import 'package:flutter/material.dart';

/// Lig Masası logosu: tablası futbol sahası olan bir masa ("Saha Masası").
/// Resim dosyası yerine çizilir; her boyutta keskin kalır. Uygulama ikonları
/// da bu çizimden üretilir (test/tool/render_app_icons_test.dart).
///
/// * [tile]: lacivert yuvarlak köşeli zemin (bant, menü, afiş). Kapalıysa
///   yalnız masa çizilir (koyu zeminli açılış ekranı vb.).
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

  /// Masanın tuvale oranı (Android uyarlanabilir ikonun güvenli alanı için
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
    // Masa 100 birimlik tuvalin ortasına (biraz yukarı kaydırılmış çizim
    // dikeyde ortalanır).
    canvas.translate(50, 50);
    canvas.scale(markScale);
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

  @override
  bool shouldRepaint(AppLogoPainter old) =>
      old.tile != tile ||
      old.tileRadius != tileRadius ||
      old.markScale != markScale;
}
