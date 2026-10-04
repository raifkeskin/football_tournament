import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'league_access.dart';

/// Uygulama geneli ayarlar (`app_settings` tablosu; herkes okur, admin yazar).
class AppSettings {
  AppSettings._();

  static const _kPrivateLeagues = 'private_leagues_enabled';

  /// Gizli turnuva özelliği. Kapalıyken "Turnuva Kodu Gir" ve "Gizli turnuva"
  /// alanları gizlenir; veritabanı da tüm turnuvaları herkese açar.
  static final privateLeaguesEnabled = ValueNotifier<bool>(false);

  static SupabaseClient get _sb => Supabase.instance.client;

  static Future<void> load() async {
    try {
      final rows = await _sb.from('app_settings').select('key, value');
      for (final r in rows) {
        if (r['key'] == _kPrivateLeagues) {
          privateLeaguesEnabled.value = r['value'] == true;
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
}
