import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uygulama (Android/iOS) sürümünde telefon bildirimi: Firebase Cloud
/// Messaging (iOS'ta FCM, APNs üzerinden iletir).
/// Cihazın FCM belirteci push_subscriptions'a `fcm:<belirteç>` adresiyle
/// kaydedilir; send-push fonksiyonu bu adresleri FCM'e gönderir. Web'de
/// kullanılmaz (orada Web Push).
class NativePush {
  NativePush._();

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  /// Kayıt yeri: push_subscriptions.platform.
  static String get platform => _isIos ? 'ios' : 'android';

  /// iOS'ta GoogleService-Info.plist Xcode kaynaklarında olmadığı için
  /// ayarlar burada verilir (com.ligmasasi.app kaydı).
  static const _iosOptions = FirebaseOptions(
    apiKey: 'AIzaSyB3IWOeQsTH-j43DfGyBBcIjgxNDk3ZRfY',
    appId: '1:974894815246:ios:5177c472a52777a11bc45f',
    messagingSenderId: '974894815246',
    projectId: 'football-tournament-c0c05',
    iosBundleId: 'com.ligmasasi.app',
  );

  static const _prefKey = 'native_push_on';
  static bool _ready = false;

  /// Son okunan izin durumu: 'granted' | 'denied' | 'default'.
  static String status = 'default';

  /// Bildirime basılınca açılacak adres (`/?n=<tür>-<id>`).
  static void Function(String url)? _onOpen;
  static String? _pendingUrl;

  /// Belirteç yenilenince yeniden kaydetmek için (PushService verir).
  static Future<void> Function(String token)? onTokenRefresh;

  static Future<void> init() async {
    if (!supported || _ready) return;
    try {
      await Firebase.initializeApp(options: _isIos ? _iosOptions : null);
      _ready = true;
      await refreshStatus();
      final m = FirebaseMessaging.instance;
      // Uygulama kapalıyken bildirime basılarak açıldıysa.
      final initial = await m.getInitialMessage();
      if (initial != null) _open(initial);
      // Arka plandayken bildirime basıldıysa.
      FirebaseMessaging.onMessageOpenedApp.listen(_open);
      m.onTokenRefresh.listen((t) async {
        if (await isOn()) await onTokenRefresh?.call(t);
      });
    } catch (e) {
      debugPrint('FCM başlatılamadı: $e');
    }
  }

  static void _open(RemoteMessage msg) {
    final url = (msg.data['url'] ?? '').toString();
    if (url.isEmpty) return;
    final handler = _onOpen;
    if (handler != null) {
      handler(url);
    } else {
      _pendingUrl = url;
    }
  }

  static void setOpenHandler(void Function(String url) handler) {
    _onOpen = handler;
    final url = _pendingUrl;
    if (url != null) {
      _pendingUrl = null;
      handler(url);
    }
  }

  static Future<void> refreshStatus() async {
    if (!_ready) return;
    final s = await FirebaseMessaging.instance.getNotificationSettings();
    status = switch (s.authorizationStatus) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional => 'granted',
      AuthorizationStatus.notDetermined => 'default',
      _ => 'denied',
    };
  }

  /// İzin ister ve belirteci döner (izin verilmezse hata).
  static Future<String> enable() async {
    if (!_ready) throw StateError('fcm-not-ready');
    await FirebaseMessaging.instance.requestPermission();
    await refreshStatus();
    if (status != 'granted') {
      throw StateError('permission-denied');
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) throw StateError('fcm-no-token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    return token;
  }

  /// Bildirimleri kapatır; kapatılan belirteci döner (yoksa boş).
  static Future<String> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, false);
    if (!_ready) return '';
    final token = await FirebaseMessaging.instance.getToken() ?? '';
    await FirebaseMessaging.instance.deleteToken();
    return token;
  }

  static Future<bool> isOn() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getBool(_prefKey) ?? false) && status == 'granted';
  }

  /// Açıksa şu anki belirteç (hesap değişince yeniden kayıt için).
  static Future<String> currentToken() async {
    if (!_ready || !await isOn()) return '';
    return await FirebaseMessaging.instance.getToken() ?? '';
  }
}
