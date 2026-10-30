import 'package:flutter/widgets.dart' show BuildContext;

import 'id_card.dart';

/// Web: kimlik kartı çipi tarayıcıdan okunamaz; doğrulama uygulamadan yapılır.
class IdCardReader {
  IdCardReader._();

  static const supported = false;

  static String get placementHint =>
      'Kartı telefonun arka ortasına düz yaslayın';

  static Future<NfcState> nfcState() async => NfcState.unsupported;

  static Future<bool> openNfcSettings() async => false;

  static Future<({IdCardKey? key, String? fallback})?> scanLive(
    BuildContext context,
  ) async => null;

  static Future<IdCardKey?> scanBackSide() async => null;

  static Future<IdCardData> readChip(
    IdCardKey key, {
    void Function(String status)? onStatus,
    void Function(double progress)? onProgress,
  }) async => throw const IdCardError('Kimlik okuma yalnız uygulamada.');
}
