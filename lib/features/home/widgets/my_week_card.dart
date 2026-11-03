import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/widgets/youtube_player_page.dart';
import '../../match/widgets/youtube_find_sheet.dart';

/// Ana sayfada "Bu hafta sen": giriş yapan futbolcunun son maçında (son 7
/// gün, bu turnuvada) golü ya da asisti varsa skor ve gol videoları
/// (paylaşım video sayfasında). Gol ve asist yoksa hiç görünmez.
/// Yeni özellik: admin her zaman, diğerleri my_week_enabled açıksa.
class MyWeekCard extends StatefulWidget {
  const MyWeekCard({super.key, required this.leagueId});

  final String leagueId;

  /// Kart ana sayfada görünsün mü (selamlamadaki profil kısayolu da aynı
  /// anahtarla açılır).
  static bool enabledFor(AppSessionState s) =>
      s.isAdmin || AppSettings.myWeekEnabled.value;

  @override
  State<MyWeekCard> createState() => _MyWeekCardState();
}

class _Goal {
  const _Goal({
    required this.id,
    required this.label,
    required this.assist,
    this.videoId,
    this.start = 0,
    this.end = 0,
    this.clipUrl,
    this.storyUrl,
  });

  final String id;
  final String label;
  final bool assist;
  final String? videoId;
  final int start;
  final int end;
  final String? clipUrl;
  final String? storyUrl;
}

class _Week {
  const _Week({
    required this.week,
    required this.homeName,
    required this.awayName,
    required this.homeLogo,
    required this.awayLogo,
    required this.hs,
    required this.as,
    required this.events,
  });

  final int? week;
  final String homeName;
  final String awayName;
  final String homeLogo;
  final String awayLogo;
  final int hs;
  final int as;
  final List<_Goal> events;

  int get goals => events.where((e) => !e.assist).length;
  int get assists => events.where((e) => e.assist).length;
  List<_Goal> get clips => [
    for (final e in events)
      if ((e.videoId ?? '').isNotEmpty) e,
  ];
}

class _MyWeekCardState extends State<MyWeekCard> {
  /// Turnuva + futbolcu → son yüklenen (ekrana dönüşte anında görünsün).
  static final Map<String, _Week?> _cache = {};

