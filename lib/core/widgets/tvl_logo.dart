import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Türk Veteranlar Ligi monogram rozeti (kırmızı halka, beyaz merkez, içinde
/// top olan kırmızı V, yanlarda T ve L). Resim dosyası yerine çizilir; her
/// boyutta keskin kalır. [ringText] büyük boyutlar içindir (açılış ekranı):
/// halkaya üstte lig adı, altta kuruluş yılı ve iki yanda yıldız yazılır.
class TvlLogo extends StatelessWidget {
  const TvlLogo({super.key, this.size = 32, this.ringText = false});

  final double size;
  final bool ringText;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _TvlLogoPainter(ringText: ringText)),
    );
  }
}

class _TvlLogoPainter extends CustomPainter {
  _TvlLogoPainter({required this.ringText});

  final bool ringText;

  static const _red = Color(0xFFC8102E);
  static const _darkRed = Color(0xFF8B0A1F);
  static const _navy = Color(0xFF0F172A);

  @override
  void paint(Canvas canvas, Size size) {
    // Tasarım 200x200 birimlik tuvalde; boyuta ölçeklenir.
    canvas.save();
    canvas.scale(size.width / 200, size.height / 200);
    const c = Offset(100, 100);

    canvas.drawCircle(c, 96, Paint()..color = _red);
    canvas.drawCircle(
      c,
      96,
      Paint()
        ..color = _darkRed
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    canvas.drawCircle(c, 60, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      60,
      Paint()
        ..color = _darkRed
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    final v = Path()
      ..moveTo(70, 64)
      ..lineTo(90, 64)
      ..lineTo(100, 102)
      ..lineTo(110, 64)
      ..lineTo(130, 64)
      ..lineTo(107, 138)
      ..lineTo(93, 138)
      ..close();
    canvas.drawPath(v, Paint()..color = _red);

    _ball(canvas, const Offset(100, 80), 15);

    _letter(canvas, 'T', const Offset(57, 104), 40);
    _letter(canvas, 'L', const Offset(143, 104), 40);

    if (ringText) {
      _arcText(canvas, 'TÜRK VETERANLAR LİGİ', 77, top: true, fontSize: 21);
      _arcText(canvas, 'KURULUŞ 2026', 79, top: false, fontSize: 17);
      _star(canvas, const Offset(17, 100), 8.5);
      _star(canvas, const Offset(183, 100), 8.5);
    }
    canvas.restore();
  }

  void _ball(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    final pent = Path();
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 5;
      final p = c + Offset(math.cos(a), math.sin(a)) * r * 0.42;
      i == 0 ? pent.moveTo(p.dx, p.dy) : pent.lineTo(p.dx, p.dy);
    }
    pent.close();
    canvas.drawPath(pent, Paint()..color = _navy);
    final seam = Paint()
      ..color = _navy
      ..strokeWidth = r * 0.12
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 5;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * r * 0.42, c + dir * r, seam);
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = _navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12,
    );
  }

  void _star(Canvas canvas, Offset c, double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final rr = i.isEven ? r : r * 0.42;
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = Colors.white);
  }

  void _letter(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize, {
    Color color = _navy,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'BarlowCondensed',
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  /// Yazıyı daire yayına ortalayarak dizer; üst yay soldan sağa, alt yay da
  /// soldan sağa ve düz okunur.
  void _arcText(
    Canvas canvas,
    String text,
    double radius, {
    required bool top,
    required double fontSize,
  }) {
    final style = TextStyle(
      fontFamily: 'BarlowCondensed',
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
      height: 1,
    );
    final painters = [
      for (final ch in text.characters)
        TextPainter(
          text: TextSpan(text: ch, style: style),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    const spacing = 1.2;
    final total =
        painters.fold<double>(0, (s, p) => s + p.width) +
        spacing * (painters.length - 1);
    final sweep = total / radius;
    // Üstte merkez açı -90°, altta +90°.
    var angle = top ? -math.pi / 2 - sweep / 2 : math.pi / 2 + sweep / 2;
    for (final p in painters) {
      final half = p.width / 2 / radius;
      angle += top ? half : -half;
      final pos =
          const Offset(100, 100) +
          Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(top ? angle + math.pi / 2 : angle - math.pi / 2);
      p.paint(canvas, Offset(-p.width / 2, -p.height / 2));
      canvas.restore();
      angle += top ? half + spacing / radius : -(half + spacing / radius);
    }
  }

  @override
  bool shouldRepaint(_TvlLogoPainter old) => old.ringText != ringText;
}
