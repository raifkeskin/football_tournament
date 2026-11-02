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
  static const _kManualPlayerCreate = 'manual_player_create_enabled';
  static const _kSuspendedTab = 'suspended_tab_enabled';
  static const _kWeeklyPicks = 'weekly_picks_enabled';
  static const _kReferees = 'referees_enabled';
  static const _kPositionsTab = 'positions_tab_enabled';
  static const _kRosterAdd = 'roster_add_shortcut_enabled';
  static const _kBiometricLogin = 'biometric_login_enabled';
  static const _kMatchPosterDesigns = 'match_poster_designs_enabled';
  static const _kMatchInsights = 'match_insights_enabled';
  static const _kRegulations = 'regulations_enabled';
  static const _kLineupCutouts = 'lineup_cutouts_enabled';
  static const _kPhotoStandard = 'photo_standard_enabled';
  static const _kRosterAddUsers = 'roster_add_shortcut_users';
  static const _kNewsScreen = 'news_screen_enabled';
  static const _kNewsComments = 'news_comments_enabled';

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

  /// Maç başına fotoğraf sınırı yok mu (ayar 0).
  static bool get matchPhotosUnlimited => matchPhotoLimit.value == 0;

  /// "Turnuvanı Kur" girişleri herkese açık mı (admin her zaman görür).
  static final tournamentRequestsEnabled = ValueNotifier<bool>(false);

  /// Yeni Kayıt Ol akışı (Futbolcu Profili kimlikle / Turnuva Sorumlusu).
  /// Kapalıyken eski kayıt talebi akışı kullanılır.
  static final selfRegistrationEnabled = ValueNotifier<bool>(false);

  /// Kimlik doğrulama Aktif/Pasif (Kimlik Yönetimi). Aktifken futbolcu
  /// kendi profilini, sorumlular kadrolarını doğrular; pasifken yalnız admin
  /// ve [identityVerificationUsers] (deneme hesapları) görür. Kayıt Ol'daki
  /// kimlikle kayıt bu anahtardan bağımsızdır.
  static final identityVerificationEnabled = ValueNotifier<bool>(false);
  static final identityVerificationUsers = ValueNotifier<Set<String>>({});

  /// Elle yeni futbolcu ekleme (lisans listesi, kadro talebi). Kapalıyken
  /// yalnız admin ekler; diğerleri futbolcunun uygulamadan kaydını bekleyip
  /// listeden seçer. Veritabanı da aynı kuralı uygular.
  static final manualPlayerCreateEnabled = ValueNotifier<bool>(true);

  /// İstatistiklerdeki "Cezalı" sekmesi herkese açık mı; kapalıyken yalnız
  /// admin görür.
  static final suspendedTabEnabled = ValueNotifier<bool>(false);

  /// Haftanın Seçimi (haftanın golü / oyuncusu / takımı) herkese açık mı;
  /// kapalıyken yalnız admin seçer. Veritabanı da aynı kuralı uygular.
  static final weeklyPicksEnabled = ValueNotifier<bool>(false);

  /// Hakemler (hakem listesi, maça hakem atama, hakem girişi) herkese açık
  /// mı; kapalıyken yalnız admin. Veritabanı da aynı kuralı uygular.
  static final refereesEnabled = ValueNotifier<bool>(false);

  /// Takım sorumlusu menüsünde "Kadroya Futbolcu Ekle" kısayolu herkese açık
  /// mı; kapalıyken yalnız admin ve [rosterAddShortcutUsers] görür.
  static final rosterAddShortcutEnabled = ValueNotifier<bool>(false);

  /// Yüz tanıma / parmak izi ile giriş teklifi herkese açık mı (admin her zaman).
  static final biometricLoginEnabled = ValueNotifier<bool>(false);

  /// Maç afişinde Formalar / Çapraz / Takım tasarımları herkese açık mı
  /// (admin her zaman görür).
  static final matchPosterDesignsEnabled = ValueNotifier<bool>(false);

  /// Kadro/Diziliş olay ikonları, futbolcu puanı ve "Olay ekle" herkese
  /// açık mı (admin her zaman görür).
  static final matchInsightsEnabled = ValueNotifier<bool>(false);

  /// Turnuva talimatnamesi herkese açık mı (admin her zaman görür).
  static final regulationsEnabled = ValueNotifier<bool>(false);

  /// Dizilişte (Profil görünümü) dekupe oyuncu fotoğrafı herkese açık mı
  /// (admin her zaman görür).
  static final lineupCutoutsEnabled = ValueNotifier<bool>(false);

  /// Profil fotoğrafı standardı (kadraj kılavuzu + yüz kontrolü uyarısı)
  /// herkese açık mı (admin her zaman görür).
  static final photoStandardEnabled = ValueNotifier<bool>(false);
  static final rosterAddShortcutUsers = ValueNotifier<Set<String>>({});

  /// Yeni haberler (ana sayfada kaydırılan fotoğraflı kartlar, ayrı
  /// Haberler ekranı, gazete küpürü detay) herkese açık mı; kapalıyken
  /// yalnız admin görür, diğerleri eski haber kartını görür.
  static final newsScreenEnabled = ValueNotifier<bool>(false);

  /// Haberlerde tribün tepkileri ve yorumlar herkese açık mı; kapalıyken
  /// yalnız admin görür. Veritabanı da aynı kuralı uygular.
  static final newsCommentsEnabled = ValueNotifier<bool>(false);

  /// Oyuncu kartındaki "Mevki" sekmesi (asıl mevki + oynayabildiği en çok 3
  /// mevki) herkese açık mı; kapalıyken yalnız admin görür. Veritabanı da
  /// kaydı aynı anahtarla açar (`positions_tab_allowed`).
  static final positionsTabEnabled = ValueNotifier<bool>(false);

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
        } else if (r['key'] == _kManualPlayerCreate) {
          manualPlayerCreateEnabled.value = r['value'] != false;
        } else if (r['key'] == _kWeeklyPicks) {
          weeklyPicksEnabled.value = r['value'] == true;
        } else if (r['key'] == _kReferees) {
          refereesEnabled.value = r['value'] == true;
        } else if (r['key'] == _kRosterAdd) {
          rosterAddShortcutEnabled.value = r['value'] == true;
        } else if (r['key'] == _kNewsScreen) {
          newsScreenEnabled.value = r['value'] == true;
        } else if (r['key'] == _kNewsComments) {
          newsCommentsEnabled.value = r['value'] == true;
        } else if (r['key'] == _kBiometricLogin) {
          biometricLoginEnabled.value = r['value'] == true;
        } else if (r['key'] == _kMatchPosterDesigns) {
          matchPosterDesignsEnabled.value = r['value'] == true;
        } else if (r['key'] == _kMatchInsights) {
          matchInsightsEnabled.value = r['value'] == true;
        } else if (r['key'] == _kRegulations) {
          regulationsEnabled.value = r['value'] == true;
        } else if (r['key'] == _kLineupCutouts) {
          lineupCutoutsEnabled.value = r['value'] == true;
        } else if (r['key'] == _kPhotoStandard) {
          photoStandardEnabled.value = r['value'] == true;
        } else if (r['key'] == _kRosterAddUsers) {
          final v = r['value'];
          rosterAddShortcutUsers.value = {
            if (v is List)
              for (final x in v) x.toString(),
          };
        } else if (r['key'] == _kSuspendedTab) {
          suspendedTabEnabled.value = r['value'] == true;
        } else if (r['key'] == _kPositionsTab) {
          positionsTabEnabled.value = r['value'] == true;
        } else if (r['key'] == _kMatchPhotoLimit) {
          final v = r['value'];
          // 0: sınırsız.
          if (v is num && v >= 0) matchPhotoLimit.value = v.toInt();
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

  /// Yalnızca admin. Kimlik doğrulamayı açar ya da kapatır.
  static Future<void> setIdentityVerificationEnabled(bool enabled) async {
    await _sb.from('app_settings').upsert({
      'key': _kIdentity,
      'value': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    identityVerificationEnabled.value = enabled;
  }

  static Future<void> setManualPlayerCreateEnabled(bool enabled) async {
    await _sb.from('app_settings').upsert({
      'key': _kManualPlayerCreate,
      'value': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    manualPlayerCreateEnabled.value = enabled;
  }

  static Future<void> setSelfRegistrationEnabled(bool enabled) async {
    await _sb.from('app_settings').upsert({
      'key': _kSelfRegistration,
      'value': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    selfRegistrationEnabled.value = enabled;
  }
}
