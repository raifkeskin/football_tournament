import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/data_versions.dart';

import 'realtime_signal.dart';
import 'resilient_stream.dart';

final Map<String, Stream<List<Map<String, dynamic>>>> _feeds = {};
final Map<String, List<Map<String, dynamic>>> _cache = {};
final _local = StreamController<(String, RowChange)>.broadcast();

/// Satırı açık listelerden düşürür. Gizlenen (silindi olarak işaretlenen)
/// satır artık okunamadığı için realtime'dan gelmez; işlemi yapan cihaz
/// listesini bununla günceller.
void announceRowRemoved(String table, String id) => _local.add((
  table,
  RowChange(PostgresChangeEvent.delete, const {}, {'id': id}),
));

Stream<RowChange> _withLocal(String table, Stream<RowChange> remote) {
  late final StreamController<RowChange> c;
  StreamSubscription<RowChange>? a;
  StreamSubscription<(String, RowChange)>? b;
  c = StreamController<RowChange>(
    onListen: () {
      a = remote.listen(c.add, onError: c.addError, onDone: c.close);
      b = _local.stream.where((e) => e.$1 == table).listen((e) => c.add(e.$2));
    },
    onCancel: () async {
      await b?.cancel();
      await a?.cancel();
    },
  );
  return c.stream;
}

/// `.stream(primaryKey: ...)` yerine kullanılan, sunucu tarafında filtrelenen
/// satır akışı:
///
/// * [column] = [value] filtresi sorguda uygulanır (tablo indirilmez);
///   verilmezse tablonun tamamı okunur (küçük sabit tablolar için).
/// * Son liste önbellekte tutulur; ekran açılınca hemen gösterilir, taze
///   veri arkadan gelir.
/// * Aynı sorgu için uygulama genelinde tek akış ve tek realtime kanalı
///   kullanılır; akış her çağrıldığında aynı nesne döner, bu yüzden
///   `build` içinde çağrılması yeniden bağlanmaya yol açmaz.
/// * Liste cihazda da saklanır; sunucudaki veri sürümü (bkz.
///   [DataVersions]) değişmediyse açılışta hiç okunmaz.
/// * Liste yalnızca bağlanırken bir kez okunur; sonrasında realtime'dan gelen
///   satır listeye işlenir (gol olunca tüm fikstür yeniden indirilmez).
///   Başka listelere ait silmeler yok sayılır. Satırda `id` yoksa liste
///   yeniden okunur.
/// * Canlı maç tabloları Broadcast konularından dinlenir (bkz.
///   [broadcastTopicFor]); konu süzgeçten çıkarılamıyorsa (ör. tarihe göre
///   maçlar) [broadcastTopics] verilir.
Stream<List<Map<String, dynamic>>> watchTableRows(
  SupabaseClient client, {
  required String table,
  String? column,
  String? value,
  String? orderBy,
  bool ascending = true,
  List<String>? broadcastTopics,

  /// Okunacak sütunlar (null: hepsi). Kişisel veri sütunu olan tablolarda
  /// (players) yalnız açık sütunlar istenir.
  String? columns,
}) {
  final key =
      '$table|$column=$value|$orderBy|$ascending|${broadcastTopics?.join(',')}'
      '${columns == null ? '' : '|$columns'}';
  // Görünen satırlar hesaba bağlı (gizli turnuva vb.): bellekteki akış ve
  // liste kullanıcıya göre ayrılır. Yoksa hesap değişince önceki hesabın
  // listesi, yeni hesabın (değişmemiş) sürüm damgasıyla geçerli sayılıyordu.
  final uid = client.auth.currentUser?.id ?? 'guest';
  final memKey = '$uid|$key';
  final scopes = _scopesFor(table, column, value);
  final persist = scopes != null && !_memoryOnly.contains(table);
  return _feeds.putIfAbsent(memKey, () {
    Future<List<Map<String, dynamic>>> fetch() async {
      // Sürüm, veriyle aynı anda istenir (fazladan tur yok).
      final stampF = scopes == null ? null : DataVersions.stamp(scopes);
      var query = client.from(table).select(columns ?? '*');
      if (column != null && value != null) query = query.eq(column, value);
      final rows = orderBy == null
          ? await query
          : await query.order(orderBy, ascending: ascending);
      final list = rows.map((e) => Map<String, dynamic>.from(e)).toList();
      _cache[memKey] = list;
      if (scopes != null) {
        final stamp = await stampF;
        unawaited(VersionedCache.save(key, list, stamp, persist: persist));
      }
      return list;
    }

    return resilientStream(() async* {
      var cached = _cache[memKey];
      if (cached == null && persist) {
        final disk = await VersionedCache.peek(key);
        if (disk is List) {
          cached = [for (final r in disk) Map<String, dynamic>.from(r as Map)];
          _cache[memKey] = cached;
        }
      }
      if (cached != null) yield cached;
      // Sunucudaki sürüm değişmediyse yeniden okunmaz (açılışta ve arka
      // plandan dönüşte tüm akışlar için tek küçük istek).
      var rows =
          cached != null &&
              scopes != null &&
              await VersionedCache.unchanged(key, scopes)
          ? cached
          : await fetch();
      if (!identical(rows, cached)) yield rows;
      // Yalnız istenen sütunlar listeye girer (realtime satırın tamamını
      // getirir).
      final keep = columns?.split(',').map((c) => c.trim()).toSet();
      await for (final raw in _withLocal(
        table,
        realtimeRowChanges(
          client,
          table: table,
          column: column,
          value: value,
          broadcastTopics: broadcastTopics,
        ),
      )) {
        final change = keep == null
            ? raw
            : RowChange(raw.type, {
                for (final e in raw.newRow.entries)
                  if (keep.contains(e.key)) e.key: e.value,
              }, raw.oldRow);
        final next = applyRowChange(
          rows,
          change,
          column: column,
          value: value,
          orderBy: orderBy,
          ascending: ascending,
        );
        if (next == null) continue; // bu listeyi ilgilendirmiyor
        rows = next.isEmpty && change.id == null ? await fetch() : next;
        _cache[memKey] = rows;
        yield rows;
      }
    });
  });
}

