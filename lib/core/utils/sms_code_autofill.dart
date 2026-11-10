import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:smart_auth/smart_auth.dart';

/// Android: gelen doğrulama SMS'ini (kullanıcı onayıyla) okuyup kodu verir.
/// iPhone'da klavyenin "Mesajlardan" önerisi zaten çalışır; web'de yoktur.
/// Mesajın içeriği uygulamaya yalnız kullanıcı "İzin ver" derse geçer.
class SmsCodeAutofill {
  SmsCodeAutofill._();

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// SMS gelene (en çok 5 dk) ya da [stop] çağrılana kadar bekler; kod
  /// bulunursa [onCode] ile 4-6 haneli kodu döndürür.
  static Future<void> listen(void Function(String code) onCode) async {
    if (!supported) return;
    try {
      final r = await SmartAuth.instance.getSmsWithUserConsentApi(
        matcher: r'\b\d{6}\b',
      );
      final code = r.data?.code;
      if (r.hasData && code != null && code.length == 6) onCode(code);
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!supported) return;
    try {
      await SmartAuth.instance.removeUserConsentApiListener();
    } catch (_) {}
  }
}
