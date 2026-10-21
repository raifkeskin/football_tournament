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
  static const _kMatchPhotoLimit = 'match_photo_limit';
  static const _kTournamentRequests = 'tournament_requests_enabled';
  static const _kSelfRegistration = 'self_registration_enabled';
  static const _kIdentity = 'identity_verification_enabled';
  static const _kIdentityUsers = 'identity_verification_users';

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

  /// Bir maça eklenebilecek en fazla fotoğraf (yayın ve albüm linki hariç).
  /// Veritabanı da aynı sınırı uygular (match_media tetikleyicisi).
  static final matchPhotoLimit = ValueNotifier<int>(20);

  /// "Turnuvanı Kur" girişleri herkese açık mı (admin her zaman görür).
  static final tournamentRequestsEnabled = ValueNotifier<bool>(false);

  /// Yeni Kayıt Ol akışı (Futbolcu Profili kimlikle / Turnuva Sorumlusu).
  /// Kapalıyken eski kayıt talebi akışı kullanılır.
  static final selfRegistrationEnabled = ValueNotifier<bool>(false);

  /// Kimlik doğrulama herkese açık mı; kapalıyken yalnız admin ve
  /// [identityVerificationUsers] (deneme hesapları) görür.
  static final identityVerificationEnabled = ValueNotifier<bool>(false);
  static final identityVerificationUsers = ValueNotifier<Set<String>>({});

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
        } else if (r['key'] == _kTournamentRequests) {
          tournamentRequestsEnabled.value = r['value'] == true;
        } else if (r['key'] == _kSelfRegistration) {
          selfRegistrationEnabled.value = r['value'] == true;
        } else if (r['key'] == _kIdentity) {
          identityVerificationEnabled.value = r['value'] == true;
        } else if (r['key'] == _kIdentityUsers) {
          final v = r['value'];
          identityVerificationUsers.value = {
            if (v is List)
              for (final x in v) x.toString(),
          };
        } else if (r['key'] == _kMatchPhotoLimit) {
          final v = r['value'];
          if (v is num && v > 0) matchPhotoLimit.value = v.toInt();
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

  /// Yalnızca admin.
  static Future<void> setMatchPhotoLimit(int limit) async {
    await _sb.from('app_settings').upsert({
      'key': _kMatchPhotoLimit,
      'value': limit,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    matchPhotoLimit.value = limit;
  }

  /// Yalnızca admin.
  static Future<void> setTournamentRequestsEnabled(bool enabled) async {
    await _sb.from('app_settings').upsert({
      'key': _kTournamentRequests,
      'value': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    tournamentRequestsEnabled.value = enabled;
  }

  /// Yalnızca admin.
  static Future<void> setSelfRegistrationEnabled(bool enabled) async {
    await _sb.from('app_settings').upsert({
      'key': _kSelfRegistration,
      'value': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    selfRegistrationEnabled.value = enabled;
  }
}
