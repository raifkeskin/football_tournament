// Uygulama ikonlarını AppLogo çiziminden üretir (design/ ve web/icons/).
// Çalıştırma: flutter test tool/render_app_icons_test.dart
// Ardından: dart run flutter_launcher_icons && dart run flutter_native_splash:create
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      // Play Store ikonu: tam kare (köşeleri Play yuvarlar).
      await _render('design/store/play_icon_512.png', 512, full);
    });
  });

  testWidgets('Play tanıtım görseli', (tester) async {
    await tester.runAsync(() async {
      final loader = FontLoader('BarlowCondensed')
        ..addFont(
          rootBundle.load('assets/fonts/BarlowCondensed-ExtraBoldItalic.ttf'),
        );
      await loader.load();
      final barlow = FontLoader('Barlow')
        ..addFont(rootBundle.load('assets/fonts/Barlow-SemiBold.ttf'));
      await barlow.load();

      const w = 1024.0, h = 500.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, w, h),
        Paint()..color = AppLogoPainter.navy,
      );
      canvas.save();
      canvas.translate(90, 110);
      const AppLogoPainter(tile: false).paint(canvas, const Size.square(280));
      canvas.restore();
      void text(String s, double x, double y, TextStyle style) {
        final tp = TextPainter(
          text: TextSpan(text: s, style: style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: w - x - 40);
        tp.paint(canvas, Offset(x, y));
      }

      text(
        'LİG MASASI',
        430,
        165,
        const TextStyle(
          fontFamily: 'BarlowCondensed',
          fontSize: 96,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 2,
        ),
      );
      text(
        'Fikstür · Kadro · Canlı skor · Puan durumu',
        434,
        285,
        const TextStyle(
          fontFamily: 'Barlow',
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: AppLogoPainter.green,
        ),
      );
      final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('design/store/play_feature_1024x500.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
