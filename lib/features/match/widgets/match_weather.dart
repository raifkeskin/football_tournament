import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Maç saatindeki hava (match_weather; saatlik cron + match-weather edge
/// function doldurur). Maça 5 gün kalandan başlama saatine kadar tahmin,
/// başlama saatinde dondurulur ("maç oynanırken").
class MatchWeather {
  final double temp;
  final double? feelsLike;
  final int? humidity;
  final double? windKmh;
  final int pop;
  final double rainMm;

  /// OpenWeatherMap hava kodu (2xx fırtına, 3xx/5xx yağmur, 6xx kar,
  /// 7xx sis, 800 açık, 801-802 parçalı, 803-804 bulutlu).
  final int code;
  final String description;
  final bool isDay;
  final String area;

  const MatchWeather({
    required this.temp,
    this.feelsLike,
    this.humidity,
    this.windKmh,
    required this.pop,
    required this.rainMm,
    required this.code,
    required this.description,
    required this.isDay,
    required this.area,
  });

  factory MatchWeather.fromMap(Map<String, dynamic> m) {
    double? d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
    int? i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v');
    final desc = (m['description'] ?? '').toString().trim();
    final pitch = m['pitches'];
    return MatchWeather(
      temp: d(m['temp']) ?? 0,
      feelsLike: d(m['feels_like']),
      humidity: i(m['humidity']),
      windKmh: d(m['wind_kmh']),
      pop: i(m['pop']) ?? 0,
      rainMm: d(m['rain_mm']) ?? 0,
      code: i(m['code']) ?? 800,
      description: desc.isEmpty
          ? ''
          : (desc[0] == 'i' ? 'İ' : desc[0].toUpperCase()) + desc.substring(1),
      isDay: m['is_day'] != false,
      area: pitch is Map ? (pitch['geo_area'] ?? '').toString().trim() : '',
    );
  }

  bool get isRainy => code >= 200 && code < 700;

  String get tempLabel => '${temp.round()}°';
}

class MatchWeatherService {
  MatchWeatherService._();

  static final Map<String, ValueNotifier<MatchWeather?>> _notifiers = {};
  static final Map<String, DateTime> _fetchedAt = {};

  /// Maçın havası; ilk çağrıda (ve 10 dakikada bir) arka planda okunur.
  /// Değer yoksa null kalır ve ekranda hiçbir şey çizilmez.
  static ValueNotifier<MatchWeather?> of(String matchId) {
    final n = _notifiers.putIfAbsent(matchId, () => ValueNotifier(null));
    final last = _fetchedAt[matchId];
    if (last == null ||
        DateTime.now().difference(last) > const Duration(minutes: 10)) {
      _fetchedAt[matchId] = DateTime.now();
      _fetch(matchId, n);
    }
    return n;
  }

  static Future<void> _fetch(
    String matchId,
    ValueNotifier<MatchWeather?> n,
  ) async {
    try {
      final r = await Supabase.instance.client
          .from('match_weather')
          .select('*, pitches(geo_area)')
          .eq('match_id', matchId)
          .maybeSingle();
      n.value = r == null
          ? null
          : MatchWeather.fromMap(Map<String, dynamic>.from(r));
    } catch (_) {
      _fetchedAt.remove(matchId); // sonraki açılışta yeniden dene
    }
  }
}

/// Hava ikonu (güneş/ay, bulut, yağmur, kar, şimşek, sis).
class WeatherGlyph extends StatelessWidget {
  final int code;
  final bool isDay;
  final double size;
  const WeatherGlyph({
    super.key,
    required this.code,
    this.isDay = true,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _GlyphPainter(code, isDay)),
  );
}

class _GlyphPainter extends CustomPainter {
  final int code;
  final bool isDay;
  _GlyphPainter(this.code, this.isDay);

  static const _sun = Color(0xFFFBBF24);
  static const _moon = Color(0xFFE2E8F0);
  static const _cloudLight = Color(0xFFE2E8F0);
  static const _cloudDark = Color(0xFFCBD5E1);
  static const _rain = Color(0xFF60A5FA);

  void _cloud(Canvas c, Offset o, double s, Color color) {
    final p = Paint()..color = color;
    c.drawCircle(o + Offset(-3.6 * s, 1.2 * s), 3.4 * s, p);
    c.drawCircle(o + Offset(0.6 * s, -1.4 * s), 4.6 * s, p);
    c.drawCircle(o + Offset(4.6 * s, 1.4 * s), 3.2 * s, p);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          o.dx - 7 * s,
          o.dy + 0.6 * s,
          o.dx + 7.8 * s,
          o.dy + 4.6 * s,
        ),
        Radius.circular(2 * s),
      ),
      p,
    );
  }

  void _sunOrMoon(Canvas c, Offset o, double r, double s) {
    if (isDay) {
      final p = Paint()..color = _sun;
      c.drawCircle(o, r, p);
      final ray = Paint()
        ..color = _sun
        ..strokeWidth = 1.8 * s
        ..strokeCap = StrokeCap.round;
      for (var k = 0; k < 8; k++) {
        final a = k * math.pi / 4;
        final dir = Offset(math.cos(a), math.sin(a));
        c.drawLine(o + dir * (r + 2.2 * s), o + dir * (r + 4.2 * s), ray);
      }
    } else {
      final path = Path()
        ..addOval(Rect.fromCircle(center: o, radius: r + 1 * s));
      final cut = Path()
        ..addOval(
          Rect.fromCircle(center: o + Offset(2.6 * s, -2 * s), radius: r),
        );
      c.drawPath(
        Path.combine(PathOperation.difference, path, cut),
        Paint()..color = _moon,
      );
    }
  }

  @override
  void paint(Canvas c, Size size) {
    final s = size.width / 24;
    final stroke = Paint()
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round;
    if (code == 800) {
      _sunOrMoon(c, Offset(12 * s, 12 * s), 4.6 * s, s);
      return;
    }
    if (code == 801 || code == 802) {
      _sunOrMoon(c, Offset(8.6 * s, 8 * s), 3.4 * s, s * 0.8);
      _cloud(c, Offset(13 * s, 14 * s), s, _cloudLight);
      return;
    }
    if (code >= 700 && code < 800) {
      _cloud(c, Offset(12 * s, 8.5 * s), s, _cloudDark);
      stroke.color = _cloudDark;
      for (final y in [16.0, 19.5]) {
        c.drawLine(Offset(5 * s, y * s), Offset(19 * s, y * s), stroke);
      }
      return;
    }
    final wet = code < 700;
    _cloud(c, Offset(12 * s, wet ? 8.5 * s : 11 * s), s, _cloudDark);
    if (!wet) return;
    if (code >= 600) {
      final p = Paint()..color = Colors.white;
      for (final x in [8.0, 12.0, 16.0]) {
        c.drawCircle(Offset(x * s, 18.5 * s), 1.3 * s, p);
      }
    } else {
      stroke.color = _rain;
      for (final x in [8.5, 12.5, 16.5]) {
        c.drawLine(
          Offset(x * s, 16.5 * s),
          Offset((x - 1) * s, 19.5 * s),
          stroke,
        );
      }
    }
    if (code < 300) {
      final bolt = Path()
        ..moveTo(13 * s, 13 * s)
        ..lineTo(10 * s, 18 * s)
        ..lineTo(12.5 * s, 18 * s)
        ..lineTo(11 * s, 22.5 * s)
        ..lineTo(15.5 * s, 16.5 * s)
        ..lineTo(13 * s, 16.5 * s)
        ..close();
      c.drawPath(bolt, Paint()..color = _sun);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.code != code || old.isDay != isDay;
}

/// Başlık bandında, maç saatinin altında: ikon · 14° · %60 yağmur.
class MatchWeatherHeaderLine extends StatelessWidget {
  final String matchId;
  final List<Shadow> shadows;
  const MatchWeatherHeaderLine({
    super.key,
    required this.matchId,
    this.shadows = const [],
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MatchWeather?>(
      valueListenable: MatchWeatherService.of(matchId),
      builder: (context, w, _) {
        if (w == null) return const SizedBox.shrink();
        final base = TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
          shadows: shadows,
        );
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WeatherGlyph(code: w.code, isDay: w.isDay, size: 16),
                const SizedBox(width: 4),
                Text.rich(
                  TextSpan(
                    text: w.tempLabel,
                    children: [
                      if (w.pop >= 20)
                        TextSpan(
                          text: ' · %${w.pop} yağmur',
                          style: const TextStyle(color: Color(0xFF93C5FD)),
                        ),
                    ],
                  ),
                  style: base,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Detay sekmesinin üstünde açılır kapanır hava paneli. Kapalıyken tek
/// satır özet; açıkken sıcaklık, hissedilen, yağmur olasılığı ve rüzgâr /
/// yağış / nem. Açık/kapalı tercihi cihazda hatırlanır.
class MatchWeatherPanel extends StatefulWidget {
  final String matchId;

  /// "16:00" — başlıktaki saat; yoksa gösterilmez.
  final String? kickoffLabel;

  /// Maç başladıysa/bittiyse "Maç oynanırken" yazılır.
  final bool played;

  const MatchWeatherPanel({
    super.key,
    required this.matchId,
    this.kickoffLabel,
    this.played = false,
  });

  @override
  State<MatchWeatherPanel> createState() => _MatchWeatherPanelState();
}

class _MatchWeatherPanelState extends State<MatchWeatherPanel> {
  static const _prefKey = 'match_weather_panel_open';
  static bool? _openPref;

  bool get _open => _openPref ?? false;

  @override
  void initState() {
    super.initState();
    if (_openPref == null) {
      SharedPreferences.getInstance()
          .then((p) {
            final v = p.getBool(_prefKey) ?? false;
            if (_openPref == null && mounted) setState(() => _openPref = v);
          })
          .catchError((_) {});
    }
  }

  void _toggle() {
    setState(() => _openPref = !_open);
    SharedPreferences.getInstance()
        .then((p) => p.setBool(_prefKey, _open))
        .catchError((_) => false);
  }

  static const _dim = Color(0x9EFFFFFF);
  static const _rain = Color(0xFF60A5FA);

  String _num(double v) =>
      (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1))
          .replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MatchWeather?>(
      valueListenable: MatchWeatherService.of(widget.matchId),
      builder: (context, w, _) {
        if (w == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Material(
            color: const Color(0xFF1E293B).withValues(alpha: 0.7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _toggle,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _open ? _expanded(w) : _collapsed(w),
              ),
            ),
          ),
        );
      },
    );
  }

  String get _when => widget.played ? 'Maç oynanırken' : 'Maç saatinde';

  Widget _collapsed(MatchWeather w) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Row(
        children: [
          WeatherGlyph(code: w.code, isDay: w.isDay, size: 28),
          const SizedBox(width: 10),
          Text(
            w.tempLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  w.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text.rich(
                  TextSpan(
                    text: _when,
                    children: [
                      if (w.pop >= 20)
                        TextSpan(
                          text: ' · %${w.pop} yağmur',
                          style: const TextStyle(
                            color: _rain,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _dim,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.expand_more_rounded, color: _dim, size: 22),
        ],
      ),
    );
  }

  Widget _expanded(MatchWeather w) {
    const cap = TextStyle(
      color: _dim,
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    );
    final title = widget.kickoffLabel == null
        ? _when
        : '$_when · ${widget.kickoffLabel}';
    final feels = w.feelsLike == null
        ? null
        : 'Hissedilen ${w.feelsLike!.round()}°';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title.toUpperCase(), style: cap, maxLines: 1),
              ),
              if (w.area.isNotEmpty)
                Text(w.area.toUpperCase(), style: cap, maxLines: 1),
              const Icon(Icons.expand_less_rounded, color: _dim, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              WeatherGlyph(code: w.code, isDay: w.isDay, size: 46),
              const SizedBox(width: 12),
              Text(
                w.tempLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      w.description,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [?feels, 'Yağmur %${w.pop}'].join(' · '),
                      style: const TextStyle(
                        color: _dim,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat(
                'Rüzgâr',
                w.windKmh == null ? '–' : '${_num(w.windKmh!)} km/s',
              ),
              const SizedBox(width: 6),
              _stat('Yağış', '${_num(w.rainMm)} mm'),
              const SizedBox(width: 6),
              _stat('Nem', w.humidity == null ? '–' : '%${w.humidity}'),
            ],
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Kaynak: OpenWeather',
              style: TextStyle(color: _dim, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _dim,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ),
  );
}
