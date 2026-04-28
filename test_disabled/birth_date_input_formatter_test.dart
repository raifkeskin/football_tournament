import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_tournament/features/team/screens/team_squad_screen.dart';

void main() {
  test('BirthDateInputFormatter formats 01011990 as 01/01/1990', () {
    final f = BirthDateInputFormatter();
    var v = const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    const input = '01011990';
    for (final ch in input.split('')) {
      final next = TextEditingValue(
        text: v.text + ch,
        selection: TextSelection.collapsed(offset: v.text.length + 1),
      );
      v = f.formatEditUpdate(v, next);
    }
    expect(v.text, '01/01/1990');
  });

  test('BirthDateInputFormatter allows deleting a slash without re-adding it', () {
    final f = BirthDateInputFormatter();
    final oldV = const TextEditingValue(
      text: '01/01/1990',
      selection: TextSelection.collapsed(offset: 3),
    );
    final newV = const TextEditingValue(
      text: '0101/1990',
      selection: TextSelection.collapsed(offset: 2),
    );
    final out = f.formatEditUpdate(oldV, newV);
    expect(out.text, '0101/1990');
  });

  test('BirthDateInputFormatter max length is 10', () {
    final f = BirthDateInputFormatter();
    var v = const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    const input = '010119901234';
    for (final ch in input.split('')) {
      final next = TextEditingValue(
        text: v.text + ch,
        selection: TextSelection.collapsed(offset: v.text.length + 1),
      );
      v = f.formatEditUpdate(v, next);
    }
    expect(v.text.length, lessThanOrEqualTo(10));
  });
}

