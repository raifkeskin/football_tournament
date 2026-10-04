import 'package:flutter/material.dart';
import '../../../core/utils/table_feed.dart';
import 'package:football_tournament/core/widgets/master_class_app_bar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../tournament/models/league.dart';
import '../../tournament/models/season.dart';
import '../models/player_stats.dart';
import '../widgets/player_card.dart';
import '../../team/models/team.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../../match/services/interfaces/i_match_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/services/global_filter.dart';

// ORTAK BİLEŞEN
import '../../../core/widgets/tournament_filter_dialog.dart';
import '../../../core/utils/string_utils.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final IMatchService _matchService = ServiceLocator.matchService;
  final ITeamService _teamService = ServiceLocator.teamService;

  String? _selectedLeagueId;
  String? _selectedSeasonId;

  Stream<List<League>>? _leaguesStream;

  String? _lastLeagueIdForSeason;
  Stream<List<Season>>? _seasonsStream;

  Stream<List<Season>> _watchSeasons(String leagueId) {
    // Önce normal sorgu, canlı bağlantı arkadan (bkz. watchTableRows).
    return watchTableRows(
      Supabase.instance.client,
      table: 'seasons',
      column: 'league_id',
      value: leagueId,
      orderBy: 'start_date',
      ascending: false,
    ).map((rows) => rows.map((r) => Season.fromMap(r)).toList());
  }

  Stream<List<Season>> _getSeasonsStream(String leagueId) {
    if (_lastLeagueIdForSeason != leagueId || _seasonsStream == null) {
      _lastLeagueIdForSeason = leagueId;
      _seasonsStream = _watchSeasons(leagueId);
    }
    return _seasonsStream!;
  }

  // İstatistikteki oyuncuların ad + fotoğrafı tek sorguda okunur (önceden
  // her satır ayrı sorgu atıyordu). Aynı oyuncu kümesi için tekrar okunmaz.
  String? _playersKey;
  Future<Map<String, _PlayerLite>>? _playersFuture;

  Future<Map<String, _PlayerLite>> _playersFor(Set<String> ids) {
    final key = (ids.toList()..sort()).join(',');
    if (key == _playersKey && _playersFuture != null) return _playersFuture!;
    _playersKey = key;
    return _playersFuture = () async {
      if (ids.isEmpty) return const <String, _PlayerLite>{};
      // İstatistik anahtarı oyuncunun telefonu, telefonu yoksa id'si.
      final uuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false,
      );
      final byId = ids.where(uuid.hasMatch).toList();
      final byPhone = ids.where((k) => !uuid.hasMatch(k)).toList();
      final client = Supabase.instance.client;
      final rows = [
        if (byId.isNotEmpty)
          ...await client
              .from('players')
              .select('id, phone, name, surname, photo_url')
              .inFilter('id', byId),
        if (byPhone.isNotEmpty)
          ...await client
              .from('players')
              .select('id, phone, name, surname, photo_url')
              .inFilter('phone', byPhone),
      ];
      final out = <String, _PlayerLite>{};
      for (final r in rows) {
        final p = _PlayerLite(
          name: [
            (r['name'] ?? '').toString().trim(),
            (r['surname'] ?? '').toString().trim(),
          ].where((e) => e.isNotEmpty).join(' '),
          photoUrl: (r['photo_url'] ?? '').toString().trim(),
        );
        for (final k in [r['id'], r['phone']]) {
          final key = (k ?? '').toString().trim();
          if (key.isNotEmpty) out[key] = p;
        }
      }
      return out;
    }();
  }

  @override
  void initState() {
    super.initState();
    _leaguesStream = _leagueService.watchLeagues();
    _selectedLeagueId = GlobalFilter.leagueId.value;
    _selectedSeasonId = GlobalFilter.seasonId.value;
    GlobalFilter.leagueId.addListener(_onGlobalFilterChanged);
    GlobalFilter.seasonId.addListener(_onGlobalFilterChanged);
  }

  void _onGlobalFilterChanged() {
    if (!mounted) return;
    setState(() {
      _selectedLeagueId = GlobalFilter.leagueId.value;
      _selectedSeasonId = GlobalFilter.seasonId.value;
    });
  }

  @override
  void dispose() {
    GlobalFilter.leagueId.removeListener(_onGlobalFilterChanged);
    GlobalFilter.seasonId.removeListener(_onGlobalFilterChanged);
    super.dispose();
  }

  // İSTATİSTİK EKRANI İÇİN ORTADAN AÇILAN FİLTRE DİALOGU; seçimler yalnızca
  // "Filtreleri Uygula" ile ekrana yansır.
  Future<void> _showFilterDialog(
    BuildContext context,
    List<League> leagues,
  ) async {
    final result = await showTournamentFilterDialog(
      context: context,
      leagues: leagues,
      initial: TournamentFilter(
        leagueId: _selectedLeagueId,
        seasonId: _selectedSeasonId,
      ),
      watchSeasons: _watchSeasons,
    );
    if (result == null || !mounted) return;
    GlobalFilter.setLeague(result.leagueId);
    GlobalFilter.setSeason(result.seasonId);
    setState(() {
      _selectedLeagueId = result.leagueId;
      _selectedSeasonId = result.seasonId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const bgDark = Color(0xFF0F172A);

    return StreamBuilder<List<League>>(
      stream: _leaguesStream,
      builder: (context, leaguesSnap) {
        if (!leaguesSnap.hasData &&
            leaguesSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: bgDark,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final leagues = leaguesSnap.data ?? const <League>[];
        if (leagues.isEmpty) {
          return const Scaffold(
            backgroundColor: bgDark,
            body: Center(
              child: Text(
                'Turnuva bulunamadı.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: bgDark,
          extendBodyBehindAppBar: true,
          appBar: const MasterClassAppBar(title: 'İstatistik'),
          body: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: 0.15,
                  child: Image.asset(
                    'assets/images/background_ball.jpg',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    // KAPSÜL BÖLÜMÜ
                    StreamBuilder<List<Season>>(
                      stream: _selectedLeagueId == null
                          ? Stream.value([])
                          : _getSeasonsStream(_selectedLeagueId!),
                      builder: (context, seasonSnap) {
                        // Turnuva değişince yeni sezonlar gelene kadar eski
                        // turnuvanınkiler tutulur; onlarla seçim yapılmasın.
                        final seasons =
                            seasonSnap.connectionState ==
                                ConnectionState.waiting
                            ? const <Season>[]
                            : (seasonSnap.data ?? const <Season>[]);

                        if (seasons.isNotEmpty &&
                            _selectedSeasonId == null &&
                            GlobalFilter.seasonId.value == null) {
                          final defaultSeason = pickDefaultSeasonId(seasons);

                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            GlobalFilter.setSeason(defaultSeason);
                          });
                        }

                        final currentLeagueName = leagues
                            .firstWhere(
                              (l) => l.id == _selectedLeagueId,
                              orElse: () => leagues.first,
                            )
                            .name;
                        final currentSeasonName = seasons.isEmpty
                            ? ''
                            : seasons
                                  .firstWhere(
                                    (s) => s.id == _selectedSeasonId,
                                    orElse: () => seasons.first,
                                  )
                                  .name;

                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: InkWell(
                            onTap: () => _showFilterDialog(context, leagues),
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white24),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.tune_rounded,
                                    color: Color(0xFF10B981),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      "$currentLeagueName • $currentSeasonName",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.keyboard_arrow_down,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // LİSTE BÖLÜMÜ
                    Expanded(
                      child: _selectedSeasonId == null
                          ? const Center(
                              child: Text(
                                'Lütfen bir turnuva ve sezon seçin.',
                                style: TextStyle(color: Colors.white),
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: StreamBuilder<List<Team>>(
                                stream: _teamService.watchAllTeams(),
                                builder: (context, teamsSnap) {
                                  if (!teamsSnap.hasData &&
                                      teamsSnap.connectionState ==
                                          ConnectionState.waiting) {
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  }

                                  final teams =
                                      (teamsSnap.data ?? const <Team>[])
                                          .where(
                                            (t) => t.id != 'free_agent_pool',
                                          )
                                          .toList();
                                  final teamById = {
                                    for (final t in teams) t.id: t,
                                  };

                                  return StreamBuilder<List<PlayerStats>>(
                                    stream: _matchService.watchPlayerStats(
                                      tournamentId: _selectedSeasonId ?? '',
                                    ),
                                    builder: (context, statsSnap) {
                                      if (!statsSnap.hasData &&
                                          statsSnap.connectionState ==
                                              ConnectionState.waiting) {
                                        return const Center(
                                          child: CircularProgressIndicator(),
                                        );
                                      }

                                      // Sadece golü veya asisti olan oyuncuları dahil et
                                      final stats =
                                          (statsSnap.data ??
                                                  const <PlayerStats>[])
                                              .where(
                                                (s) =>
                                                    (s.goals > 0 ||
                                                    s.assists > 0),
                                              )
                                              .toList();

                                      if (stats.isEmpty) {
                                        return Center(
                                          child: Text(
                                            'Bu sezon için istatistik bulunmuyor.',
                                            style: TextStyle(
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        );
                                      }

                                      final ids = stats
                                          .map((s) => s.playerPhone)
                                          .toSet();
                                      return FutureBuilder<
                                        Map<String, _PlayerLite>
                                      >(
                                        future: _playersFor(ids),
                                        builder: (context, pSnap) => _StatsTabs(
                                          stats: stats,
                                          teamById: teamById,
                                          players:
                                              pSnap.data ??
                                              const <String, _PlayerLite>{},
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniTeamLogo extends StatelessWidget {
  const _MiniTeamLogo({required this.logoUrl, required this.fallbackText});
  final String logoUrl;
  final String fallbackText;

  String _normalizeUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return 'https://$url';
  }

  @override
  Widget build(BuildContext context) {
    final url = _normalizeUrl(logoUrl);
    return WebSafeImage(
      url: url,
      width: 16,
      height: 16,
      fit: BoxFit.contain,
      fallbackIconSize: 12,
    );
  }
}

// ---------------------------------------------------------------------------
// Krallık sekmeleri: kürsü (ilk 3) + sıralama listesi.
// ---------------------------------------------------------------------------

const _accent = Color(0xFF10B981);
const _card = Color(0xFF1E293B);
const _muted = Color(0xFF94A3B8);
const _gold = Color(0xFFFBBF24);
const _silver = Color(0xFFCBD5E1);
const _bronze = Color(0xFFD97706);

class _PlayerLite {
  const _PlayerLite({required this.name, required this.photoUrl});
  final String name;
  final String photoUrl;
}

/// Sıralanmış satır: eşit değerdekiler aynı sırayı paylaşır (1, 2, 2, 4).
class _Ranked {
  const _Ranked(this.rank, this.stats, this.value);
  final int rank;
  final PlayerStats stats;
  final int value;
}

List<_Ranked> _rank(List<PlayerStats> all, int Function(PlayerStats) value) {
  final list = all.where((s) => value(s) > 0).toList()
    ..sort((a, b) {
      final c = value(b).compareTo(value(a));
      if (c != 0) return c;
      // Eşitlikte daha az maçta yapan önde.
      return a.matchesPlayed.compareTo(b.matchesPlayed);
    });
  final out = <_Ranked>[];
  for (var i = 0; i < list.length && i < 10; i++) {
    final v = value(list[i]);
    final rank = i > 0 && value(list[i - 1]) == v ? out[i - 1].rank : i + 1;
    out.add(_Ranked(rank, list[i], v));
  }
  return out;
}

class _StatsTabs extends StatefulWidget {
  const _StatsTabs({
    required this.stats,
    required this.teamById,
    required this.players,
  });

  final List<PlayerStats> stats;
  final Map<String, Team> teamById;
  final Map<String, _PlayerLite> players;

  @override
  State<_StatsTabs> createState() => _StatsTabsState();
}

class _StatsTabsState extends State<_StatsTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (mounted) setState(() {});
    });

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Widget _tabButton(int index, IconData icon, String label) {
    final selected = _tabs.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabs.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? _accent : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _accent.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : Colors.white60,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: _card.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                _tabButton(0, Icons.sports_soccer_rounded, 'Gol Krallığı'),
                const SizedBox(width: 6),
                _tabButton(1, Icons.assistant_rounded, 'Asist Krallığı'),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _Board(
                rows: _rank(widget.stats, (s) => s.goals),
                unit: 'gol',
                icon: Icons.sports_soccer_rounded,
                teamById: widget.teamById,
                players: widget.players,
              ),
              _Board(
                rows: _rank(widget.stats, (s) => s.assists),
                unit: 'asist',
                icon: Icons.assistant_rounded,
                teamById: widget.teamById,
                players: widget.players,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({
    required this.rows,
    required this.unit,
    required this.icon,
    required this.teamById,
    required this.players,
  });

  final List<_Ranked> rows;
  final String unit;
  final IconData icon;
  final Map<String, Team> teamById;
  final Map<String, _PlayerLite> players;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.white24),
            const SizedBox(height: 10),
            Text(
              'Henüz $unit kaydı yok.',
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }
    final podium = rows.take(3).toList();
    final rest = rows.skip(3).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
      children: [
        _Podium(rows: podium, unit: unit, teamById: teamById, players: players),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _card.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  for (var i = 0; i < rest.length; i++)
                    _RankRow(
                      row: rest[i],
                      unit: unit,
                      first: i == 0,
                      team: teamById[rest[i].stats.teamId],
                      player: players[rest[i].stats.playerPhone],
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

Color _medal(int rank) => switch (rank) {
  1 => _gold,
  2 => _silver,
  _ => _bronze,
};

/// İlk üç: 2. solda, 1. ortada (yüksek), 3. sağda.
class _Podium extends StatelessWidget {
  const _Podium({
    required this.rows,
    required this.unit,
    required this.teamById,
    required this.players,
  });

  final List<_Ranked> rows;
  final String unit;
  final Map<String, Team> teamById;
  final Map<String, _PlayerLite> players;

  Widget _slot(_Ranked? r, {required double height, required double avatar}) {
    if (r == null) return const Expanded(child: SizedBox());
    final color = _medal(r.rank);
    final player = players[r.stats.playerPhone];
    final team = teamById[r.stats.teamId];
    final name = (player?.name ?? '').isEmpty ? 'Oyuncu' : player!.name;
    return Expanded(
      child: Builder(
        builder: (context) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showPlayerCard(context, playerKey: r.stats.playerPhone),
          child: _slotBody(r, color, player, team, name, height, avatar),
        ),
      ),
    );
  }

  Widget _slotBody(
    _Ranked r,
    Color color,
    _PlayerLite? player,
    Team? team,
    String name,
    double height,
    double avatar,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (r.rank == 1)
          const Icon(Icons.workspace_premium_rounded, color: _gold, size: 28),
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [color, color.withValues(alpha: 0.45)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: _PlayerAvatar(
                name: name,
                photoUrl: player?.photoUrl ?? '',
                size: avatar,
              ),
            ),
            Positioned(
              bottom: -10,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF0F172A), width: 2),
                ),
                child: Text(
                  '${r.rank}',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 13,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MiniTeamLogo(logoUrl: team?.logoUrl ?? '', fallbackText: ''),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                team?.name ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Kürsü basamağı
        Container(
          height: height,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: 0.30),
                color.withValues(alpha: 0.05),
              ],
            ),
            border: Border(
              top: BorderSide(color: color.withValues(alpha: 0.7), width: 2),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text.rich(
                TextSpan(
                  text: '${r.value}',
                  style: TextStyle(
                    fontSize: r.rank == 1 ? 30 : 24,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                  children: [
                    TextSpan(
                      text: ' $unit',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                style: TextStyle(color: color),
              ),
              const SizedBox(height: 2),
              Text(
                '${r.stats.matchesPlayed} maç',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _Ranked? at(int i) => i < rows.length ? rows[i] : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _card.withValues(alpha: 0.94),
            const Color(0xFF064E3B).withValues(alpha: 0.85),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _slot(at(1), height: 78, avatar: 62),
          _slot(at(0), height: 104, avatar: 78),
          _slot(at(2), height: 62, avatar: 62),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.row,
    required this.unit,
    required this.first,
    required this.team,
    required this.player,
  });

  final _Ranked row;
  final String unit;
  final bool first;
  final Team? team;
  final _PlayerLite? player;

  @override
  Widget build(BuildContext context) {
    final name = (player?.name ?? '').isEmpty ? 'Oyuncu' : player!.name;
    return InkWell(
      onTap: () => showPlayerCard(context, playerKey: row.stats.playerPhone),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: first
              ? null
              : Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '${row.rank}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _PlayerAvatar(
              name: name,
              photoUrl: player?.photoUrl ?? '',
              size: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _MiniTeamLogo(
                        logoUrl: team?.logoUrl ?? '',
                        fallbackText: '',
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '${team?.name ?? ''} · ${row.stats.matchesPlayed} maç',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text.rich(
                TextSpan(
                  text: '${row.value}',
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                  children: [
                    TextSpan(
                      text: ' $unit',
                      style: const TextStyle(
                        fontSize: 11,
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
    );
  }
}

/// Oyuncu fotoğrafı; yoksa baş harfler.
class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({
    required this.name,
    required this.photoUrl,
    required this.size,
  });

  final String name;
  final String photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.characters.first)
        .join()
        .trUpper;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF064E3B),
      ),
      child: photoUrl.isNotEmpty
          ? WebSafeImage(
              url: photoUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              isCircle: true,
              fallbackIconSize: size * 0.4,
            )
          : Text(
              initials,
              style: TextStyle(
                color: const Color(0xFF6EE7B7),
                fontSize: size * 0.34,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}
