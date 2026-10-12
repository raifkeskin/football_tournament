import 'package:flutter_test/flutter_test.dart';
import 'package:football_tournament/features/auth/password_input.dart';

void main() {
  test('kolay tahmin edilen şifreler zayıf sayılır', () {
    for (final p in [
      '123456',
      '654321',
      '456789',
      '111111',
      '000000',
      '121212',
      '123123',
      '112233',
      'abc123',
      'ABC123',
    ]) {
      expect(PasswordRules.isWeak(p), isTrue, reason: p);
    }
  });

  test('telefon numarasının parçası zayıf sayılır', () {
    expect(PasswordRules.isWeak('089589', phone: '905375089589'), isTrue);
    expect(PasswordRules.isWeak('5375089589', phone: '5375089589'), isTrue);
    expect(PasswordRules.isWeak('482915', phone: '905375089589'), isFalse);
  });

  test('sıradan olmayan şifreler geçer', () {
    for (final p in ['482915', '730261', 'kartal1', 'Ali.1985', '1357924']) {
      expect(PasswordRules.isWeak(p), isFalse, reason: p);
    }
  });
}
