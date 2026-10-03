import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_bridge_stub.dart'
    if (dart.library.js_interop) 'push_bridge_web.dart'
    as bridge;

/// Web Push açık anahtarı (VAPID). Gizli eşi yalnızca Supabase'de
/// (send-push fonksiyonunun gizli değerlerinde) durur.
const kVapidPublicKey =
    'BKuh-HQ-IdEyQYxxdLDKpPLUAFZ_YhftLTzdxFSsZ_HDULCy3p1FV6u9mRb4Rb57dkL6-ZlkbGC4o-XJV9PNyeQ';

enum PushState {
  /// Tarayıcı/platform desteklemiyor.
  unsupported,

  /// iPhone'da Safari sekmesi: önce "Ana Ekrana Ekle" gerekir.
  iosInstall,

  /// Kullanıcı engellemiş; tarayıcı ayarlarından açılmalı.
  denied,

  /// İzin verilmiş.
  granted,

  /// Henüz sorulmamış.
  available,
}

/// Bildirim aboneliği (web). Abonelik Supabase'deki push_subscriptions
/// tablosuna, giriş yapmış kullanıcıya bağlı kaydedilir.
class PushService {
  static SupabaseClient get _sb => Supabase.instance.client;

  static PushState state() {
    switch (bridge.pushState()) {
      case 'ios-install':
        return PushState.iosInstall;
      case 'denied':
        return PushState.denied;
      case 'granted':
        return PushState.granted;
      case 'default':
        return PushState.available;
      default:
        return PushState.unsupported;
    }
  }

  static String get _platform => kIsWeb
      ? (bridge.pushIsIos() ? 'web-ios' : 'web')
      : defaultTargetPlatform.name;

  static Future<void> _save(String json) async {
    final m = jsonDecode(json) as Map<String, dynamic>;
    await _sb.rpc(
      'save_push_subscription',
      params: {
        'p_endpoint': m['endpoint'],
        'p_p256dh': m['p256dh'],
        'p_auth': m['auth'],
        'p_platform': _platform,
      },
    );
  }

  /// İzin ister ve abone olur. Bir butona basılınca çağrılmalı (tarayıcılar
  /// kullanıcı etkileşimi olmadan izin penceresi açmaz).
  static Future<void> enable() async {
    await _save(await bridge.pushSubscribe(kVapidPublicKey));
  }

  /// Bu cihazda bildirimleri kapatır.
  static Future<void> disable() async {
    final endpoint = await bridge.pushUnsubscribe();
    if (endpoint.isEmpty) return;
    await _sb.rpc('delete_push_subscription', params: {'p_endpoint': endpoint});
  }

  /// Bu cihazda abonelik var mı (izin verilmiş olsa da abonelik silinmiş
  /// olabilir).
  static Future<bool> isSubscribed() async =>
      (await bridge.pushCurrent()).isNotEmpty;

  /// İzin verilmiş cihazda aboneliği şu anki hesaba yeniden bağlar (başka
  /// hesapla girildiyse bildirimler doğru kişiye gitsin).
  static Future<void> resync() async {
    if (state() != PushState.granted) return;
    try {
      if (!await isSubscribed()) return;
      await _save(await bridge.pushSubscribe(kVapidPublicKey));
    } catch (e) {
      debugPrint('push resync: $e');
    }
  }

  /// Çıkışta bu cihazın kaydı silinir; çıkış yapmış cihaza bildirim gitmez.
  static Future<void> onSignOut() async {
    try {
      final endpoint = await bridge.pushCurrent();
      if (endpoint.isEmpty) return;
      await _sb.rpc(
        'delete_push_subscription',
        params: {'p_endpoint': endpoint},
      );
    } catch (e) {
      debugPrint('push signout: $e');
    }
  }
}