/// Sezona bağlı tablolar (satırda season_id var; sürüm `season:<id>`).
const _seasonTables = {
  'groups',
  'match_events',
  'match_rosters',
  'matches',
  'news',
  'player_penalties',
  'player_season_stats',
  'season_regions',
  'season_registrations',
  'season_team_players',
  'season_teams',
  'team_managers',
};

/// Sürümü tablo düzeyinde tutulan genel tablolar.
const _globalTables = {'teams', 'players', 'leagues', 'pitches', 'seasons'};

/// Sürümle doğrulanır ama cihaza yazılmaz (kişisel veri).
const _memoryOnly = {'players', 'team_managers', 'player_penalties'};

/// Akışın bağlı olduğu sürüm kapsamları; sürümü tutulmayan tabloda `null`
/// (her bağlanışta okunur).
List<String>? _scopesFor(String table, String? column, String? value) {
  if (_seasonTables.contains(table)) {
    return column == 'season_id' && value != null ? ['season:$value'] : [table];
  }
  if (_globalTables.contains(table)) return [table];
  return null;
}

/// Değişikliği listeye işler ve yeni listeyi döner; liste etkilenmiyorsa
/// `null`. Satırda `id` yoksa boş liste döner (çağıran yeniden okur).
List<Map<String, dynamic>>? applyRowChange(
  List<Map<String, dynamic>> rows,
  RowChange change, {
  String? column,
  String? value,
  String? orderBy,
  required bool ascending,
}) {
  final id = change.id;
  if (id == null) return const [];
  final index = rows.indexWhere((r) => r['id']?.toString() == id);

  // Silindi olarak işaretlenen (gizlenen) satır listeden çıkar.
  if (change.type == PostgresChangeEvent.delete ||
      change.newRow['deleted_at'] != null) {
    if (index < 0) return null;
    return [...rows]..removeAt(index);
  }

  // Güncellemede gelmeyen (ör. değişmemiş büyük) sütunlar eski değerini
  // korur.
  final row = <String, dynamic>{
    if (index >= 0) ...rows[index],
    ...change.newRow,
  };
  final next = [...rows];
  if (index >= 0) next.removeAt(index);
  if (column != null && value != null && row[column]?.toString() != value) {
    // Satır artık bu listeye ait değil.
    return index >= 0 ? next : null;
  }
  if (orderBy == null) {
    if (index >= 0) {
      next.insert(index, row);
    } else {
      next.add(row);
    }
    return next;
  }
  // Sıralı listede yerine koy (eşit değerlerde mevcut sıra korunur).
  var at = next.length;
  for (var i = 0; i < next.length; i++) {
    if (_compare(row[orderBy], next[i][orderBy], ascending) < 0) {
      at = i;
      break;
    }
  }
  next.insert(at, row);
  return next;
}

/// Postgres sırasıyla aynı: artan sırada boşlar sonda, azalanda başta.
int _compare(Object? a, Object? b, bool ascending) {
  if (a == null && b == null) return 0;
  if (a == null) return 1 * (ascending ? 1 : -1);
  if (b == null) return -1 * (ascending ? 1 : -1);
  final int c;
  if (a is num && b is num) {
    c = a.compareTo(b);
  } else if (a is bool && b is bool) {
    c = a == b ? 0 : (a ? 1 : -1);
  } else {
    c = a.toString().compareTo(b.toString());
  }
  return ascending ? c : -c;
}
