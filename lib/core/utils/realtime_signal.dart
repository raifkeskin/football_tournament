import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'stream_scope.dart';

/// Realtime'dan gelen tek bir satır değişikliği.
class RowChange {
  const RowChange(this.type, this.newRow, this.oldRow);

  final PostgresChangeEvent type;

  /// Ekleme/güncellemede satırın yeni hali (silmede boş).
  final Map<String, dynamic> newRow;

  /// Silmede yalnızca birincil anahtar bulunur.
  final Map<String, dynamic> oldRow;

  String? get id {
    final v = (type == PostgresChangeEvent.delete ? oldRow : newRow)['id'];
    return v?.toString();
  }
}

/// Bir tablodaki `column = value` satırlarının değişikliklerini (ekleme,
/// güncelleme, silme) satır verisiyle birlikte yayar.
///
/// Filtreli realtime aboneliğinde silme olayları gelmediği için (silinen
/// satırda yalnızca birincil anahtar olur) silmeler ayrıca filtresiz
/// dinlenir; bu olaylar yalnızca id taşır, ilgili olup olmadığına dinleyen
/// taraf karar verir.
///
/// [column] verilmezse tablodaki her değişiklik gelir.
///
/// Kanal hata verirse akış hata ile biter; `resilientStream` ile sarılırsa
/// otomatik yeniden bağlanır.
Stream<RowChange> realtimeRowChanges(
  SupabaseClient client, {
  required String table,
  String? column,
  String? value,
  List<String>? broadcastTopics,
}) {
  // Canlı maç tabloları Broadcast konularından dinlenir (bkz.
  // 20261018190000_match_broadcast.sql): değişiklik başına tek mesaj,
  // izleyici başına veritabanı sorgusu yok.
  final topics = broadcastTopics ?? [?broadcastTopicFor(table, column, value)];
  if (topics.isNotEmpty && column != null && value != null) {
    return _broadcastRowChanges(
      client,
      topics: topics,
      table: table,
      column: column,
      value: value,
    );
  }
  late StreamController<RowChange> controller;
  RealtimeChannel? channel;
  void Function()? unregister;

  Future<void> close() async {
    unregister?.call();
    unregister = null;
    final c = channel;
    channel = null;
    if (c != null) await client.removeChannel(c);
  }

  controller = StreamController<RowChange>(
    onListen: () {
      void forward(PostgresChangePayload p) {
        if (controller.isClosed) return;
        controller.add(
          RowChange(
            p.eventType,
            Map<String, dynamic>.from(p.newRecord),
            Map<String, dynamic>.from(p.oldRecord),
          ),
        );
      }

      final name =
          'sig:$table:$column=$value:${DateTime.now().microsecondsSinceEpoch}';
      final base = client.channel(name);
      // Kanal oluşturulunca istemcinin listesine girer; kapatma bunu da
      // kaldırsın.
      channel = base;
      final RealtimeChannel configured;
      if (column == null || value == null) {
        configured = base.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: forward,
        );
      } else {
        final filter = PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: column,
          value: value,
        );
        configured = base
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: table,
              filter: filter,
              callback: forward,
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.update,
              schema: 'public',
              table: table,
              filter: filter,
              callback: forward,
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.delete,
              schema: 'public',
              table: table,
              callback: forward,
            );
      }
      // Akışı dinleyen gövde bir kapsam içindeyse (resilientStream), kapsam
      // kapanınca kanal `await for`'un bitmesini beklemeden kapatılır.
      unregister = StreamScope.current?.add(() {
        close();
        if (!controller.isClosed) controller.close();
      });
      // Kapsam zaten kapanmışsa kanal hiç açılmaz.
      if (controller.isClosed) return;
      channel = configured.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) {
          if (!controller.isClosed) {
            controller.addError(error ?? 'realtime $status');
          }
        }
      });
    },
    onCancel: close,
  );
  return controller.stream;
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// [table] içindeki [column] = [value] satırlarının yayınlandığı Broadcast
/// konusu; bu abonelik için konu yoksa `null` (postgres_changes kullanılır).
String? broadcastTopicFor(String table, String? column, String? value) {
  if (value == null || !_uuid.hasMatch(value)) return null;
  return switch ((table, column)) {
    ('matches', 'id') ||
    ('match_events', 'match_id') ||
    ('match_rosters', 'match_id') => 'match:$value',
    ('matches', 'season_id') ||
    ('match_events', 'season_id') => 'season:$value',
    ('matches', 'league_id') => 'league:$value',
    _ => null,
  };
}

/// Bir Broadcast konusunun uygulama genelindeki tek kanalı: o konuyu dinleyen
/// tüm akışlar bu kanalı paylaşır (aynı konuya ikinci katılım sunucuda
/// öncekini kapatır). Son dinleyici gidince kanal kapanır.
class _TopicHub {
  _TopicHub(this.client, this.topic);

  final SupabaseClient client;
  final String topic;
  final _out = StreamController<RowChange>.broadcast(sync: true);
  final _tableOf = Expando<String>();
  RealtimeChannel? _channel;
  int _refs = 0;

  static final Map<String, _TopicHub> _hubs = {};

  static _TopicHub retain(SupabaseClient client, String topic) {
    final key = '${identityHashCode(client)}|$topic';
    final hub = _hubs.putIfAbsent(key, () => _TopicHub(client, topic));
    if (hub._refs++ == 0) hub._open();
    return hub;
  }

