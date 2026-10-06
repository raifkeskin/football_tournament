import 'package:flutter/foundation.dart';
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
/// * Liste yalnızca bağlanırken bir kez okunur; sonrasında realtime'dan gelen
///   satır listeye işlenir (gol olunca tüm fikstür yeniden indirilmez).
///   Başka listelere ait silmeler yok sayılır. Satırda `id` yoksa liste
///   yeniden okunur.
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
      var rows = await fetch();
      yield rows;
      await for (final change in realtimeRowChanges(
        client,
        table: table,
        column: column,
        value: value,
      )) {
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
        _cache[key] = rows;
        yield rows;
      }
    });
  });
}

/// Değişikliği listeye işler ve yeni listeyi döner; liste etkilenmiyorsa
/// `null`. Satırda `id` yoksa boş liste döner (çağıran yeniden okur).
@visibleForTesting
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

  if (change.type == PostgresChangeEvent.delete) {
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
  if (column != null &&
      value != null &&
      row[column]?.toString() != value) {
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
