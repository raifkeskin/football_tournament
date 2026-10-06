import 'package:flutter_test/flutter_test.dart';
import 'package:football_tournament/core/utils/realtime_signal.dart';
import 'package:football_tournament/core/utils/table_feed.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final rows = [
    {'id': '1', 'league_id': 'L', 'match_date': '2026-10-01', 'home': 0},
    {'id': '2', 'league_id': 'L', 'match_date': '2026-10-05', 'home': 0},
    {'id': '3', 'league_id': 'L', 'match_date': null, 'home': 0},
  ];
  List<String> ids(List<Map<String, dynamic>>? r) =>
      r!.map((e) => e['id'].toString()).toList();
  List<Map<String, dynamic>>? apply(RowChange c) => applyRowChange(
    rows,
    c,
    column: 'league_id',
    value: 'L',
    orderBy: 'match_date',
    ascending: true,
  );

  test('güncelleme yerinde, eksik sütunlar korunur', () {
    final r = apply(
      const RowChange(PostgresChangeEvent.update, {'id': '2', 'home': 3}, {}),
    );
    expect(ids(r), ['1', '2', '3']);
    expect(r![1]['home'], 3);
    expect(r[1]['match_date'], '2026-10-05');
  });

  test('ekleme sıraya girer, boş tarih sonda kalır', () {
    final r = apply(
      const RowChange(PostgresChangeEvent.insert, {
        'id': '4',
        'league_id': 'L',
        'match_date': '2026-10-03',
      }, {}),
    );
    expect(ids(r), ['1', '4', '2', '3']);
  });

  test('başka listeye ait silme yok sayılır, bilinen silinir', () {
    expect(
      apply(const RowChange(PostgresChangeEvent.delete, {}, {'id': '9'})),
      isNull,
    );
    expect(
      ids(apply(const RowChange(PostgresChangeEvent.delete, {}, {'id': '1'}))),
      ['2', '3'],
    );
  });

  test('filtreden çıkan satır listeden düşer', () {
    final r = apply(
      const RowChange(PostgresChangeEvent.update, {
        'id': '1',
        'league_id': 'X',
      }, {}),
    );
    expect(ids(r), ['2', '3']);
  });

  test('tarih değişince satır yeni yerine taşınır', () {
    final r = apply(
      const RowChange(PostgresChangeEvent.update, {
        'id': '1',
        'match_date': '2026-10-09',
      }, {}),
    );
    expect(ids(r), ['2', '1', '3']);
  });
}
