import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Topun tonu: normal (beyaz), kendi kalesine (kırmızı), iptal/kaçan (soluk).
enum BallTint { normal, red, grey }

/// Maç olaylarında kullanılan gerçekçi futbol topu: ortada siyah beşgen,
/// kenarlarda yarım beşgenler, dikişler, gölge ve parlama.
class BallIcon extends StatelessWidget {
  const BallIcon({super.key, this.size = 18, this.tint = BallTint.normal});

  final double size;
  final BallTint tint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BallPainter(tint)),
    );
  }
}

class _BallPainter extends CustomPainter {
  const _BallPainter(this.tint);

  final BallTint tint;

  ({Color white, Color shade, Color dark}) get _colors => switch (tint) {
    BallTint.normal => (
      white: Colors.white,
      shade: const Color(0xFF9CA3AF),
      dark: const Color(0xFF111827),
    ),
    BallTint.red => (
      white: const Color(0xFFFECACA),
      shade: const Color(0xFFEF4444),
      dark: const Color(0xFF991B1B),
    ),
    BallTint.grey => (
      white: const Color(0xFFCBD5E1),
      shade: const Color(0xFF64748B),
      dark: const Color(0xFF475569),
    ),
  };

  static Offset _polar(double r, double deg) {
    final a = deg * math.pi / 180;
    return Offset(12 + r * math.cos(a), 12 + r * math.sin(a));
  }

  static Path _pentagon(Offset c, double r, double rot) {
    final p = Path();
    for (var i = 0; i < 5; i++) {
      final a = (rot + i * 72) * math.pi / 180;
      final o = c + Offset(r * math.cos(a), r * math.sin(a));
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 24×24 tasarım alanı ikon boyutuna ölçeklenir.
    canvas.scale(size.width / 24, size.height / 24);
    final c = _colors;
    const center = Offset(12, 12);
    const r = 10.6;
    final circle = Rect.fromCircle(center: center, radius: r);

    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.24, -0.36),
          radius: 0.75,
          colors: [c.white, c.white, c.shade],
          stops: const [0, 0.55, 1],
        ).createShader(circle),
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(circle));
    final fill = Paint()..color = c.dark;
    final stroke = Paint()
      ..color = c.dark
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(_pentagon(center, 4.1, -90), fill);
    canvas.drawPath(_pentagon(center, 4.1, -90), stroke..strokeWidth = 0.7);
    for (var i = 0; i < 5; i++) {
      final a = -90.0 + i * 72;
      final b = a + 36;
      stroke.strokeWidth = 0.7;
      canvas.drawLine(_polar(4.1, a), _polar(7.2, a), stroke);
      final edge = _pentagon(_polar(10.9, a), 3.7, a + 180);
      canvas.drawPath(edge, fill);
      stroke.strokeWidth = 0.6;
      canvas.drawLine(_polar(6.4, b), _polar(11, b), stroke);
      canvas.drawLine(_polar(7.2, a), _polar(6.4, b), stroke);
      canvas.drawLine(_polar(7.2, a + 72), _polar(6.4, b), stroke);
    }
    canvas.restore();

    // Parlama ve dış hat.
    canvas.save();
    canvas.translate(8.6, 7.4);
    canvas.rotate(-30 * math.pi / 180);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 6.4, height: 3.8),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.restore();
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.black.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_BallPainter old) => old.tint != tint;
}

/// Dikey hakem kartı (sarı / kırmızı / soluk).
class RefereeCardIcon extends StatelessWidget {
  const RefereeCardIcon({super.key, required this.color, this.height = 16});

  const RefereeCardIcon.yellow({super.key, this.height = 16})
    : color = const Color(0xFFFACC15);
  const RefereeCardIcon.red({super.key, this.height = 16})
    : color = const Color(0xFFEF4444);
  const RefereeCardIcon.grey({super.key, this.height = 16})
    : color = const Color(0xFF94A3B8);

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Color.lerp(color, Colors.black, 0.18)!;
    return Container(
      width: height * 0.7,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height * 0.15),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, dark],
        ),
        border: Border.all(color: Colors.black.withValues(alpha: 0.18)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
    );
  }
}
