import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Diziliş sahasında oyuncunun gösterimi: yuvarlak veya forma.
/// Diziliş işareti: yuvarlak, forma ya da profil fotoğrafı.
enum PitchTokenStyle { circle, shirt, photo }

/// Cihazda saklanan diziliş gösterimi tercihi; diziliş sekmesi ve diziliş
/// afişi aynı tercihi kullanır.
class PitchTokenStylePref {
  PitchTokenStylePref._();

  // v2: varsayılan Profil oldu; eski kayıtlı seçim sıfırlanır.
  static const _key = 'pitch_token_style_v2';
  static final notifier = ValueNotifier<PitchTokenStyle>(PitchTokenStyle.photo);
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = PitchTokenStyle.values
          .where((e) => e.name == prefs.getString(_key))
          .firstOrNull;
      if (saved != null) notifier.value = saved;
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
  const PitchTokenStyleToggle({
    super.key,
    this.compact = false,
    this.showPhoto = false,
  });

  /// Yalnız ikonlar (dar satırlar için).
  final bool compact;

  /// "Profil" (oyuncu fotoğrafı) seçeneği gösterilsin mi.
  final bool showPhoto;

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
                horizontal: compact ? 13 : 12,
                vertical: compact ? 8 : 6,
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
              if (showPhoto)
                item(
                  PitchTokenStyle.photo,
                  'Profil',
                  const Icon(
                    Icons.account_circle_outlined,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Tek düğme: dokununca Profil / Forma / Yuvarlak seçimi açılır. Seçili
/// gösterim düğmenin üstünde yazar; tercih cihazda hatırlanır.
class PitchStyleMenuButton extends StatelessWidget {
  const PitchStyleMenuButton({super.key, this.showPhoto = true});

  final bool showPhoto;

  static const _accent = Color(0xFF10B981);

  static (String, String, Widget) _info(PitchTokenStyle v, {double s = 16}) =>
      switch (v) {
        PitchTokenStyle.circle => (
          'Yuvarlak',
          'Numaralı yuvarlak',
          Container(
            width: s - 2,
            height: s - 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
        PitchTokenStyle.shirt => (
          'Forma',
          'Numaralı forma',
          JerseyShape(
            width: s,
            color: Colors.transparent,
            borderColor: Colors.white,
          ),
        ),
        PitchTokenStyle.photo => (
          'Profil',
          'Dekupe fotoğraf, yoksa forma',
          Icon(Icons.account_circle_outlined, size: s, color: Colors.white),
        ),
      };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PitchTokenStyle>(
      valueListenable: PitchTokenStylePref.notifier,
      builder: (context, style, _) {
        final values = [
          PitchTokenStyle.photo,
          PitchTokenStyle.shirt,
          PitchTokenStyle.circle,
        ].where((v) => showPhoto || v != PitchTokenStyle.photo).toList();
        final cur = style == PitchTokenStyle.photo && !showPhoto
            ? PitchTokenStyle.shirt
            : style;
        final (label, _, icon) = _info(cur);
        return PopupMenuButton<PitchTokenStyle>(
          tooltip: 'Gösterim',
          initialValue: cur,
          color: const Color(0xFF0A1324),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Colors.white24),
          ),
          onSelected: PitchTokenStylePref.set,
          itemBuilder: (_) => [
            for (final v in values)
              PopupMenuItem(
                value: v,
                child: Row(
                  children: [
                    _info(v, s: 18).$3,
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _info(v).$1,
                            style: TextStyle(
                              color: v == cur ? _accent : Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            _info(v).$2,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (v == cur)
                      const Icon(Icons.check_rounded, color: _accent, size: 18),
                  ],
                ),
              ),
          ],
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Icon(
                  Icons.arrow_drop_down,
                  color: Colors.white70,
                  size: 18,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
