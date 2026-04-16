import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/league.dart';
import '../models/player_stats.dart';
import '../models/team.dart';
import '../services/database_service.dart';
import '../widgets/web_safe_image.dart';

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
    return StreamBuilder(
      stream: _db.getLeagues(),
      builder: (context, leaguesSnap) {
        if (!leaguesSnap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final leagues = leaguesSnap.data!.docs
            .map(
              (d) => League.fromMap(
                {...d.data() as Map<String, dynamic>, 'id': d.id},
              ),
            )
            .toList();
        if (leagues.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('Turnuva bulunamadı.')),
          );
        }

        if (_selectedLeagueId == null) {
          final defaults = leagues.where((l) => l.isDefault).toList();
          if (defaults.isNotEmpty) {
            defaults.sort(
              (a, b) =>
                  (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
            );
            _selectedLeagueId = defaults.first.id;
          } else {
            leagues.sort(
              (a, b) =>
                  (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
            );
            _selectedLeagueId = leagues.first.id;
          }
        }

        final leagueId = _selectedLeagueId!;

        return Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.bar_chart_outlined),
                SizedBox(width: 8),
                Text('İstatistik'),
              ],
            ),
          ),
          body: Column(
            children: [
              Container(
                color: const Color(0xFF064E3B),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                child: DropdownButtonFormField<String>(
                  initialValue: leagueId,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E293B),
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white,
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Turnuva Seçin',
                    labelStyle: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.white54),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  items: leagues
                      .map(
                        (l) => DropdownMenuItem(
                          value: l.id,
                          child: Text(
                            l.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setState(() => _selectedLeagueId = val),
                ),
              ),
              Expanded(
                child: Transform.translate(
                  offset: const Offset(0, -20),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F172A),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    padding: const EdgeInsets.only(top: 34),
                    child: StreamBuilder(
                      stream: _db.getTeams(),
                      builder: (context, teamsSnap) {
                        if (!teamsSnap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

              final teams = teamsSnap.data!.docs
                  .where((d) => d.id != 'free_agent_pool')
                  .map(
                    (d) => Team.fromMap(
                      {...d.data() as Map<String, dynamic>, 'id': d.id},
                    ),
                  )
                  .toList();
              final teamIds = teams.map((t) => t.id).toSet();
              final teamById = {for (final t in teams) t.id: t};

                        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('player_stats')
                              .where('tournamentId', isEqualTo: leagueId)
                              .snapshots(),
                          builder: (context, statsSnap) {
                            if (!statsSnap.hasData) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final stats = statsSnap.data!.docs
                                .map((d) => PlayerStats.fromMap(d.data(), d.id))
                                .where((s) => s.playerPhone.trim().isNotEmpty)
                                .toList();

                            List<PlayerStats> topBy(int Function(PlayerStats s) getValue) {
                              final list = [...stats];
                              list.sort((a, b) {
                                final cmp = getValue(b).compareTo(getValue(a));
                                if (cmp != 0) return cmp;
                                return a.playerPhone.compareTo(b.playerPhone);
                              });
                              return list.where((s) => getValue(s) > 0).take(10).toList();
                            }

                            final topGoals = topBy((s) => s.goals);
                            final topAssists = topBy((s) => s.assists);

                            Widget table({
                              required String valueHeader,
                              required List<PlayerStats> rows,
                              required int Function(PlayerStats) getValue,
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
                                      color: const Color(0xFF064E3B),
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
                                      padding: const EdgeInsets.symmetric(vertical: 12),
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
                                                    final s = rows[i];
                                                    final team = teamById[s.teamId];
                                                    final teamName = team?.name ?? '';
                                                    final teamLogo = team?.logoUrl ?? '';
                                                    final fallback = teamName.isNotEmpty
                                                        ? teamName[0].toUpperCase()
                                                        : '?';
                                                    return Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        FutureBuilder<
                                                            DocumentSnapshot<Map<String, dynamic>>>(
                                                          future: FirebaseFirestore.instance
                                                              .collection('players')
                                                              .doc(s.playerPhone)
                                                              .get(),
                                                          builder: (context, pSnap) {
                                                            final name = (pSnap.data?.data()?['name']
                                                                        as String?)
                                                                    ?.trim() ??
                                                                s.playerPhone;
                                                            return Text(
                                                              name,
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: const TextStyle(
                                                                fontWeight: FontWeight.w900,
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                        const SizedBox(height: 3),
                                                        Row(
                                                          children: [
                                                            _MiniTeamLogo(
                                                              logoUrl: teamLogo,
                                                              fallbackText: fallback,
                                                            ),
                                                            const SizedBox(width: 6),
                                                            Expanded(
                                                              child: Text(
                                                                teamName,
                                                                maxLines: 1,
                                                                overflow: TextOverflow.ellipsis,
                                                                style: TextStyle(
                                                                  color: cs.onSurfaceVariant,
                                                                  fontWeight: FontWeight.w600,
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
                                                  '${rows[i].matchesPlayed}',
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
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned(
                                    top: -22,
                                    left: 16,
                                    right: 16,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E293B),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const TabBar(
                                        labelColor: Colors.white,
                                        unselectedLabelColor: Colors.white70,
                                        indicatorColor: Colors.white,
                                        indicatorSize: TabBarIndicatorSize.tab,
                                        labelStyle: TextStyle(
                                          fontWeight: FontWeight.w900,
                                        ),
                                        tabs: [
                                          Tab(text: 'Gol Krallığı'),
                                          Tab(text: 'Asist Krallığı'),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    top: 34,
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 120),
                                      child: TabBarView(
                                        children: [
                                          table(
                                            valueHeader: 'Gol',
                                            rows: topGoals,
                                            getValue: (s) => s.goals,
                                          ),
                                          table(
                                            valueHeader: 'Asist',
                                            rows: topAssists,
                                            getValue: (s) => s.assists,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
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
    final cs = Theme.of(context).colorScheme;
    final url = _normalizeUrl(logoUrl);
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.primary.withValues(alpha: 0.16),
      ),
      child: WebSafeImage(
        url: url,
        width: 16,
        height: 16,
        isCircle: true,
        fallbackIconSize: 12,
      ),
    );
  }
}