  Stream<RowChange> get changes => _out.stream;
  String? tableOf(RowChange c) => _tableOf[c];

  void _open() {
    final channel = client.channel(
      topic,
      opts: const RealtimeChannelConfig(private: true),
    );
    _channel = channel;
    channel
        .onBroadcast(
          event: '*',
          callback: (m) {
            final inner = m['payload'];
            final p = inner is Map ? Map<String, dynamic>.from(inner) : m;
            final type = switch ((p['operation'] ?? '').toString()) {
              'INSERT' => PostgresChangeEvent.insert,
              'UPDATE' => PostgresChangeEvent.update,
              'DELETE' => PostgresChangeEvent.delete,
              _ => null,
            };
            if (type == null || _out.isClosed) return;
            Map<String, dynamic> row(Object? v) =>
                v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
            final change = RowChange(
              type,
              type == PostgresChangeEvent.delete
                  ? <String, dynamic>{}
                  : row(p['record']),
              row(p['old_record']),
            );
            _tableOf[change] = (p['table'] ?? m['event'] ?? '').toString();
            _out.add(change);
          },
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            if (!_out.isClosed) _out.addError(error ?? 'realtime $status');
          }
        });
  }

  Future<void> release() async {
    if (--_refs > 0) return;
    _hubs.removeWhere((_, h) => identical(h, this));
    final c = _channel;
    _channel = null;
    if (!_out.isClosed) await _out.close();
    if (c != null) await client.removeChannel(c);
  }
}

/// Broadcast konularından [table] satırlarının [column] = [value] olan
/// değişiklikleri. Silmede eski satırın tamamı gelir (postgres_changes'ten
/// farklı olarak süzülebilir).
Stream<RowChange> _broadcastRowChanges(
  SupabaseClient client, {
  required List<String> topics,
  required String table,
  required String column,
  required String value,
}) {
  late StreamController<RowChange> controller;
  final hubs = <_TopicHub>[];
  final subs = <StreamSubscription<RowChange>>[];
  void Function()? unregister;
  var closed = false;

  Future<void> close() async {
    if (closed) return;
    closed = true;
    unregister?.call();
    unregister = null;
    for (final s in subs) {
      await s.cancel();
    }
    subs.clear();
    for (final h in hubs) {
      await h.release();
    }
    hubs.clear();
  }

  bool matches(RowChange c) {
    final now = c.newRow[column]?.toString();
    final before = c.oldRow[column]?.toString();
    // Güncellemede satır listeden çıkmış olabilir: eski değer de bakılır.
    return now == value || before == value;
  }

  controller = StreamController<RowChange>(
    onListen: () {
      unregister = StreamScope.current?.add(() {
        close();
        if (!controller.isClosed) controller.close();
      });
      if (controller.isClosed) return;
      for (final topic in topics.toSet()) {
        final hub = _TopicHub.retain(client, topic);
        hubs.add(hub);
        subs.add(
          hub.changes.listen(
            (c) {
              if (controller.isClosed) return;
              if (hub.tableOf(c) != table || !matches(c)) return;
              controller.add(c);
            },
            onError: (Object e, StackTrace s) {
              if (!controller.isClosed) controller.addError(e, s);
            },
            onDone: () {
              if (!controller.isClosed) controller.close();
            },
          ),
        );
      }
    },
    onCancel: close,
  );
  return controller.stream;
}

/// [realtimeRowChanges] üzerine "değişti" sinyali: veri taşımaz; dinleyen
/// taraf listeyi kendi filtreli sorgusuyla yeniden okur.
///
/// * [knownIds] verilirse id'si bu kümede olmayan silmeler yok sayılır
///   (başka maçın/turnuvanın silmesi yeniden okumaya yol açmaz).
/// * [relevant] verilirse yalnızca true dönen değişiklikler sinyal üretir.
/// * Art arda gelen değişiklikler [debounce] süresi içinde tek sinyalde
///   birleşir (ör. kadro kaydı: önce silme, sonra toplu ekleme).
Stream<void> realtimeChangeSignal(
  SupabaseClient client, {
  required String table,
  String? column,
  String? value,
  Set<String> Function()? knownIds,
  bool Function(RowChange change)? relevant,
  Duration debounce = const Duration(milliseconds: 300),
}) {
  late StreamController<void> controller;
  StreamSubscription<RowChange>? sub;
  Timer? timer;

  controller = StreamController<void>(
    onListen: () {
      sub =
          realtimeRowChanges(
            client,
            table: table,
            column: column,
            value: value,
          ).listen(
            (c) {
              if (c.type == PostgresChangeEvent.delete && knownIds != null) {
                final id = c.id;
                if (id != null && !knownIds().contains(id)) return;
              }
              if (relevant != null && !relevant(c)) return;
              timer ??= Timer(debounce, () {
                timer = null;
                if (!controller.isClosed) controller.add(null);
              });
            },
            onError: (Object e, StackTrace s) {
              if (!controller.isClosed) controller.addError(e, s);
            },
            // Kanal kapsamla kapatılınca sinyal de biter (`await for` çıkar).
            onDone: () {
              timer?.cancel();
              timer = null;
              if (!controller.isClosed) controller.close();
            },
          );
    },
    onCancel: () async {
      timer?.cancel();
      timer = null;
      await sub?.cancel();
      sub = null;
    },
  );
  return controller.stream;
}
