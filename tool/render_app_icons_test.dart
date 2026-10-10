// Uygulama ikonlarını ve uygulama içi logoyu ana logo görselinden üretir
// (design/app_logo_master.jpg, 5120 px).
// Çalıştırma: flutter test tool/render_app_icons_test.dart
// Ardından: dart run flutter_launcher_icons && dart run flutter_native_splash:create
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Ana görselde yuvarlak köşeli iç panelin, köşeleri ve dış çerçeveyi
/// dışarıda bırakan kare kesiti (panel: x 165–4905, y 215–4955).
const _crop = Rect.fromLTWH(255, 305, 4560, 4560);

/// Uygulama içi logo ve yuvarlak ikonlarda köşe yarıçapı (kenarın oranı).
const _radius = 0.22;

const _navy = Color(0xFF0F172A);
const _green = Color(0xFF10B981);

late ui.Image _master;

Future<void> _save(String path, ui.Image image) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

Future<ui.Image> _draw(int px, void Function(Canvas c, double s) paint) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paint(canvas, px.toDouble());
  return recorder.endRecording().toImage(px, px);
}

final _paint = Paint()..filterQuality = FilterQuality.medium;

/// Kesiti [dst] alanına çizer; [rounded] ise köşeler yuvarlanır (dışı saydam).
void _logo(Canvas c, Rect dst, {bool rounded = false}) {
  c.save();
  if (rounded) {
    c.clipRRect(
      RRect.fromRectAndRadius(dst, Radius.circular(dst.width * _radius)),
    );
  }
  c.drawImageRect(_master, _crop, dst, _paint);
  c.restore();
}

/// Kesiti ortada [frac] oranında çizer, kenarları kesitin kenar pikselleri
/// uzatılarak doldurulur (uyarlanabilir/maskable ikon: maske logoyu kesmesin,
/// zemin kesintisiz görünsün).
void _padded(Canvas c, double s, double frac) {
  final m = s * frac;
  final o = (s - m) / 2;
  final r = _crop;
  final dst = Rect.fromLTWH(o, o, m, m);
  // Kenar şeritleri (1 px kaynak, kenara kadar uzatılır).
  void strip(Rect src, Rect to) => c.drawImageRect(_master, src, to, _paint);
  strip(
    Rect.fromLTWH(r.left, r.top, r.width, 1),
    Rect.fromLTWH(o, 0, m, o + 1),
  );
  strip(
    Rect.fromLTWH(r.left, r.bottom - 1, r.width, 1),
    Rect.fromLTWH(o, o + m - 1, m, o + 1),
  );
  strip(
    Rect.fromLTWH(r.left, r.top, 1, r.height),
    Rect.fromLTWH(0, o, o + 1, m),
  );
  strip(
    Rect.fromLTWH(r.right - 1, r.top, 1, r.height),
    Rect.fromLTWH(o + m - 1, o, o + 1, m),
  );
  // Köşeler: köşe pikseli.
  for (final (sx, sy, dx, dy) in [
    (r.left, r.top, 0.0, 0.0),
    (r.right - 1, r.top, o + m - 1, 0.0),
    (r.left, r.bottom - 1, 0.0, o + m - 1),
    (r.right - 1, r.bottom - 1, o + m - 1, o + m - 1),
  ]) {
    strip(Rect.fromLTWH(sx, sy, 1, 1), Rect.fromLTWH(dx, dy, o + 1, o + 1));
  }
  c.drawImageRect(_master, r, dst, _paint);
}

Future<void> _full(String path, int px) async => _save(
  path,
  await _draw(px, (c, s) => _logo(c, Rect.fromLTWH(0, 0, s, s))),
);

Future<void> _rounded(String path, int px, {double frac = 1}) async =>
    _save(
      path,
      await _draw(px, (c, s) {
        final m = s * frac;
        _logo(
          c,
          Rect.fromLTWH((s - m) / 2, (s - m) / 2, m, m),
          rounded: true,
        );
      }),
    );

Future<void> _maskable(String path, int px, double frac) async =>
    _save(path, await _draw(px, (c, s) => _padded(c, s, frac)));

void main() {
  setUpAll(() async {
    final codec = await ui.instantiateImageCodec(
      File('design/app_logo_master.jpg').readAsBytesSync(),
    );
    _master = (await codec.getNextFrame()).image;
  });

  testWidgets('ikonları üret', (tester) async {
    await tester.runAsync(() async {
      // Uygulama içi logo (köşeleri widget yuvarlar): küçük JPG.
      final logo = await _draw(
        512,
        (c, s) => _logo(c, Rect.fromLTWH(0, 0, s, s)),
      );
      final raw = await logo.toByteData(format: ui.ImageByteFormat.rawRgba);
      final jpg = img.encodeJpg(
        img.Image.fromBytes(
          width: 512,
          height: 512,
          bytes: raw!.buffer,
          numChannels: 4,
        ),
        quality: 88,
      );
      File('assets/images/app_logo.jpg').writeAsBytesSync(jpg);

      // iOS: tam kare (köşeleri iOS yuvarlar), saydamlık yok.
      await _full('design/app_icon_ios.png', 1024);
      // Android uyarlanabilir ikon: zemin logonun kendisi (maske güvenli
      // alana sığacak kadar küçültülmüş), ön yüz saydam.
      await _maskable('design/app_icon_android_bg.png', 1024, 0.74);
      await _save('design/app_icon_android_fg.png', await _draw(1024, (_, _) {}));
      // Açılış ekranı (lacivert zemin üstünde yuvarlak köşeli logo).
      await _rounded('design/splash_logo.png', 768);
      // Android 12 açılış ikonu: dairesel maskeye sığsın.
      await _rounded('design/splash_android12.png', 960, frac: 0.52);
      // Web
      await _rounded('web/icons/Icon-192.png', 192);
      await _rounded('web/icons/Icon-512.png', 512);
      await _maskable('web/icons/Icon-maskable-192.png', 192, 0.8);
      await _maskable('web/icons/Icon-maskable-512.png', 512, 0.8);
      await _full('web/icons/Icon-180-apple.png', 180);
      await _rounded('web/favicon.png', 64);
      // Play Store ikonu: tam kare (köşeleri Play yuvarlar).
      await _full('design/store/play_icon_512.png', 512);
    });
  });

  testWidgets('Play tanıtım görseli', (tester) async {
    await tester.runAsync(() async {
      await (FontLoader('BarlowCondensed')..addFont(
            rootBundle.load('assets/fonts/BarlowCondensed-ExtraBoldItalic.ttf'),
          ))
          .load();
      final barlow = FontLoader('Barlow')
        ..addFont(rootBundle.load('assets/fonts/Barlow-SemiBold.ttf'));
      await barlow.load();

      const w = 1024.0, h = 500.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, w, h),
        Paint()..color = _navy,
      );
      _logo(canvas, const Rect.fromLTWH(90, 110, 280, 280), rounded: true);
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
          color: _green,
        ),
      );
      final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
      await _save('design/store/play_feature_1024x500.png', image);
    });
  });
}
