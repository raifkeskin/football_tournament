import 'package:flutter/material.dart';
import '../models/league.dart';
import '../models/match.dart';
import '../models/team.dart';
import '../services/database_service.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _db = DatabaseService();
  String? _selectedLeagueId;

  String _trKey(String s) {
    return s
        .trim()
        .toLowerCase()
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .replaceAll('i̇', 'i')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('İstatistik')),
      body: StreamBuilder(
        stream: _db.getLeagues(),
        builder: (context, leaguesSnap) {
          if (!leaguesSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final leagues = leaguesSnap.data!.docs
              .map(
                (d) => League.fromMap(
                  {...d.data() as Map<String, dynamic>, 'id': d.id},
                ),
              )
              .toList();
          if (leagues.isEmpty) {
            return const Center(child: Text('Turnuva bulunamadı.'));
          }

          if (_selectedLeagueId == null) {
            final defaults = leagues.where((l) => l.isDefault).toList();
            if (defaults.isNotEmpty) {
              defaults.sort(
                (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
                  a.createdAt ?? DateTime(0),
                ),
              );
              _selectedLeagueId = defaults.first.id;
            } else {
              leagues.sort(
                (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
                  a.createdAt ?? DateTime(0),
                ),
              );
              _selectedLeagueId = leagues.first.id;
            }
          }

          final leagueId = _selectedLeagueId!;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<String>(
                  initialValue: leagueId,
                  decoration: const InputDecoration(labelText: 'Turnuva Seçimi'),
                  items: leagues
                      .map(
                        (l) => DropdownMenuItem(
                          value: l.id,
                          child: Text(l.name),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setState(() => _selectedLeagueId = val),
                ),
              ),
              Expanded(
                child: StreamBuilder(
                  stream: _db.getTeams(),
                  builder: (context, teamsSnap) {
                    if (!teamsSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final teams = teamsSnap.data!.docs
                        .map(
                          (d) => Team.fromMap(
                            {...d.data() as Map<String, dynamic>, 'id': d.id},
                          ),
                        )
                        .where((t) => t.leagueId == leagueId)
                        .toList();
                    final teamIds = teams.map((t) => t.id).toSet();
                    final teamById = {for (final t in teams) t.id: t};

                    return StreamBuilder<List<PlayerModel>>(
                      stream: _db.watchAllPlayers(),
                      builder: (context, playersSnap) {
                        if (!playersSnap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final players = playersSnap.data!
                            .where((p) => teamIds.contains(p.teamId))
                            .toList();

                        return StreamBuilder<List<MatchModel>>(
                          stream: _db.watchMatchesForLeague(leagueId),
                          builder: (context, matchesSnap) {
                            if (!matchesSnap.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final matches = matchesSnap.data!;

                            final appearances = <String, int>{};
                            void bump(String playerId) {
                              final id = playerId.trim();
                              if (id.isEmpty) return;
                              appearances[id] = (appearances[id] ?? 0) + 1;
                            }

                            for (final m in matches) {
                              final home = m.homeLineup;
                              final away = m.awayLineup;
                              if (home != null) {
                                for (final p in [...home.starting, ...home.subs]) {
                                  bump(p.playerId);
                                }
                              }
                              if (away != null) {
                                for (final p in [...away.starting, ...away.subs]) {
                                  bump(p.playerId);
                                }
                              }
                            }

                            List<PlayerModel> topBy(
                              int Function(PlayerModel p) getValue,
                            ) {
                              final list = [...players];
                              list.sort((a, b) {
                                final cmp =
                                    getValue(b).compareTo(getValue(a));
                                if (cmp != 0) return cmp;
                                return _trKey(a.name).compareTo(_trKey(b.name));
                              });
                              return list.where((p) => getValue(p) > 0).take(10).toList();
                            }

                            final topGoals = topBy((p) => p.goals);
                            final topAssists = topBy((p) => p.assists);

                            Widget table({
                              required String valueHeader,
                              required List<PlayerModel> rows,
                              required int Function(PlayerModel) getValue,
                            }) {
                              return ListView(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1B5E20),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(
                                      children: [
                                        const SizedBox(
                                          width: 28,
                                          child: Center(
                                            child: Text(
                                              '#',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const Expanded(
                                          flex: 6,
                                          child: Text(
                                            'Oyuncu',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        const Expanded(
                                          flex: 2,
                                          child: Text(
                                            'Maç',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            valueHeader,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  if (rows.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Text(
                                        'Veri yok.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    )
                                  else
                                    for (var i = 0; i < rows.length; i++)
                                      Card(
                                        margin: const EdgeInsets.only(bottom: 10),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 28,
                                                child: Center(
                                                  child: Text(
                                                    '${i + 1}.',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w900,
                                                      color: cs.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 6,
                                                child: Builder(
                                                  builder: (context) {
                                                    final p = rows[i];
                                                    final team =
                                                        teamById[p.teamId];
                                                    final teamName =
                                                        team?.name ?? '';
                                                    final teamLogo =
                                                        team?.logoUrl ?? '';
                                                    final fallback =
                                                        teamName.isNotEmpty
                                                            ? teamName[0]
                                                                .toUpperCase()
                                                            : '?';
                                                    return Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          p.name,
                                                          maxLines: 1,
                                                          overflow:
                                                              TextOverflow.ellipsis,
                                                          style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight.w900,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 3),
                                                        Row(
                                                          children: [
                                                            _MiniTeamLogo(
                                                              logoUrl: teamLogo,
                                                              fallbackText:
                                                                  fallback,
                                                            ),
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            Expanded(
                                                              child: Text(
                                                                teamName,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: TextStyle(
                                                                  color: cs
                                                                      .onSurfaceVariant,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  fontSize: 11,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  '${appearances[rows[i].id] ?? 0}',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  '${getValue(rows[i])}',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w900,
                                                    color: cs.primary,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                ],
                              );
                            }

                            return DefaultTabController(
                              length: 2,
                              child: Column(
                                children: [
                                  Container(
                                    margin: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      10,
                                    ),
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1B5E20),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const TabBar(
                                      labelColor: Colors.white,
                                      unselectedLabelColor: Colors.white70,
                                      indicatorColor: Colors.white,
                                      indicatorSize: TabBarIndicatorSize.tab,
                                      tabs: [
                                        Tab(text: 'Gol Krallığı'),
                                        Tab(text: 'Asist Krallığı'),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: TabBarView(
                                      children: [
                                        table(
                                          valueHeader: 'Gol',
                                          rows: topGoals,
                                          getValue: (p) => p.goals,
                                        ),
                                        table(
                                          valueHeader: 'Asist',
                                          rows: topAssists,
                                          getValue: (p) => p.assists,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
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
    final cs = Theme.of(context).colorScheme;
    final url = _normalizeUrl(logoUrl);
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.primary.withValues(alpha: 0.16),
      ),
      child: ClipOval(
        child: url.isNotEmpty
            ? Image.network(
                url,
                width: 16,
                height: 16,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Text(
                    fallbackText,
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      height: 1,
                    ),
                  ),
                ),
              )
            : Center(
                child: Text(
                  fallbackText,
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    height: 1,
                  ),
                ),
              ),
      ),
    );
  }
}
