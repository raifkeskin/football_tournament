import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lig Masası logosu: tablası futbol sahası olan bir masa ("Saha Masası"),
/// sol üstünde kırmızı-beyaz kaptan pazubandı, sağ üstünde siyah-beyaz top.
/// Resim dosyası yerine çizilir; her boyutta keskin kalır. Uygulama ikonları
/// da bu çizimden üretilir (tool/render_app_icons_test.dart).
///
/// * [tile]: lacivert yuvarlak köşeli zemin (bant, menü, afiş). Kapalıysa
///   yalnız çizim (koyu zeminli açılış ekranı vb.).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32, this.tile = true});

  final double size;
  final bool tile;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: AppLogoPainter(tile: tile)),
    );
  }
}

class AppLogoPainter extends CustomPainter {
  const AppLogoPainter({
    this.tile = true,
    this.tileRadius = 22,
    this.markScale = 1,
  });

  /// Zemin çizilsin mi.
  final bool tile;

  /// Zemin köşe yarıçapı (100 birimlik tuvalde). iOS ikonu için 0: köşeleri
  /// işletim sistemi yuvarlar.
  final double tileRadius;

  /// Çizimin tuvale oranı (Android uyarlanabilir ikonun güvenli alanı için
  /// küçültülür).
  final double markScale;

