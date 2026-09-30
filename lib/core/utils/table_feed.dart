import 'package:supabase_flutter/supabase_flutter.dart';

import 'realtime_signal.dart';
import 'resilient_stream.dart';

final Map<String, Stream<List<Map<String, dynamic>>>> _feeds = {};
final Map<String, List<Map<String, dynamic>>> _cache = {};

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
/// * Realtime yalnızca "değişti" sinyali verir; liste her seferinde yeniden
///   sorgulanır (silmeler de yakalanır).
Stream<List<Map<String, dynamic>>> watchTableRows(
  SupabaseClient client, {
  required String table,
  String? column,
  String? value,
  String? orderBy,
  bool ascending = true,
}) {
  final key = '$table|$column=$value|$orderBy|$ascending';
  return _feeds.putIfAbsent(key, () {
    Future<List<Map<String, dynamic>>> fetch() async {
      var query = client.from(table).select();
      if (column != null && value != null) query = query.eq(column, value);
      final rows = orderBy == null
          ? await query
          : await query.order(orderBy, ascending: ascending);
      final list = rows.map((e) => Map<String, dynamic>.from(e)).toList();
      _cache[key] = list;
      return list;
    }

    return resilientStream(() async* {
      final cached = _cache[key];
      if (cached != null) yield cached;
      yield await fetch();
      await for (final _ in realtimeChangeSignal(
        client,
        table: table,
        column: column,
        value: value,
      )) {
        yield await fetch();
      }
    });
  });
}
