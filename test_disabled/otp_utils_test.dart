import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:football_tournament/core/utils/otp_utils.dart';

void main() {
  test('generateOtp6 returns 6 digit numeric string', () {
    final r = Random(1);
    final otp = generateOtp6(random: r);
    expect(otp.length, 6);
    expect(RegExp(r'^\d{6}$').hasMatch(otp), true);
  });
}