  static const navy = Color(0xFF0F172A);
  static const green = Color(0xFF10B981);
  static const greenDark = Color(0xFF064E3B);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 100;
    canvas.save();
    canvas.scale(s);
    if (tile) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 100, 100),
          Radius.circular(tileRadius),
        ),
        Paint()..color = navy,
      );
    }
    canvas.translate(50, 50);
    canvas.scale(markScale);
    canvas.translate(-50, -50);

    _table(canvas);
    _armband(canvas, const Offset(25, 25), 25, 14, -0.18);
    _Ball.paint(canvas, const Offset(72, 27), 12.5);
    canvas.restore();
  }

  /// Masa: tablası saha, iki bacak (100 birimlik tuvalde, biraz aşağıda).
  static void _table(Canvas canvas) {
    canvas.save();
    canvas.translate(48, 58);
    canvas.scale(1.05);
    canvas.translate(-50, -53);
    final leg = Paint()..color = greenDark;
    for (final x in [22.0, 71.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 66, 7, 16),
          const Radius.circular(2),
        ),
        leg,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(12, 24, 76, 46),
        const Radius.circular(7),
      ),
      Paint()..color = green,
    );
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(17, 29, 66, 36),
        const Radius.circular(3),
      ),
      line,
    );
    canvas.drawLine(const Offset(50, 29), const Offset(50, 65), line);
    canvas.drawCircle(const Offset(50, 47), 7, line);
    canvas.drawRect(const Rect.fromLTWH(17, 39, 8, 16), line);
    canvas.drawRect(const Rect.fromLTWH(75, 39, 8, 16), line);
    canvas.restore();
  }

  /// Kaptan pazubandı: kırmızı tüp, kenarlarında beyaz şerit, ortada beyaz C.
  static void _armband(Canvas c, Offset o, double w, double h, double angle) {
    c.save();
    c.translate(o.dx, o.dy);
    c.rotate(angle);
    final body = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final rr = RRect.fromRectAndRadius(body, Radius.circular(h * 0.22));
    c.drawRRect(
      rr.shift(Offset(w * 0.03, h * 0.12)),
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.08),
    );
    c.drawRRect(
      rr,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF87171), Color(0xFFDC2626), Color(0xFF991B1B)],
          stops: [0, 0.45, 1],
        ).createShader(body),
    );
    final stripe = Paint()..color = Colors.white;
    c.save();
    c.clipRRect(rr);
    c.drawRect(
      Rect.fromLTWH(body.left, body.top + h * 0.07, w, h * 0.06),
      stripe,
    );
    c.drawRect(
      Rect.fromLTWH(body.left, body.bottom - h * 0.13, w, h * 0.06),
      stripe,
    );
    // Yanlarda kıvrım gölgesi (tüp görünümü).
    c.drawRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0x55000000),
            Color(0x00000000),
            Color(0x00000000),
            Color(0x55000000),
          ],
          stops: [0, 0.18, 0.82, 1],
        ).createShader(body),
    );
    c.restore();
    final tp = TextPainter(
      text: TextSpan(
        text: 'C',
        style: TextStyle(
          fontFamily: 'BarlowCondensed',
          fontWeight: FontWeight.w800,
          fontStyle: FontStyle.italic,
          fontSize: h * 0.86,
          color: Colors.white,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
  }

  @override
  bool shouldRepaint(AppLogoPainter old) =>
      old.tile != tile ||
      old.tileRadius != tileRadius ||
      old.markScale != markScale;
}

typedef _V3 = (double, double, double);

/// Siyah-beyaz futbol topu: kesik ikosahedron (12 beşgen, 20 altıgen) küreye
/// yansıtılır; ön yüzde siyah beşgen, çevresinde beyaz altıgenler.
class _Ball {
  static const _phi = 1.618033988749895;

  static List<_V3> _cyc(_V3 v) => [v, (v.$2, v.$3, v.$1), (v.$3, v.$1, v.$2)];

  static Set<_V3> _signs(_V3 v) => {
    for (final a in [1, -1])
      for (final b in [1, -1])
        for (final c in [1, -1]) (v.$1 * a, v.$2 * b, v.$3 * c),
  };

  static _V3 _norm(_V3 v) {
    final l = math.sqrt(v.$1 * v.$1 + v.$2 * v.$2 + v.$3 * v.$3);
    return (v.$1 / l, v.$2 / l, v.$3 / l);
  }

  static double _dot(_V3 a, _V3 b) => a.$1 * b.$1 + a.$2 * b.$2 + a.$3 * b.$3;

  static _V3 _slerp(_V3 a, _V3 b, double t) => _norm((
    a.$1 + (b.$1 - a.$1) * t,
    a.$2 + (b.$2 - a.$2) * t,
    a.$3 + (b.$3 - a.$3) * t,
  ));

  static final List<_V3> _verts = {
    for (final base in [
      (0.0, 1.0, 3 * _phi),
      (1.0, 2 + _phi, 2 * _phi),
      (_phi, 2.0, 2 * _phi + 1),
    ])
      for (final s in _signs(base)) ..._cyc(s),
  }.map(_norm).toList();

  static final List<_V3> _pentDirs = {
    for (final s in _signs((0.0, 1.0, _phi))) ..._cyc(s),
  }.map(_norm).toList();

  static final List<_V3> _hexDirs = {
    ..._signs((1.0, 1.0, 1.0)),
    for (final s in _signs((0.0, _phi, 1 / _phi))) ..._cyc(s),
  }.map(_norm).toList();

  /// Yüz: yöne en yakın k köşe, yön etrafında açıya göre sıralı.
  static List<_V3> _face(_V3 n, int k) {
    final f = ([
      ..._verts,
    ]..sort((a, b) => _dot(b, n).compareTo(_dot(a, n)))).take(k).toList();
    final t = _norm(n.$1.abs() < 0.9 ? (0.0, -n.$3, n.$2) : (-n.$3, 0.0, n.$1));
    final u = (
      n.$2 * t.$3 - n.$3 * t.$2,
      n.$3 * t.$1 - n.$1 * t.$3,
      n.$1 * t.$2 - n.$2 * t.$1,
    );
    double ang(_V3 v) => math.atan2(_dot(v, u), _dot(v, t));
    return f..sort((a, b) => ang(a).compareTo(ang(b)));
  }

  /// Önden görünüm: bir beşgen öne (+z) bakar, tepesi yukarıda. Yüzler bir
  /// kez hesaplanır.
  static final List<(List<_V3>, bool)> _faces = () {
    final n = _norm((0.0, 1.0, _phi));
    final ax = math.atan2(n.$2, n.$3);
    _V3 rx(_V3 v) {
      final c = math.cos(ax), s = math.sin(ax);
      return (v.$1, v.$2 * c - v.$3 * s, v.$2 * s + v.$3 * c);
    }

    final front = _face(n, 5).map(rx).toList();
    final top = front.reduce((a, b) => a.$2 > b.$2 ? a : b);
    final az = math.pi / 2 - math.atan2(top.$2, top.$1);
    _V3 view(_V3 v) {
      final w = rx(v);
      final c = math.cos(az), s = math.sin(az);
      return (w.$1 * c - w.$2 * s, w.$1 * s + w.$2 * c, w.$3);
    }

    return [
      for (final d in _hexDirs)
        if (view(d).$3 > -0.35) (_face(d, 6).map(view).toList(), false),
      for (final d in _pentDirs)
        if (view(d).$3 > -0.35) (_face(d, 5).map(view).toList(), true),
    ];
  }();

  static void paint(Canvas c, Offset o, double r) {
    Offset proj(_V3 v) {
      var x = v.$1, y = v.$2;
      if (v.$3 < 0) {
        // Arkaya dönen köşe kenara yapışır.
        final l = math.sqrt(x * x + y * y);
        x /= l;
        y /= l;
      }
      return o + Offset(x * r, -y * r);
    }

    c.drawOval(
      Rect.fromCenter(
        center: o + Offset(0, r * 0.98),
        width: r * 1.5,
        height: r * 0.28,
      ),
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.08),
    );
    final disc = Rect.fromCircle(center: o, radius: r);
    c.save();
    c.clipPath(Path()..addOval(disc));
    c.drawRect(disc, Paint()..color = Colors.white);
    final seam = Paint()
      ..color = const Color(0xFFB8BEC8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.016
      ..strokeCap = StrokeCap.round;
    final black = Paint()..color = const Color(0xFF15171C);
    for (final (f, _) in _faces) {
      for (var i = 0; i < f.length; i++) {
        final a = f[i], b = f[(i + 1) % f.length];
        for (var k = 0; k < 12; k++) {
          final p1 = _slerp(a, b, k / 12), p2 = _slerp(a, b, (k + 1) / 12);
          if (p1.$3 < 0 || p2.$3 < 0) continue;
          c.drawLine(proj(p1), proj(p2), seam);
        }
      }
    }
    for (final (f, pent) in _faces) {
      if (!pent) continue;
      final p = Path();
      for (var i = 0; i < f.length; i++) {
        final a = f[i], b = f[(i + 1) % f.length];
        for (var k = 0; k < 10; k++) {
          final pt = proj(_slerp(a, b, k / 10));
          i == 0 && k == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
        }
      }
      c.drawPath(p..close(), black);
    }
    // Işık: sol üst parlak, kenarlar gölgeli.
    c.drawRect(
      disc,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.45),
          radius: 1.05,
          colors: [Color(0x00000000), Color(0x08000000), Color(0x55000000)],
          stops: [0, 0.5, 1],
        ).createShader(disc),
    );
    c.drawRect(
      disc,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.5),
          radius: 0.5,
          colors: [Color(0x55FFFFFF), Color(0x00FFFFFF)],
        ).createShader(disc),
    );
    c.restore();
  }
}
