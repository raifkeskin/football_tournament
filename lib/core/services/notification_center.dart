import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_activity.dart';

/// Uygulama içi bildirimlerin okunmamış sayısı (zildeki rozet).
///
/// Canlı bağlantı açılmaz (eşzamanlı bağlantı sınırı): sayı açılışta, giriş
/// / çıkışta, ön plana dönüşte ve ön plandayken dakikada bir yenilenir.
class NotificationCenter {
  NotificationCenter._();

  static final unread = ValueNotifier<int>(0);

  /// Zil yalnızca giriş yapmış (misafir olmayan) kişide görünür.
  static final enabled = ValueNotifier<bool>(false);

  static const _interval = Duration(seconds: 60);
  static Timer? _timer;
  static var _started = false;

  static SupabaseClient get _sb => Supabase.instance.client;

  static bool get _isRealUser {
    final u = _sb.auth.currentUser;
    return u != null && !u.isAnonymous;
  }

  static void start() {
    if (_started) return;
    _started = true;
    _sb.auth.onAuthStateChange.listen((_) => refresh());
    AppActivity.foreground.addListener(() {
      if (AppActivity.foreground.value) refresh();
    });
    _timer = Timer.periodic(_interval, (_) {
      if (AppActivity.foreground.value) refresh();
    });
    refresh();
  }

  static Future<void> refresh() async {
    enabled.value = _isRealUser;
    if (!_isRealUser) {
      unread.value = 0;
      return;
    }
    try {
      final n = await _sb.rpc('my_unread_notification_count');
      unread.value = (n as num?)?.toInt() ?? 0;
    } catch (_) {}
  }

  /// Hepsini okundu yapar (liste açılınca).
  static Future<void> markAllRead() async {
    unread.value = 0;
    try {
      await _sb.rpc('mark_notifications_read');
    } catch (_) {}
  }

  @visibleForTesting
  static void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
