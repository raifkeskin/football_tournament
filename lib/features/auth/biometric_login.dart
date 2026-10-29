import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/services/app_session.dart';
import '../../core/services/app_settings.dart';

/// Yüz tanıma / parmak izi ile giriş (banka uygulamaları gibi): kullanıcı
/// izin verirse telefon ve şifresi telefonun güvenli kasasında (iOS Anahtar
/// Zinciri, Android Keystore) şifreli saklanır; giriş ekranında biyometrik
/// doğrulamayla bu bilgilerle giriş yapılır. Sunucuya bir şey gitmez.
class BiometricLogin {
  BiometricLogin._();

  static const _storage = FlutterSecureStorage();
  static const _kPhone = 'bio_phone';
  static const _kPassword = 'bio_password';
  static final _auth = LocalAuthentication();

  /// Yalnız telefon uygulamasında (web'de yok).
  static bool get _platform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Yeni özellik: admin her zaman; diğerleri ayar açıksa teklif görür.
  static bool offerAllowed(AppSessionState s) =>
      s.isAdmin || AppSettings.biometricLoginEnabled.value;

  /// Cihazda kayıtlı yüz / parmak izi var mı.
  static Future<bool> available() async {
    if (!_platform) return false;
    try {
      return await _auth.isDeviceSupported() &&
          await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Düğme metni için: "Face ID" / "Yüz tanıma" ya da "Parmak izi".
  static Future<String> label() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) {
        return defaultTargetPlatform == TargetPlatform.iOS
            ? 'Face ID'
            : 'Yüz tanıma';
      }
    } catch (_) {}
    return 'Parmak izi';
  }

  /// Biyometrik doğrulama; vazgeçilir ya da başarısız olursa false.
  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  /// Kayıtlı numara (10 hane); yoksa null.
  static Future<String?> savedPhone() async {
    if (!_platform) return null;
    try {
      final p = await _storage.read(key: _kPhone);
      return (p ?? '').length == 10 ? p : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String phoneRaw10, String password) async {
    await _storage.write(key: _kPhone, value: phoneRaw10);
    await _storage.write(key: _kPassword, value: password);
  }

  static Future<({String phone, String password})?> read() async {
    try {
      final phone = await _storage.read(key: _kPhone);
      final password = await _storage.read(key: _kPassword);
      if ((phone ?? '').length != 10 || (password ?? '').isEmpty) return null;
      return (phone: phone!, password: password!);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: _kPhone);
      await _storage.delete(key: _kPassword);
    } catch (_) {}
  }

  /// Kullanıcı şifresini değiştirdi: kayıtlıysa yenisi saklanır.
  static Future<void> passwordChanged(String newPassword) async {
    if (await savedPhone() == null) return;
    try {
      await _storage.write(key: _kPassword, value: newPassword);
    } catch (_) {}
  }
}
