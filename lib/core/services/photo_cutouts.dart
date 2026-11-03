import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_session.dart';
import 'app_settings.dart';

/// Dekupe (arka planı silinmiş) oyuncu fotoğrafları: asıl fotoğraf adresi →
/// dekupe adresi. Fotoğraf değişir ya da izin yüzünden gizlenirse eşleşme
/// kalmaz, dizilişte daire görünür. Oturum başına bir kez okunur.
class PhotoCutouts {
  PhotoCutouts._();

  static final map = ValueNotifier<Map<String, String>>(const {});
  static Future<void>? _loading;

  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('player_photo_cutouts')
          .select('photo_url, cutout_url');
      map.value = {
        for (final r in rows)
          (r['photo_url'] ?? '').toString(): (r['cutout_url'] ?? '').toString(),
      };
    } catch (_) {
      _loading = null; // bir sonraki açılışta yeniden denensin
    }
  }

  /// Yeni özellik: admin her zaman, diğerleri ayar açıksa görür.
  static bool visible(BuildContext context) {
    try {
      if (AppSession.of(context).value.isAdmin) return true;
    } catch (_) {}
    return AppSettings.lineupCutoutsEnabled.value;
  }
}
