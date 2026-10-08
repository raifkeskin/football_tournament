import 'package:flutter/material.dart';

import '../../../core/services/service_locator.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../match/models/match.dart';
import '../../match/screens/match_details_screen.dart';
import '../../player/models/player_stats.dart';
import '../../player/services/player_profile_service.dart';
import '../../player/widgets/player_card.dart';

const _muted = Color(0xFF94A3B8);
const _card = Color(0xFF1E293B);
const _accent = Color(0xFF10B981);

/// Takım sayfasının sekme çubuğu (maç detayındaki sekmelerle aynı görünüm).
class TeamPageTabBar extends StatelessWidget {
  const TeamPageTabBar({
    super.key,
    required this.index,
    required this.onChanged,
    this.labels = const ['Kadro', 'Fikstür', 'İstatistik'],
  });

  final int index;
  final ValueChanged<int> onChanged;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: i == index ? _accent : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: i == index ? Colors.white : _muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Takımın sezondaki maçları: yaklaşanlar önce, sonra oynananlar (yeniden
/// eskiye). Satıra dokununca maç detayı açılır.
class TeamFixtureTab extends StatefulWidget {
  const TeamFixtureTab({
    super.key,
    required this.seasonId,
    required this.teamId,
    required this.teamName,
  });

  final String seasonId;
  final String teamId;
  final String teamName;

  @override
  State<TeamFixtureTab> createState() => _TeamFixtureTabState();
}

class _TeamFixtureTabState extends State<TeamFixtureTab> {
  // Sekme değişince yeniden okunmasın: sezon+takım başına bir kez.
  static final Map<String, Future<List<TeamMatch>>> _cache = {};

  late Future<List<TeamMatch>> _future;

  String get _key => '${widget.seasonId}|${widget.teamId}';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<TeamMatch>> _load() => _cache.putIfAbsent(
    _key,
    () => PlayerProfileService().loadTeamMatches(
      MyTeam(
        seasonId: widget.seasonId,
        teamId: widget.teamId,
        teamName: widget.teamName,
        leagueName: '',
        seasonName: '',
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TeamMatch>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(color: _accent)),
          );
        }
        if (snap.hasError) {
          _cache.remove(_key);
          return _empty('Maçlar yüklenemedi.');
        }
        final all = snap.data ?? const <TeamMatch>[];
        if (all.isEmpty) return _empty('Bu sezon için maç yok.');
        final upcoming = all.where((m) => !_isDone(m.match)).toList();
        final played = all.where((m) => _isDone(m.match)).toList().reversed;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (upcoming.isNotEmpty) ...[
              _label('YAKLAŞAN MAÇLAR'),
              for (final m in upcoming) _row(context, m),
            ],
            if (played.isNotEmpty) ...[
              _label('OYNANAN MAÇLAR'),
              for (final m in played) _row(context, m),
            ],
          ],
        );
      },
    );
  }

  static bool _isDone(MatchModel m) =>
      m.status == MatchStatus.finished || m.status == MatchStatus.cancelled;

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(
      text,
      style: const TextStyle(
        color: _accent,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    ),
  );

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.all(32),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: _muted),
    ),
  );

  Widget _row(BuildContext context, TeamMatch tm) {
    final m = tm.match;
    final isHome = m.homeTeamId == widget.teamId;
    final opponent = isHome ? tm.awayName : tm.homeName;
    final opponentLogo = isHome ? tm.awayLogo : tm.homeLogo;
    final d = tm.startsAt;
    String two(int v) => v.toString().padLeft(2, '0');
    final date = d == null ? '–' : '${two(d.day)}.${two(d.month)}';
    final time = d == null ? '' : '${two(d.hour)}:${two(d.minute)}';

    // Sağdaki sonuç kutusu: skor (G/B/M rengiyle), ERT, İPT ya da saat.
    final (String text, Color color) result = switch (m.status) {
      MatchStatus.cancelled => ('İPT', Colors.white54),
      MatchStatus.postponed => ('ERT', Colors.white54),
      MatchStatus.finished => () {
        final mine = isHome ? m.homeScore : m.awayScore;
        final their = isHome ? m.awayScore : m.homeScore;
        return (
          '${m.homeScore} - ${m.awayScore}',
          mine > their
              ? _accent
              : mine < their
              ? const Color(0xFFF87171)
              : const Color(0xFFFBBF24),
        );
      }(),
      MatchStatus.live || MatchStatus.halftime => (
        '${m.homeScore} - ${m.awayScore}',
        const Color(0xFFF87171),
      ),
      MatchStatus.notStarted => (time.isEmpty ? '–' : time, Colors.white),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => MatchDetailsScreen(match: m)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 46,
                  child: Column(
                    children: [
                      Text(
                        date,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        m.week == null ? '' : '${m.week}. hf',
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 30,
                  height: 30,
                  child: opponentLogo.trim().isEmpty
                      ? const Icon(Icons.shield_outlined, color: _muted)
                      : WebSafeImage(
                          url: opponentLogo,
                          width: 30,
                          height: 30,
                          fit: BoxFit.contain,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shortTeamName(opponent),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        [
                          isHome ? 'İç saha' : 'Deplasman',
                          if ((tm.pitchName ?? '').trim().isNotEmpty)
                            tm.pitchName!.trim(),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: result.$2.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    result.$1,
                    style: TextStyle(
                      color: result.$2,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Takım oyuncularının sezon istatistikleri (gol sırasına göre). Sayılar
/// istatistik ekranıyla aynı kaynaktan gelir.
class TeamStatsTab extends StatelessWidget {
  const TeamStatsTab({
    super.key,
    required this.seasonId,
    required this.teamId,
    required this.players,
  });

  final String seasonId;
  final String teamId;
  final List<PlayerModel> players;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final p in players) p.id: p};
    return StreamBuilder<List<PlayerStats>>(
      stream: ServiceLocator.matchService.watchPlayerStats(
        tournamentId: seasonId,
      ),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(color: _accent)),
          );
        }
        // Kadrodaki oyuncular; istatistiği olmayan da 0 ile listelenir.
        final stats = {
          for (final s in snap.data!)
            if (byId.containsKey(s.playerPhone)) s.playerPhone: s,
        };
        final rows = players.toList()
          ..sort((a, b) {
            final x = stats[a.id], y = stats[b.id];
            final g = (y?.goals ?? 0).compareTo(x?.goals ?? 0);
            if (g != 0) return g;
            final as = (y?.assists ?? 0).compareTo(x?.assists ?? 0);
            if (as != 0) return as;
            return (y?.matchesPlayed ?? 0).compareTo(x?.matchesPlayed ?? 0);
          });
        int sum(int Function(PlayerStats) f) =>
            stats.values.fold(0, (a, s) => a + f(s));

        const head = TextStyle(
          color: _muted,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        );
        Widget cell(String v, TextStyle style) => SizedBox(
          width: 30,
          child: Text(v, textAlign: TextAlign.center, style: style),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 14),
            Row(
              children: [
                _total('${sum((s) => s.goals)}', 'Gol', _accent),
                const SizedBox(width: 8),
                _total(
                  '${sum((s) => s.assists)}',
                  'Asist',
                  const Color(0xFFA78BFA),
                ),
                const SizedBox(width: 8),
                _total(
                  '${sum((s) => s.yellowCards)}',
                  'Sarı',
                  const Color(0xFFFBBF24),
                ),
                const SizedBox(width: 8),
                _total(
                  '${sum((s) => s.redCards)}',
                  'Kırmızı',
                  const Color(0xFFF87171),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Oyuncu', style: head)),
                      for (final h in ['M', 'G', 'A', 'S', 'K']) cell(h, head),
                    ],
                  ),
                  for (final p in rows)
                    InkWell(
                      onTap: () => showPlayerCard(context, playerKey: p.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: Colors.white.withValues(alpha: 0.06),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            for (final v in [
                              stats[p.id]?.matchesPlayed ?? 0,
                              stats[p.id]?.goals ?? 0,
                              stats[p.id]?.assists ?? 0,
                              stats[p.id]?.yellowCards ?? 0,
                              stats[p.id]?.redCards ?? 0,
                            ])
                              cell(
                                '$v',
                                TextStyle(
                                  color: v == 0 ? Colors.white38 : Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _total(String value, String label, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
        ],
      ),
    ),
  );
}
