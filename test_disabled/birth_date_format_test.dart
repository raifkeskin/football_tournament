import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_tournament/features/match/models/match.dart';
import 'package:football_tournament/features/team/screens/team_squad_screen.dart';

void main() {
  group('Birth date formatting', () {
    test('db YYYY-MM-DD -> ui DD-MM-YYYY', () {
      expect(birthDateDbToUi('2026-04-26'), '26-04-2026');
    });

    test('ui DD-MM-YYYY -> db YYYY-MM-DD', () {
      expect(birthDateUiToDb('26-04-2026'), '2026-04-26');
    });

    test('PlayerModel.fromMap normalizes db YYYY-MM-DD and UI shows DD-MM-YYYY', () {
      final p = PlayerModel.fromMap(
        {
          'name': 'Test Player',
          'birth_date': '2026-04-26',
          'role': 'Futbolcu',
        },
        'p1',
      );

      expect(p.birthDate, '26/04/2026');
      expect(birthDateDbToUi(p.birthDate), '26-04-2026');
    });

    test('BirthDateInputFormatter formats digits to DD-MM-YYYY', () {
      final f = BirthDateInputFormatter();
      final v = f.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(
          text: '26042026',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      expect(v.text, '26-04-2026');
    });
  });
}

