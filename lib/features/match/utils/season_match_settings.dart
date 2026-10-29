import 'package:supabase_flutter/supabase_flutter.dart';

/// Maç ekranlarının ihtiyaç duyduğu sezon ayarları (devre süresi, gol
/// dakikası tutuluyor mu). Sezon başına bir kez okunur ve önbellekte kalır.
class SeasonMatchSettings {
  const SeasonMatchSettings({
    this.periodMinutes = 45,
    this.tracksGoalMinutes = true,
    this.aiEsame = true,
    this.aiClips = true,
    this.assistantReferees = true,
  });

  /// `seasons.match_period_duration` = TEK DEVRE süresi.
  final int periodMinutes;

  /// `seasons.track_goal_minutes`: false ise (halısaha) olaylar dakikasız
  /// girilir, maç detayında golcü listesi gösterilir, YZ kesitleri kapanır.
  final bool tracksGoalMinutes;

  /// Yapay Zekâ Yönetimi: sezonda esame okuma / gol videosu yakalama açık mı.
  final bool aiEsame;
  final bool aiClips;

  /// `seasons.assistant_referees_enabled`: maçta yan hakem seçilir mi.
  final bool assistantReferees;

  static final Map<String, Future<SeasonMatchSettings>> _futures = {};
  static final Map<String, SeasonMatchSettings> _cache = {};

  /// Önbellekteki değer (henüz okunmadıysa null).
  static SeasonMatchSettings? cached(String seasonId) =>
      _cache[seasonId.trim()];

  static Future<SeasonMatchSettings> of(String seasonId) {
    final sid = seasonId.trim();
    if (sid.isEmpty) return Future.value(const SeasonMatchSettings());
    return _futures.putIfAbsent(sid, () async {
      try {
        final res = await Supabase.instance.client
            .from('seasons')
            .select(
              'match_period_duration, track_goal_minutes, '
              'ai_esame_enabled, ai_clips_enabled, '
              'assistant_referees_enabled',
            )
            .eq('id', sid)
            .limit(1);
        if (res.isEmpty) return const SeasonMatchSettings();
        final v = res.first['match_period_duration'];
        final m = v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
        return _cache[sid] = SeasonMatchSettings(
          periodMinutes: m > 0 ? m : 45,
          tracksGoalMinutes: res.first['track_goal_minutes'] != false,
          aiEsame: res.first['ai_esame_enabled'] != false,
          aiClips: res.first['ai_clips_enabled'] != false,
          assistantReferees: res.first['assistant_referees_enabled'] != false,
        );
      } catch (_) {
        _futures.remove(sid); // hata kalıcı önbelleğe alınmasın
        return const SeasonMatchSettings();
      }
    });
  }

  /// Sezon formu kaydedilince eski değer kullanılmasın.
  static void invalidate(String seasonId) {
    _futures.remove(seasonId.trim());
    _cache.remove(seasonId.trim());
  }
}
