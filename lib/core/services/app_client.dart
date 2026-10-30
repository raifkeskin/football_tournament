import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_activity.dart';

/// Bu kurulumun platformunu, sürümünü ve varsa hesabını bildirir (admin
/// İstatistikler: sürüm dağılımı). Kimlik rastgeledir, cihazdan okunmaz.
/// Açılışta, girişte ve uygulamaya dönüşte en çok yarım saatte bir.
class AppClient {
  AppClient._();

  static const _kId = 'app_client_id';
  static String? _id;
  static String? _version;
  static DateTime? _last;

  static String get _platform =>
      kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

  static void start() {
    _ping(force: true);
    Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn) _ping(force: true);
    });
    AppActivity.foreground.addListener(() {
      if (AppActivity.foreground.value) _ping();
    });
  }

  static Future<void> _ping({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _last != null &&
        now.difference(_last!) < const Duration(minutes: 30)) {
      return;
    }
    _last = now;
    try {
      _id ??= await _clientId();
      if (_version == null) {
        final info = await PackageInfo.fromPlatform();
        _version = '${info.version}+${info.buildNumber}';
      }
      await Supabase.instance.client.rpc(
        'client_ping',
        params: {
          'p_client_id': _id,
          'p_platform': _platform,
          'p_version': _version,
        },
      );
    } catch (e) {
      debugPrint('client_ping: $e');
    }
  }

  static Future<String> _clientId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kId);
    if (saved != null && saved.length == 36) return saved;
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String hex(int from, int to) => b
        .sublist(from, to)
        .map((x) => x.toRadixString(16).padLeft(2, '0'))
        .join();
    final id =
        '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
    await prefs.setString(_kId, id);
    return id;
  }
}
