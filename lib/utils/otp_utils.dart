import 'dart:math';

String generateOtp6({Random? random}) {
  final r = random ?? Random.secure();
  final n = 100000 + r.nextInt(900000);
  return n.toString().padLeft(6, '0');
}

