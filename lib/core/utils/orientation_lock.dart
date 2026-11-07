import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Telefonda uygulama hep dik durur; tablette (kısa kenar ≥ 600) yön
/// serbesttir. Yatay açılan ekranlar (tam ekran saha, video tam ekranı)
/// kapanırken [restore] çağırır.
class OrientationLock {
  OrientationLock._();

  static bool _tablet = false;
  static bool get isTablet => _tablet;

  static Future<void> init() async {
    if (kIsWeb) return;
    final views = PlatformDispatcher.instance.views;
    if (views.isNotEmpty) {
      final v = views.first;
      final size = v.physicalSize / v.devicePixelRatio;
      _tablet = size.shortestSide >= 600;
    }
    await restore();
  }

  /// Telefonda dikey kilit, tablette serbest.
  static Future<void> restore() async {
    if (kIsWeb) return;
    await SystemChrome.setPreferredOrientations(
      _tablet
          ? const <DeviceOrientation>[]
          : const [DeviceOrientation.portraitUp],
    );
  }

  /// Yatay ekrandan çıkış: önce dikeye döndürülür (iOS yatayda kalmasın),
  /// sonra cihaza göre kilit / serbest.
  static Future<void> backToPortrait() async {
    if (kIsWeb) return;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    await restore();
  }
}