  final _sb = Supabase.instance.client;
  String? _pid;
  _Week? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pid = AppSession.of(context).value.playerId;
    if (pid != _pid) {
      _pid = pid;
      _data = pid == null ? null : _cache['${widget.leagueId}|$pid'];
      if (pid != null) _load(pid);
    }
  }

  Future<void> _load(String pid) async {
    try {
      final evs = await _sb
          .from('match_events')
          .select(
            'id, match_id, player_id, assist_player_id, minute, '
            'added_minute, is_own_goal',
          )
          .eq('event_type', 'goal')
          .or('player_id.eq.$pid,assist_player_id.eq.$pid')
          .order('created_at', ascending: false)
          .limit(60);
      final mine = [
        for (final e in evs)
          if (!(e['is_own_goal'] == true && e['player_id'] == pid)) e,
      ];
      _Week? week;
      if (mine.isNotEmpty) {
        final since = DateTime.now().subtract(const Duration(days: 7));
        final day =
            '${since.year}-${since.month.toString().padLeft(2, '0')}-'
            '${since.day.toString().padLeft(2, '0')}';
        final matches = await _sb
            .from('matches')
            .select(
              'id, week, home_team_id, away_team_id, home_score, away_score',
            )
            .eq('league_id', widget.leagueId)
            .eq('status', 'finished')
            .isFilter('deleted_at', null)
            .gte('match_date', day)
            .inFilter('id', {for (final e in mine) e['match_id']}.toList())
            .order('match_date', ascending: false)
            .limit(1);
        if (matches.isNotEmpty) {
          final m = matches.first;
          final here = [
            for (final e in mine)
              if (e['match_id'] == m['id']) e,
          ];
          final (teams, clips) = await (
            _sb.from('teams').select('id, name, logo_url').inFilter('id', [
              m['home_team_id'],
              m['away_team_id'],
            ]),
            _sb
                .from('match_highlights')
                .select(
                  'match_event_id, video_id, start_sec, end_sec, clip_url, '
                  'story_url',
                )
                .eq('match_id', m['id'])
                .eq('status', 'approved')
                .inFilter('match_event_id', [for (final e in here) e['id']]),
          ).wait;
          final team = {for (final t in teams) t['id']: t};
          final clipOf = {for (final c in clips) c['match_event_id']: c};
          String label(Map e) {
            final n = (e['minute'] as num?)?.toInt() ?? 0;
            final a = (e['added_minute'] as num?)?.toInt() ?? 0;
            if (n <= 0) return '';
            return a > 0 ? "$n+$a'" : "$n'";
          }

          _Goal goal(Map e) {
            final own = e['player_id'] == pid;
            final c = clipOf[e['id']];
            return _Goal(
              id: e['id'].toString(),
              label: label(e),
              assist: !own,
              videoId: c?['video_id']?.toString(),
              start: (c?['start_sec'] as num?)?.toInt() ?? 0,
              end: (c?['end_sec'] as num?)?.toInt() ?? 0,
              clipUrl: c?['clip_url']?.toString(),
              storyUrl: c?['story_url']?.toString(),
            );
          }

          final events = [for (final e in here) goal(e)]
            ..sort((a, b) => _minute(a.label).compareTo(_minute(b.label)));
          week = _Week(
            week: (m['week'] as num?)?.toInt(),
            homeName: shortTeamName(
              (team[m['home_team_id']]?['name'] ?? '').toString(),
            ),
            awayName: shortTeamName(
              (team[m['away_team_id']]?['name'] ?? '').toString(),
            ),
            homeLogo: (team[m['home_team_id']]?['logo_url'] ?? '').toString(),
            awayLogo: (team[m['away_team_id']]?['logo_url'] ?? '').toString(),
            hs: (m['home_score'] as num?)?.toInt() ?? 0,
            as: (m['away_score'] as num?)?.toInt() ?? 0,
            events: events,
          );
        }
      }
      _cache['${widget.leagueId}|$pid'] = week;
      if (!mounted || _pid != pid) return;
      setState(() => _data = week);
    } catch (_) {
      // Kart isteğe bağlı: okunamazsa görünmez.
    }
  }

  static int _minute(String label) =>
      int.tryParse(label.split(RegExp(r"[+']")).first) ?? 0;

  void _play(_Goal g) {
    openYoutubeClip(
      context,
      videoId: g.videoId!,
      startSec: g.start,
      endSec: g.end,
      clipUrl: g.clipUrl,
      storyUrl: g.storyUrl,
      title: '${g.assist ? 'Asist' : 'Gol'} ${g.label}'.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null || d.events.isEmpty) return const SizedBox.shrink();
    const gold = Color(0xFFE2B845);
    final title = [
      if (d.goals > 0) '${d.goals} GOL',
      if (d.assists > 0) '${d.assists} ASİST',
    ].join(' · ');
    Widget crest(String url) => SizedBox(
      width: 26,
      height: 26,
      child: url.isEmpty
          ? const Icon(Icons.shield_outlined, color: Colors.white38, size: 22)
          : WebSafeImage(url: url, fit: BoxFit.contain),
    );
    final clips = d.clips;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.35),
          ),
          gradient: const RadialGradient(
            center: Alignment.topLeft,
            radius: 1.6,
            colors: [Color(0xFF14532D), Color(0xFF0F2A20), Color(0xFF1E293B)],
            stops: [0, 0.45, 1],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'BU HAFTA SEN',
                  style: TextStyle(
                    color: Color(0xFF34D399),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                if (d.week != null)
                  Text(
                    '${d.week}. Hafta',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'BarlowCondensed',
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w800,
                fontSize: 32,
                height: 1,
                color: gold,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                crest(d.homeLogo),
                const SizedBox(width: 8),
                Text(
                  '${d.hs}-${d.as}',
                  style: const TextStyle(
                    fontFamily: 'BarlowCondensed',
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                    height: 1,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                crest(d.awayLogo),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${d.homeName} – ${d.awayName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
            if (clips.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: clips.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final g = clips[i];
                    return GestureDetector(
                      onTap: () => _play(g),
                      child: SizedBox(
                        width: 152,
                        child: Stack(
                          children: [
                            BroadcastThumb(videoId: g.videoId!, radius: 10),
                            Positioned(
                              right: 6,
                              top: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: g.assist
                                      ? const Color(0xFF34D399)
                                      : gold,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  g.assist ? 'ASİST' : 'GOL',
                                  style: const TextStyle(
                                    color: Color(0xFF0A1020),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                            if (g.label.isNotEmpty)
                              Positioned(
                                left: 6,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    g.label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Videoya dokun: izle, Instagram'da ya da WhatsApp'ta paylaş.",
                style: TextStyle(color: Colors.white54, fontSize: 11.5),
              ),
            ] else ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in d.events)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (e.assist
                                    ? const Color(0xFF38BDF8)
                                    : const Color(0xFF10B981))
                                .withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        [
                          e.label,
                          e.assist ? 'Asist' : 'Gol',
                        ].where((t) => t.isNotEmpty).join(' '),
                        style: TextStyle(
                          color: e.assist
                              ? const Color(0xFF7DD3FC)
                              : const Color(0xFF34D399),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
