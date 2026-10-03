import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Diziliş sahasında oyuncunun gösterimi: yuvarlak veya forma.
enum PitchTokenStyle { circle, shirt }

/// Cihazda saklanan diziliş gösterimi tercihi; diziliş sekmesi ve diziliş
/// afişi aynı tercihi kullanır.
class PitchTokenStylePref {
  PitchTokenStylePref._();

  static const _key = 'pitch_token_style';
  static final notifier = ValueNotifier<PitchTokenStyle>(
    PitchTokenStyle.circle,
  );
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_key) == PitchTokenStyle.shirt.name) {
        notifier.value = PitchTokenStyle.shirt;
      }
    } catch (_) {}
  }

  static Future<void> set(PitchTokenStyle style) async {
    notifier.value = style;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, style.name);
    } catch (_) {}
  }
}

/// Forma şekli; ortasında [child] (forma numarası) durur.
class JerseyShape extends StatelessWidget {
  const JerseyShape({
    super.key,
    required this.color,
    required this.borderColor,
    this.width = 36,
    this.child,
  });

  final Color color;
  final Color borderColor;
  final double width;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 0.88,
      child: CustomPaint(
        painter: _JerseyPainter(color, borderColor),
        child: Padding(
          padding: EdgeInsets.only(top: width * 0.12),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _JerseyPainter extends CustomPainter {
  _JerseyPainter(this.color, this.border);

  final Color color;
  final Color border;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final path = Path()
      ..moveTo(w * 0.32, 0)
      ..lineTo(w * 0.12, h * 0.12)
      ..lineTo(0, h * 0.36)
      ..lineTo(w * 0.15, h * 0.46)
      ..lineTo(w * 0.21, h * 0.37)
      ..lineTo(w * 0.21, h)
      ..lineTo(w * 0.79, h)
      ..lineTo(w * 0.79, h * 0.37)
      ..lineTo(w * 0.85, h * 0.46)
      ..lineTo(w, h * 0.36)
      ..lineTo(w * 0.88, h * 0.12)
      ..lineTo(w * 0.68, 0)
      ..quadraticBezierTo(w * 0.5, h * 0.16, w * 0.32, 0)
      ..close();
    canvas.drawShadow(path, Colors.black, 2, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _JerseyPainter old) =>
      old.color != color || old.border != border;
}

/// Diziliş sekmesindeki "Yuvarlak / Forma" seçici.
class PitchTokenStyleToggle extends StatelessWidget {
  const PitchTokenStyleToggle({super.key, this.compact = false});

  /// Yalnız ikonlar (dar satırlar için).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PitchTokenStyle>(
      valueListenable: PitchTokenStylePref.notifier,
      builder: (context, style, _) {
        Widget item(PitchTokenStyle v, String label, Widget icon) {
          final sel = style == v;
          final body = InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => PitchTokenStylePref.set(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 9 : 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFF10B981) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  if (!compact) ...[
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        color: sel ? Colors.white : Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
          return compact ? Tooltip(message: label, child: body) : body;
        }

        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              item(
                PitchTokenStyle.circle,
                'Yuvarlak',
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
              item(
                PitchTokenStyle.shirt,
                'Forma',
                const JerseyShape(
                  width: 16,
                  color: Colors.transparent,
                  borderColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
