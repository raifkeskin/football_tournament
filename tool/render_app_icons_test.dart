// Uygulama ikonlarını AppLogo çiziminden üretir (design/ ve web/icons/).
// Çalıştırma: flutter test tool/render_app_icons_test.dart
// Ardından: dart run flutter_launcher_icons && dart run flutter_native_splash:create
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:football_tournament/core/widgets/app_logo.dart';

Future<void> _render(String path, int px, AppLogoPainter painter) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, Size.square(px.toDouble()));
  final image = await recorder.endRecording().toImage(px, px);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('ikonları üret', (tester) async {
    await tester.runAsync(() async {
      // iOS: tam kare lacivert (köşeleri iOS yuvarlar), saydamlık yok.
      const full = AppLogoPainter(tileRadius: 0);
      await _render('design/app_icon_ios.png', 1024, full);
      // Android uyarlanabilir ikon ön yüzü: saydam, güvenli alana sığan masa.
      await _render(
        'design/app_icon_android_fg.png',
        1024,
        const AppLogoPainter(tile: false, markScale: 0.62),
      );
      // Açılış ekranı (lacivert zemin üstünde yalnız masa).
      await _render(
        'design/splash_logo.png',
        768,
        const AppLogoPainter(tile: false),
      );
      // Android 12 açılış ikonu: dairesel maskeye sığsın.
      await _render(
        'design/splash_android12.png',
        960,
        const AppLogoPainter(tile: false, markScale: 0.6),
      );
      // Web
      const rounded = AppLogoPainter();
      await _render('web/icons/Icon-192.png', 192, rounded);
      await _render('web/icons/Icon-512.png', 512, rounded);
      const maskable = AppLogoPainter(tileRadius: 0, markScale: 0.8);
      await _render('web/icons/Icon-maskable-192.png', 192, maskable);
      await _render('web/icons/Icon-maskable-512.png', 512, maskable);
      await _render('web/icons/Icon-180-apple.png', 180, full);
      await _render('web/favicon.png', 64, rounded);
    });
  });
}
