import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'league_access.dart';

/// Uygulama geneli ayarlar (`app_settings` tablosu; herkes okur, admin yazar).
class AppSettings {
  AppSettings._();

  static const _kPrivateLeagues = 'private_leagues_enabled';
  static const _kBottomNav = 'bottom_nav_enabled';
  static const _kSmsOtp = 'sms_otp_enabled';
  static const _kSmsOtpProvider = 'sms_otp_provider';

  /// Gizli turnuva özelliği. Kapalıyken "Turnuva Kodu Gir" ve "Gizli turnuva"
  /// alanları gizlenir; veritabanı da tüm turnuvaları herkese açar.
  static final privateLeaguesEnabled = ValueNotifier<bool>(false);

  /// Ana ekranlardaki alt gezinme çubuğu. Kapalıyken gezinme yan menü ve
  /// kaydırma ile (kayıt yoksa açık).
  static final bottomNavEnabled = ValueNotifier<bool>(true);

  /// SMS ile doğrulama. Açıkken Kayıt Ol / Şifremi Unuttum telefona gelen
  /// kodla çalışır; kapalıyken talep → admin onayı → WhatsApp akışı.
  static final smsOtpEnabled = ValueNotifier<bool>(false);

  /// SMS test modu: kod SMS yerine adminlerin Telegram'ına gider
  /// (`sms_otp_provider` = 'telegram'). Kapalıyken İletiMerkezi kullanılır.
  static final smsOtpTestMode = ValueNotifier<bool>(true);

  static SupabaseClient get _sb => Supabase.instance.client;

  static Future<void> load() async {
    try {
      final rows = await _sb.from('app_settings').select('key, value');
      for (final r in rows) {
        if (r['key'] == _kPrivateLeagues) {
          privateLeaguesEnabled.value = r['value'] == true;
        } else if (r['key'] == _kBottomNav) {
          bottomNavEnabled.value = r['value'] != false;
        } else if (r['key'] == _kSmsOtp) {
          smsOtpEnabled.value = r['value'] == true;
        } else if (r['key'] == _kSmsOtpProvider) {
          smsOtpTestMode.value = r['value'] != 'iletimerkezi';
        }
      }
    } catch (e) {
      debugPrint('Uygulama ayarları okunamadı: $e');
    }
  }

  /// Yalnızca admin. Görünürlük değiştiği için ekranlar verilerini yeniler.
  static Future<void> setPrivateLeaguesEnabled(bool enabled) async {
    await _sb.from('app_settings').upsert({
      'key': _kPrivateLeagues,
      'value': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    privateLeaguesEnabled.value = enabled;
    LeagueAccess.bump();
  }

  /// Yalnızca admin.
  static Future<void> setBottomNavEnabled(bool enabled) async {
    await _sb.from('app_settings').upsert({
      'key': _kBottomNav,
      'value': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    bottomNavEnabled.value = enabled;
  }

  /// Yalnızca admin.
  static Future<void> setSmsOtpEnabled(bool enabled) async {
    await _sb.from('app_settings').upsert({
      'key': _kSmsOtp,
      'value': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    smsOtpEnabled.value = enabled;
  }

  /// Yalnızca admin.
  static Future<void> setSmsOtpTestMode(bool testMode) async {
    await _sb.from('app_settings').upsert({
      'key': _kSmsOtpProvider,
      'value': testMode ? 'telegram' : 'iletimerkezi',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    smsOtpTestMode.value = testMode;
  }
}
