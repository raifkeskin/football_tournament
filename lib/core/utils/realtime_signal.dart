import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

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
}) {
  late StreamController<RowChange> controller;
  RealtimeChannel? channel;

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
      channel = configured.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) {
          if (!controller.isClosed) {
            controller.addError(error ?? 'realtime $status');
          }
        }
      });
    },
    onCancel: () async {
      final c = channel;
      channel = null;
      if (c != null) await client.removeChannel(c);
    },
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
