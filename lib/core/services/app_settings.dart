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
  static const _kWeekAwards = 'week_awards_enabled';
  static const _kPlayerPoster = 'player_poster_enabled';
  static const _kPlayerPosterUsers = 'player_poster_users';
  static const _kMyWeek = 'my_week_enabled';
  static const _kReferees = 'referees_enabled';
  static const _kPositionsTab = 'positions_tab_enabled';
  static const _kRosterAdd = 'roster_add_shortcut_enabled';
  static const _kBiometricLogin = 'biometric_login_enabled';
  static const _kMatchPosterDesigns = 'match_poster_designs_enabled';
  static const _kMatchInsights = 'match_insights_enabled';
  static const _kRegulations = 'regulations_enabled';
  static const _kLineupCutouts = 'lineup_cutouts_enabled';
  static const _kLineupInRoster = 'lineup_in_roster_enabled';
  static const _kPhotoStandard = 'photo_standard_enabled';
  static const _kRosterIdScan = 'roster_id_scan_enabled';
  static const _kGoalClipMp4 = 'goal_clip_mp4_enabled';
  static const _kFollowList = 'follow_list_enabled';
  static const _kSearch = 'search_enabled';
  static const _kMatchBundle = 'match_bundle_enabled';
  static const _kMyWeekPoster = 'my_week_poster_enabled';
  static const _kLivePitch = 'live_pitch_enabled';
  static const _kAdminPanel = 'admin_panel_enabled';
  static const _kIbraz = 'ibraz_enabled';
  static const _kPasswordChange = 'password_change_enabled';
  static const _kRosterAddUsers = 'roster_add_shortcut_users';
  static const _kNewsScreen = 'news_screen_enabled';
  static const _kNewsComments = 'news_comments_enabled';
  static const _kSeasonHealth = 'season_health_enabled';
  static const _kConsentPreviewUsers = 'consent_preview_users';

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

  /// Haftanın Enleri bülteni herkese açık mı; kapalıyken yalnız admin
  /// hazırlar. Veritabanı da aynı kuralı uygular.
  static final weekAwardsEnabled = ValueNotifier<bool>(false);

  /// Bireysel sezon afişi ve maç fotoğrafında "Bu benim" yıldızı herkese
  /// açık mı; kapalıyken yalnız admin görür.
  static final playerPosterEnabled = ValueNotifier<bool>(false);

  /// Kapalıyken de açık olan deneme hesapları (auth kullanıcı id'leri).
  static final playerPosterUsers = ValueNotifier<Set<String>>({});

  /// Ana sayfada "Bu hafta sen" kartı ve selamlamadaki profil kısayolu
  /// herkese açık mı; kapalıyken yalnız admin görür.
  static final myWeekEnabled = ValueNotifier<bool>(false);

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

  /// Maç detayında diziliş Kadro sekmesinin üstünde (Diziliş sekmesi yok)
  /// herkese açık mı (admin her zaman görür).
  static final lineupInRosterEnabled = ValueNotifier<bool>(false);

  /// Profil fotoğrafı standardı (kadraj kılavuzu + yüz kontrolü uyarısı)
  /// herkese açık mı (admin her zaman görür).
  static final photoStandardEnabled = ValueNotifier<bool>(false);

  /// Takım kadrosunda onaysız oyuncunun satırından kimlik okutma ("Kimlik"
  /// düğmesi, "Sırayla okut") yetkililere açık mı (admin her zaman görür).
  static final rosterIdScanEnabled = ValueNotifier<bool>(false);

  /// Gol kesitlerinin MP4 hâli (YouTube yerine dosya oynar) ve "Instagram
  /// hikâyesinde paylaş" herkese açık mı (admin her zaman görür).
  static final goalClipMp4Enabled = ValueNotifier<bool>(false);

  /// Takip Listem: turnuva / takım / futbolcu yıldızla takip herkese açık
  /// mı (admin her zaman görür).
  static final followListEnabled = ValueNotifier<bool>(false);

  /// Ana sayfada takım / futbolcu araması (bantta büyüteç) herkese açık mı
  /// (admin her zaman görür).
  static final searchEnabled = ValueNotifier<bool>(false);

  /// Maç detayı tek istekte (match_detail_bundle) herkese açık mı (admin
  /// her zaman kullanır). Sorun çıkarsa kapatılır, eski okuma yoluna döner.
  static final matchBundleEnabled = ValueNotifier<bool>(false);

  /// "Bu hafta sen" kartındaki maç afişi kısayolu herkese açık mı (admin
  /// her zaman görür).
  static final myWeekPosterEnabled = ValueNotifier<bool>(false);

  /// Kadro sekmesinde tam ekran yatay saha (hızlı olay girişi) olay
  /// girebilen herkese açık mı (admin her zaman görür).
  static final livePitchEnabled = ValueNotifier<bool>(false);

  /// Menüde Yönetim Paneli: kapalıyken yalnız admin görür.
  static final adminPanelEnabled = ValueNotifier<bool>(false);

  /// Kimlik ibrazıyla onay + kimliğini okutmadan kayıt (yeni özellik kapısı).
  static final ibrazEnabled = ValueNotifier<bool>(false);

  /// Profilde telefon koduyla şifre değiştirme (yeni özellik kapısı).
  static final passwordChangeEnabled = ValueNotifier<bool>(false);
  static final rosterAddShortcutUsers = ValueNotifier<Set<String>>({});

  /// Yeni haberler (ana sayfada kaydırılan fotoğraflı kartlar, ayrı
  /// Haberler ekranı, gazete küpürü detay) herkese açık mı; kapalıyken
  /// yalnız admin görür, diğerleri eski haber kartını görür.
  static final newsScreenEnabled = ValueNotifier<bool>(false);

  /// Haberlerde tribün tepkileri ve yorumlar herkese açık mı; kapalıyken
  /// yalnız admin görür. Veritabanı da aynı kuralı uygular.
  static final newsCommentsEnabled = ValueNotifier<bool>(false);

  /// Ana sayfada sezon bazlı sağlık beyanı kartı herkese açık mı; kapalıyken
  /// yalnız admin. Veritabanı da aynı kuralı uygular (season_health_on).
  static final seasonHealthEnabled = ValueNotifier<bool>(false);

  /// Onay deneme listesi (auth uid): taslak onay metinlerini (avukat onayı
  /// bekleyen sürüm) ve sağlık beyanı kartını görür. Veritabanında
  /// consent_preview_on() aynı listeyi kullanır.
  static final consentPreviewUsers = ValueNotifier<Set<String>>({});

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
        } else if (r['key'] == _kWeekAwards) {
          weekAwardsEnabled.value = r['value'] == true;
        } else if (r['key'] == _kPlayerPoster) {
          playerPosterEnabled.value = r['value'] == true;
        } else if (r['key'] == _kPlayerPosterUsers) {
          final v = r['value'];
          playerPosterUsers.value = {
            if (v is List)
              for (final x in v) x.toString(),
          };
        } else if (r['key'] == _kMyWeek) {
          myWeekEnabled.value = r['value'] == true;
        } else if (r['key'] == _kReferees) {
          refereesEnabled.value = r['value'] == true;
        } else if (r['key'] == _kRosterAdd) {
          rosterAddShortcutEnabled.value = r['value'] == true;
        } else if (r['key'] == _kNewsScreen) {
          newsScreenEnabled.value = r['value'] == true;
        } else if (r['key'] == _kNewsComments) {
          newsCommentsEnabled.value = r['value'] == true;
        } else if (r['key'] == _kSeasonHealth) {
          seasonHealthEnabled.value = r['value'] == true;
        } else if (r['key'] == _kConsentPreviewUsers) {
          final v = r['value'];
          consentPreviewUsers.value = {
            if (v is List)
              for (final x in v) x.toString(),
          };
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
        } else if (r['key'] == _kLineupInRoster) {
          lineupInRosterEnabled.value = r['value'] == true;
        } else if (r['key'] == _kPhotoStandard) {
          photoStandardEnabled.value = r['value'] == true;
        } else if (r['key'] == _kRosterIdScan) {
          rosterIdScanEnabled.value = r['value'] == true;
        } else if (r['key'] == _kGoalClipMp4) {
          goalClipMp4Enabled.value = r['value'] == true;
        } else if (r['key'] == _kFollowList) {
          followListEnabled.value = r['value'] == true;
        } else if (r['key'] == _kSearch) {
          searchEnabled.value = r['value'] == true;
        } else if (r['key'] == _kMatchBundle) {
          matchBundleEnabled.value = r['value'] == true;
        } else if (r['key'] == _kMyWeekPoster) {
          myWeekPosterEnabled.value = r['value'] == true;
        } else if (r['key'] == _kLivePitch) {
          livePitchEnabled.value = r['value'] == true;
        } else if (r['key'] == _kAdminPanel) {
          adminPanelEnabled.value = r['value'] == true;
        } else if (r['key'] == _kIbraz) {
          ibrazEnabled.value = r['value'] == true;
        } else if (r['key'] == _kPasswordChange) {
          passwordChangeEnabled.value = r['value'] == true;
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

  /// Kimlik ibrazı ayarları: ibraz_enabled (özellik kapısı),
  /// ibraz_approve_owner (kurucu başkan onaylar), ibraz_approve_region
  /// (bölge sorumlusu onaylar).
  static Future<Map<String, bool>> loadIbrazSettings() async {
    final rows = await _sb.from('app_settings').select('key, value').inFilter(
      'key',
      [
        _kIbraz,
        'ibraz_approve_owner',
        'ibraz_approve_region',
        _kPasswordChange,
      ],
    );
    return {for (final r in rows) r['key'].toString(): r['value'] == true};
  }

  static Future<void> setIbrazSetting(String key, bool on) async {
    await _sb.from('app_settings').upsert({
      'key': key,
      'value': on,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    if (key == _kIbraz) ibrazEnabled.value = on;
    if (key == _kPasswordChange) passwordChangeEnabled.value = on;
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
