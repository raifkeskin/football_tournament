import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/match.dart';

/// Canlı maç dakikası. Başlama düdüğü ve 2. yarı başlangıcı sunucu saatiyle
/// tutulur (bkz. advance_match_phase); dakika buradan hesaplanır:
/// 1. yarı 1'…30', süre dolunca 30+1'; 2. yarı 31'…60', sonra 60+1'.
/// Devre süresi seasons.match_period_duration'dan okunur.
class MatchClock {
  MatchClock._();

  static const _defaultPeriod = 30;
  static final Map<String, int> _periodBySeason = {};
  static Future<void>? _loading;

  /// Sezonların devre sürelerini bir kez okur.
  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('seasons')
          .select('id, match_period_duration');
      for (final r in rows) {
        final d = (r['match_period_duration'] as num?)?.toInt() ?? 0;
        if (d > 0) _periodBySeason[r['id'].toString()] = d;
      }
    } catch (e) {
      debugPrint('Devre süreleri okunamadı: $e');
      _loading = null; // sonraki çağrıda yeniden dene
    }
  }

  static int periodOf(String seasonId) =>
      _periodBySeason[seasonId] ?? _defaultPeriod;

  /// Maç oynanıyorsa dakika etiketi (ör. "17'", "30+2'"), değilse null.
  static String? liveMinute(MatchModel m, {DateTime? now}) {
    if (m.status != MatchStatus.live) return null;
    final kickoff = m.kickoffAt;
    // Akış öncesi kaydedilmiş canlı maçlar: elle girilen dakika varsa o.
    if (kickoff == null) return m.minute == null ? null : "${m.minute}'";

    final t = (now ?? DateTime.now()).toUtc();
    final period = periodOf(m.seasonId);
    final secondHalf = m.secondHalfAt;
    final start = secondHalf ?? kickoff;
    final played = t.difference(start).inMinutes.clamp(0, 999) + 1;
    final base = secondHalf == null ? 0 : period;
    final limit = base + period;
    final minute = base + played;
    return minute > limit ? "$limit+${minute - limit}'" : "$minute'";
  }
}

/// Maç canlıyken dakikayı periyodik olarak yeniden çizer.
class MatchClockBuilder extends StatefulWidget {
  const MatchClockBuilder({
    super.key,
    required this.match,
    required this.builder,
  });

  final MatchModel match;
  final Widget Function(BuildContext context, String? liveMinute) builder;

  @override
  State<MatchClockBuilder> createState() => _MatchClockBuilderState();
}

class _MatchClockBuilderState extends State<MatchClockBuilder> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    MatchClock.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant MatchClockBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  void _syncTimer() {
    final live = widget.match.status == MatchStatus.live;
    if (live && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (mounted) setState(() {});
      });
    } else if (!live) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, MatchClock.liveMinute(widget.match));
}
