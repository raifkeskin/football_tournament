import 'package:flutter_test/flutter_test.dart';
import 'package:football_tournament/features/match/utils/fixture_draw.dart';

void main() {
  test('açılış maçı 1. haftanın ilk maçı olur, fikstür geçerli', () {
    for (final n in [4, 5, 7, 8, 10]) {
      final ids = [for (var i = 0; i < n; i++) 't$i'];
      for (final dbl in [false, true]) {
        for (var k = 0; k < 20; k++) {
          final w = drawLeagueFixture(ids,
              doubleRound: dbl, opening: (home: 't3', away: 't1'));
          expect(w.first.pairs.first, (home: 't3', away: 't1'));
          final seen = <String>{};
          for (final week in w) {
            final inWeek = <String>{};
            for (final p in week.pairs) {
              expect(inWeek.add(p.home), true);
              expect(inWeek.add(p.away), true);
              seen.add('${p.home}-${p.away}');
            }
          }
          expect(seen.length, n * (n - 1) ~/ 2 * (dbl ? 2 : 1));
        }
      }
    }
  });
}
