import 'package:flutter/material.dart';
import 'package:football_tournament/core/widgets/master_class_app_bar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../tournament/models/league.dart';
import '../../tournament/models/season.dart';
import '../../match/models/match.dart';
import '../models/team.dart';
import '../../../core/config/app_config.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/services/global_filter.dart';
import 'team_squad_screen.dart';

// YENİ OLUŞTURDUĞUMUZ ORTAK BİLEŞENİ IMPORT EDİYORUZ
import '../../../core/widgets/custom_popup_selector.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({
    super.key,
    this.initialLeagueId,
    this.initialSeasonId,
    this.initialGroupId,
  });

  final String? initialLeagueId;
  final String? initialSeasonId;
  final String? initialGroupId;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  String? _selectedLeagueId;
  String? _selectedSeasonId;
  String? _selectedGroupId;

  Stream<List<League>>? _leaguesStream;

  String? _lastLeagueIdForSeason;
  Stream<List<Season>>? _seasonsStream;

  String? _lastSeasonIdForGroup;
  Stream<List<GroupModel>>? _groupsStream;

  Stream<List<Season>> _watchSeasons(String leagueId) {
    if (AppConfig.activeDatabase != DatabaseType.supabase) {
      return Stream.value([]);
    }
    return Supabase.instance.client
        .from('seasons')
        .stream(primaryKey: ['id'])
        .eq('league_id', leagueId)
        .order('start_date', ascending: false)
        .map((rows) => rows.map((r) => Season.fromMap(r)).toList());
  }

  @override
  void initState() {
    super.initState();
    _leaguesStream = _leagueService.watchLeagues();
    _selectedLeagueId = widget.initialLeagueId ?? GlobalFilter.leagueId.value;
    _selectedSeasonId = widget.initialSeasonId ?? GlobalFilter.seasonId.value;
    _selectedGroupId = widget.initialGroupId;

    GlobalFilter.leagueId.addListener(_onGlobalFilterChanged);
    GlobalFilter.seasonId.addListener(_onGlobalFilterChanged);
  }

  void _onGlobalFilterChanged() {
    if (!mounted) return;
    setState(() {
      _selectedLeagueId = GlobalFilter.leagueId.value ?? _selectedLeagueId;
      _selectedSeasonId = GlobalFilter.seasonId.value ?? _selectedSeasonId;
    });
  }

  @override
  void dispose() {
    GlobalFilter.leagueId.removeListener(_onGlobalFilterChanged);
    GlobalFilter.seasonId.removeListener(_onGlobalFilterChanged);
    super.dispose();
  }

  Stream<List<Season>> _getSeasonsStream(String leagueId) {
    if (_lastLeagueIdForSeason != leagueId || _seasonsStream == null) {
      _lastLeagueIdForSeason = leagueId;
      _seasonsStream = _watchSeasons(leagueId);
    }
    return _seasonsStream!;
  }

  Stream<List<GroupModel>> _getGroupsStream(String seasonId) {
    if (_lastSeasonIdForGroup != seasonId || _groupsStream == null) {
      _lastSeasonIdForGroup = seasonId;
      _groupsStream = _leagueService.watchGroups(seasonId);
    }
    return _groupsStream!;
  }

  @override
  Widget build(BuildContext context) {
    const bgDark = Color(0xFF0F172A);
    return Scaffold(
      backgroundColor: bgDark,
      extendBodyBehindAppBar: true,
      appBar: const MasterClassAppBar(title: 'Puan Durumu'),
      body: Stack(
        children: [
          // FİKSTÜR EKRANINDAKİ AYNI ARKA PLAN
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
                // 1. ÜST FİLTRE KAPSÜLÜ BÖLÜMÜ
                StreamBuilder<List<League>>(
                  stream: _leaguesStream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox();
                    final leagues = snapshot.data ?? const <League>[];
                    if (leagues.isEmpty) return const SizedBox();

                    final leagueIds = leagues.map((l) => l.id).toSet();
                    if (_selectedLeagueId == null ||
                        !leagueIds.contains(_selectedLeagueId)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          _selectedLeagueId = leagues.first.id;
                          _selectedSeasonId = null;
                          _selectedGroupId = null;
                        });
                        GlobalFilter.setLeague(leagues.first.id);
                      });
                    }

                    final currentLeagueName = leagues
                        .firstWhere(
                          (l) => l.id == _selectedLeagueId,
                          orElse: () => leagues.first,
                        )
                        .name;

                    return StreamBuilder<List<Season>>(
                      stream: _selectedLeagueId == null
                          ? Stream.value([])
                          : _getSeasonsStream(_selectedLeagueId!),
                      builder: (context, seasonSnap) {
                        final seasons = seasonSnap.data ?? [];

                        if (_selectedLeagueId != null && seasons.isNotEmpty) {
                          if (_selectedSeasonId == null ||
                              !seasons.any((s) => s.id == _selectedSeasonId)) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              setState(() {
                                _selectedSeasonId = seasons.first.id;
                                _selectedGroupId = null;
                              });
                              GlobalFilter.setSeason(seasons.first.id);
                            });
                          }
                        }

                        final currentSeasonName = seasons.isEmpty
                            ? ''
                            : seasons
                                  .firstWhere(
                                    (s) => s.id == _selectedSeasonId,
                                    orElse: () => seasons.first,
                                  )
                                  .name;

                        // GRUP İSMİNİ BULMA
                        return StreamBuilder<List<GroupModel>>(
                          stream: _selectedSeasonId == null
                              ? Stream.value([])
                              : _getGroupsStream(_selectedSeasonId!),
                          builder: (context, groupSnap) {
                            final groups = groupSnap.data ?? [];

                            String groupText = '';
                            if (_selectedGroupId != null &&
                                groups.any((g) => g.id == _selectedGroupId)) {
                              final g = groups.firstWhere(
                                (grp) => grp.id == _selectedGroupId,
                              );
                              groupText = ' • ${g.name}';
                            }

                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              child: InkWell(
                                onTap: () {
                                  // Kapsüle tıklanınca alt paneli aç (4 argüman eksiksiz)
                                  _showFilterDialog(
                                    context,
                                    leagues,
                                    seasons,
                                    groups,
                                  );
                                },
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.4),
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
                                          "$currentLeagueName • $currentSeasonName$groupText",
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
                        );
                      },
                    );
                  },
                ),

                // 2. PUAN DURUMU LİSTESİ
                Expanded(
                  child: _selectedSeasonId == null
                      ? const Center(
                          child: Text(
                            'Lütfen bir turnuva ve sezon seçin.',
                            style: TextStyle(color: Colors.white),
                          ),
                        )
                      : StreamBuilder<List<GroupModel>>(
                          stream: _getGroupsStream(_selectedSeasonId!),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final allGroups =
                                snapshot.data ?? const <GroupModel>[];
                            if (allGroups.isEmpty) {
                              return const Center(
                                child: Text(
                                  'Bu sezonda henüz grup oluşturulmamış.',
                                  style: TextStyle(color: Colors.white),
                                ),
                              );
                            }

                            final displayedGroups = _selectedGroupId == null
                                ? allGroups
                                : allGroups
                                      .where((g) => g.id == _selectedGroupId)
                                      .toList();

                            return ListView.builder(
                              padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
                              itemCount: displayedGroups.length,
                              itemBuilder: (context, index) {
                                final g = displayedGroups[index];
                                return _GroupStandingsTable(
                                  leagueId: _selectedLeagueId!,
                                  seasonId: _selectedSeasonId!,
                                  groupId: g.id,
                                  groupName: g.name,
                                  fetchGroupId: _selectedGroupId,
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Kapsüle tıklandığında açılacak Filtre Paneli (4 Argümanlı tam hali)
  // Kapsüle tıklandığında ORTADA açılacak Filtre Paneli
  void _showFilterDialog(
    BuildContext context,
    List<League> leagues,
    List<Season> seasons,
    List<GroupModel> groups,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E293B), Color(0xFF064E3B)],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 15,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize
                      .min, // KİLİT NOKTA: İçeriği ortada sıkıştırır
                  children: [
                    // 1. Turnuva Seçici
                    CustomPopupSelector<String>(
                      label: 'Turnuva',
                      selectedValue: _selectedLeagueId,
                      items: leagues.map((l) => l.id).toList(),
                      labelBuilder: (id) => leagues
                          .firstWhere(
                            (l) => l.id == id,
                            orElse: () => leagues.first,
                          )
                          .name,
                      onChanged: (val) {
                        setState(() {
                          _selectedLeagueId = val;
                          _selectedSeasonId = null;
                          _selectedGroupId = null;
                        });
                        setDialogState(() {});
                        GlobalFilter.setLeague(val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // 2. Sezon Seçici
                    CustomPopupSelector<String>(
                      label: 'Sezon',
                      selectedValue: _selectedSeasonId,
                      items: seasons.map((s) => s.id).toList(),
                      labelBuilder: (id) => seasons
                          .firstWhere(
                            (s) => s.id == id,
                            orElse: () => seasons.first,
                          )
                          .name,
                      onChanged: (val) {
                        setState(() {
                          _selectedSeasonId = val;
                          _selectedGroupId = null;
                        });
                        setDialogState(() {});
                        GlobalFilter.setSeason(val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // 3. Grup Seçici
                    if (groups.length > 1)
                      CustomPopupSelector<String?>(
                        label: 'Grup',
                        selectedValue: _selectedGroupId,
                        items: [null, ...groups.map((g) => g.id)],
                        labelBuilder: (id) {
                          if (id == null) return 'Tüm Gruplar';
                          final g = groups.firstWhere((grp) => grp.id == id);
                          return g.name.isEmpty ? 'Grup' : g.name;
                        },
                        onChanged: (val) {
                          setState(() => _selectedGroupId = val);
                          setDialogState(() {});
                        },
                      ),
                    if (groups.length > 1) const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Filtreleri Uygula',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GroupStandingsTable extends StatefulWidget {
  final String leagueId;
  final String seasonId;
  final String groupId;
  final String groupName;
  final String? fetchGroupId;

  const _GroupStandingsTable({
    required this.leagueId,
    required this.seasonId,
    required this.groupId,
    required this.groupName,
    required this.fetchGroupId,
  });

  @override
  State<_GroupStandingsTable> createState() => _GroupStandingsTableState();
}

class _GroupStandingsTableState extends State<_GroupStandingsTable> {
  Stream<List<Map<String, dynamic>>>? _matchesStream;
  Stream<List<Team>>? _teamsStream;

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  @override
  void didUpdateWidget(covariant _GroupStandingsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leagueId != widget.leagueId ||
        oldWidget.seasonId != widget.seasonId ||
        oldWidget.fetchGroupId != widget.fetchGroupId) {
      _initStreams();
    }
  }

  void _initStreams() {
    _matchesStream = _watchLeagueMatchesRaw(
      widget.leagueId,
      widget.seasonId,
      widget.fetchGroupId,
    );
    _teamsStream = ServiceLocator.teamService.watchAllTeams();
  }

  Stream<List<Map<String, dynamic>>> _watchLeagueMatchesRaw(
    String leagueId,
    String seasonId,
    String? fetchGroupId,
  ) {
    final id = leagueId.trim();
    final sId = seasonId.trim();
    if (id.isEmpty || sId.isEmpty) {
      return const Stream<List<Map<String, dynamic>>>.empty();
    }
    if (AppConfig.activeDatabase != DatabaseType.supabase) {
      final matchService = ServiceLocator.matchService;
      return matchService
          .watchMatchesForLeague(id)
          .map(
            (matches) => matches.map((m) => m.toMap(snakeCase: true)).toList(),
          );
    }
    return Supabase.instance.client
        .from('matches')
        .stream(primaryKey: ['id'])
        .order('match_date', ascending: true)
        .map((rows) {
          final filtered = rows.where((r) {
            final matchLeague = (r['league_id'] ?? '').toString().trim() == id;
            final matchSeason = (r['season_id'] ?? '').toString().trim() == sId;
            bool ok = matchLeague && matchSeason;
            if (fetchGroupId != null) {
              ok =
                  ok && (r['group_id'] ?? '').toString().trim() == fetchGroupId;
            }
            return ok;
          });
          return filtered.map((e) => Map<String, dynamic>.from(e)).toList();
        });
  }

  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim()) ?? 0;
  }

  int _matchHomeScore(Map<String, dynamic> m) {
    final score = m['score'] ?? m['score_json'] ?? m['scoreJson'];
    if (score is Map) {
      final fullTime = score['fullTime'];
      if (fullTime is Map && fullTime['home'] != null) {
        return _asInt(fullTime['home']);
      }
    }
    return _asInt(m['homeScore'] ?? m['home_score']);
  }

  int _matchAwayScore(Map<String, dynamic> m) {
    final score = m['score'] ?? m['score_json'] ?? m['scoreJson'];
    if (score is Map) {
      final fullTime = score['fullTime'];
      if (fullTime is Map && fullTime['away'] != null) {
        return _asInt(fullTime['away']);
      }
    }
    return _asInt(m['awayScore'] ?? m['away_score']);
  }

  @override
  Widget build(BuildContext context) {
    const midText = Color(0xFF94A3B8);
    const accentGreen = Color(0xFF10B981);
    const trophy = Color(0xFFFBBF24);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _matchesStream,
        builder: (context, mergedSnapshot) {
          if (mergedSnapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final matchListRaw =
              mergedSnapshot.data ?? const <Map<String, dynamic>>[];

          final groupMatches = matchListRaw.where((m) {
            final matchGroup =
                (m['group_id'] ?? m['groupId'] ?? m['groupName'] ?? '')
                    .toString()
                    .trim();
            if (matchGroup.isEmpty) return false;
            return matchGroup == widget.groupId ||
                matchGroup == widget.groupName.trim();
          }).toList();

          final groupTeamIds = <String>{};
          for (final m in groupMatches) {
            final hId = (m['home_team_id'] ?? m['homeTeamId'] ?? '')
                .toString()
                .trim();
            final aId = (m['away_team_id'] ?? m['awayTeamId'] ?? '')
                .toString()
                .trim();
            if (hId.isNotEmpty) groupTeamIds.add(hId);
            if (aId.isNotEmpty) groupTeamIds.add(aId);
          }

          return StreamBuilder<List<Team>>(
            stream: _teamsStream,
            builder: (context, teamsSnapshot) {
              if (teamsSnapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final allTeams = teamsSnapshot.data ?? const <Team>[];

              final teams = allTeams
                  .where((t) {
                    final tLeague = (t.leagueId ?? '').toString().trim();
                    final tGroup = (t.groupId ?? '').toString().trim();
                    final playedInGroup = groupTeamIds.contains(t.id);
                    final explicitlyAssigned =
                        (tLeague == widget.leagueId.trim() &&
                        tGroup == widget.groupId.trim());
                    return playedInGroup || explicitlyAssigned;
                  })
                  .toList(growable: false);

              final standings = <String, Map<String, dynamic>>{};
              final teamNames = <String, String>{};
              final teamLogos = <String, String>{};

              for (final t in teams) {
                final teamId = t.id;
                teamNames[teamId] = t.name;
                teamLogos[teamId] = t.logoUrl;
                standings[teamId] = {
                  'P': 0,
                  'G': 0,
                  'B': 0,
                  'M': 0,
                  'AG': 0,
                  'YG': 0,
                  'AV': 0,
                  'Puan': 0,
                };
              }

              if (standings.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: Text(
                      'Grup ${widget.groupName} için henüz takım/maç verisi yok.',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                );
              }

              for (final m in groupMatches) {
                final hId = (m['home_team_id'] ?? m['homeTeamId'] ?? '')
                    .toString();
                final aId = (m['away_team_id'] ?? m['awayTeamId'] ?? '')
                    .toString();

                final rawStatus = (m['status'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase();
                final completedFlag =
                    m['is_completed'] == true || m['isCompleted'] == true;
                final isCompleted =
                    completedFlag ||
                    rawStatus == 'finished' ||
                    rawStatus == 'completed';
                if (isCompleted &&
                    standings.containsKey(hId) &&
                    standings.containsKey(aId)) {
                  final hS = _matchHomeScore(m);
                  final aS = _matchAwayScore(m);

                  standings[hId]!['P'] = standings[hId]!['P']! + 1;
                  standings[aId]!['P'] = standings[aId]!['P']! + 1;
                  standings[hId]!['AG'] = standings[hId]!['AG']! + hS;
                  standings[hId]!['YG'] = standings[hId]!['YG']! + aS;
                  standings[aId]!['AG'] = standings[aId]!['AG']! + aS;
                  standings[aId]!['YG'] = standings[aId]!['YG']! + hS;

                  if (hS > aS) {
                    standings[hId]!['G'] = standings[hId]!['G']! + 1;
                    standings[hId]!['Puan'] = standings[hId]!['Puan']! + 3;
                    standings[aId]!['M'] = standings[aId]!['M']! + 1;
                  } else if (aS > hS) {
                    standings[aId]!['G'] = standings[aId]!['G']! + 1;
                    standings[aId]!['Puan'] = standings[aId]!['Puan']! + 3;
                    standings[hId]!['M'] = standings[hId]!['M']! + 1;
                  } else {
                    standings[hId]!['B'] = standings[hId]!['B']! + 1;
                    standings[aId]!['B'] = standings[aId]!['B']! + 1;
                    standings[hId]!['Puan'] = standings[hId]!['Puan']! + 1;
                    standings[aId]!['Puan'] = standings[aId]!['Puan']! + 1;
                  }
                }
              }

              standings.forEach((_, v) {
                v['AV'] = v['AG']! - v['YG']!;
              });

              final sortedTeamIds = standings.keys.toList()
                ..sort((a, b) {
                  final sa = standings[a]!;
                  final sb = standings[b]!;

                  final pA = _asInt(sa['Puan']);
                  final pB = _asInt(sb['Puan']);
                  if (pB != pA) return pB.compareTo(pA);

                  int h2hPointsA = 0;
                  int h2hPointsB = 0;
                  int h2hGoalDiffA = 0;
                  int h2hGoalDiffB = 0;

                  for (final m in groupMatches) {
                    final hId = (m['home_team_id'] ?? m['homeTeamId'] ?? '')
                        .toString();
                    final aId = (m['away_team_id'] ?? m['awayTeamId'] ?? '')
                        .toString();

                    final rawStatus = (m['status'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase();
                    final completedFlag =
                        m['is_completed'] == true || m['isCompleted'] == true;
                    final isCompleted =
                        completedFlag ||
                        rawStatus == 'finished' ||
                        rawStatus == 'completed';

                    if (isCompleted &&
                        ((hId == a && aId == b) || (hId == b && aId == a))) {
                      final hS = _matchHomeScore(m);
                      final aS = _matchAwayScore(m);

                      if (hId == a) {
                        h2hGoalDiffA += (hS - aS);
                        h2hGoalDiffB += (aS - hS);
                        if (hS > aS) {
                          h2hPointsA += 3;
                        } else if (hS < aS) {
                          h2hPointsB += 3;
                        } else {
                          h2hPointsA += 1;
                          h2hPointsB += 1;
                        }
                      } else {
                        h2hGoalDiffB += (hS - aS);
                        h2hGoalDiffA += (aS - hS);
                        if (hS > aS) {
                          h2hPointsB += 3;
                        } else if (hS < aS) {
                          h2hPointsA += 3;
                        } else {
                          h2hPointsB += 1;
                          h2hPointsA += 1;
                        }
                      }
                    }
                  }

                  if (h2hPointsB != h2hPointsA) {
                    return h2hPointsB.compareTo(h2hPointsA);
                  }
                  if (h2hGoalDiffB != h2hGoalDiffA) {
                    return h2hGoalDiffB.compareTo(h2hGoalDiffA);
                  }

                  final avA = _asInt(sa['AV']);
                  final avB = _asInt(sb['AV']);
                  if (avB != avA) return avB.compareTo(avA);

                  final agA = _asInt(sa['AG']);
                  final agB = _asInt(sb['AG']);
                  if (agB != agA) return agB.compareTo(agA);

                  return teamNames[a]!.toLowerCase().compareTo(
                    teamNames[b]!.toLowerCase(),
                  );
                });

              String groupLabel() {
                final name = widget.groupName.trim();
                if (name.isEmpty) return 'Grup';
                return name.toLowerCase().contains('grup')
                    ? name
                    : '$name Grubu';
              }

              // 4'ten az takımda bölge şeritleri anlamsız (hepsi yeşil olur).
              final showZones = sortedTeamIds.length > 4;

              return Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Başlık
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: trophy.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.emoji_events_rounded,
                              color: trophy,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Puan Durumu',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                    // Sütun başlıkları
                    Container(
                      color: Colors.white.withValues(alpha: 0.04),
                      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                      child: const _StandingsHeaderRow(),
                    ),
                    for (var i = 0; i < sortedTeamIds.length; i++)
                      Builder(
                        builder: (context) {
                          final tId = sortedTeamIds[i];
                          final tName = teamNames[tId] ?? 'Takım';
                          final tLogo = teamLogos[tId] ?? '';
                          return _StandingsRow(
                            index: i,
                            teamId: tId,
                            teamName: tName,
                            teamLogo: tLogo,
                            stats: standings[tId]!,
                            totalCount: sortedTeamIds.length,
                            showZones: showZones,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TeamSquadScreen(
                                    teamId: tId,
                                    tournamentId: widget.leagueId,
                                    teamName: tName,
                                    teamLogoUrl: tLogo,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    // Açıklama
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: [
                          if (showZones) ...[
                            const _LegendDot(
                              color: accentGreen,
                              label: 'Üst tur',
                            ),
                            const _LegendDot(
                              color: Color(0xFFF59E0B),
                              label: 'Klasman',
                            ),
                          ],
                          Text(
                            'O: Oynanan  G: Galibiyet  B: Beraberlik  '
                            'M: Mağlubiyet  A:Y: Atılan/Yenilen  AV: Averaj',
                            style: TextStyle(
                              color: midText.withValues(alpha: 0.8),
                              fontSize: 10,
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
        },
      ),
    );
  }
}

// Sütun genişlikleri başlık ve satırlarda ortak kullanılır.
const double _kRankW = 26;
const double _kStatW = 22;
const double _kGoalsW = 42;
const double _kAvW = 30;
const double _kPtsW = 36;
const _kMidText = Color(0xFF94A3B8);
const _kAccent = Color(0xFF10B981);

/// Dar ekranlarda (ör. 360dp) takım adına yer kalsın diye G/B/M gizlenir.
bool _isCompactStandings(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 390;

const _tabular = [FontFeature.tabularFigures()];

class _StandingsHeaderRow extends StatelessWidget {
  const _StandingsHeaderRow();

  @override
  Widget build(BuildContext context) {
    Widget h(String t, double w, {bool highlight = false}) => SizedBox(
      width: w,
      child: Text(
        t,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: highlight ? _kAccent : _kMidText,
        ),
      ),
    );

    return Row(
      children: [
        h('#', _kRankW),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Takım',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: _kMidText,
            ),
          ),
        ),
        h('O', _kStatW),
        if (!_isCompactStandings(context)) ...[
          h('G', _kStatW),
          h('B', _kStatW),
          h('M', _kStatW),
        ],
        h('A:Y', _kGoalsW),
        h('AV', _kAvW),
        const SizedBox(width: 4),
        h('P', _kPtsW, highlight: true),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: _kMidText, fontSize: 10)),
      ],
    );
  }
}

class _StandingsRow extends StatelessWidget {
  const _StandingsRow({
    required this.index,
    required this.teamId,
    required this.teamName,
    required this.teamLogo,
    required this.stats,
    required this.totalCount,
    required this.showZones,
    required this.onTap,
  });

  final int index;
  final String teamId;
  final String teamName;
  final String teamLogo;
  final Map<String, dynamic> stats;
  final int totalCount;
  final bool showZones;
  final VoidCallback onTap;

  String _shortenMasters(String s) {
    return s
        .replaceAll('Masterlar', 'M.')
        .replaceAll('Master', 'M.')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  int _asInt(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    const teamText = Color(0xFFF8FAFC);
    const classOrange = Color(0xFFF59E0B);
    const negative = Color(0xFFF87171);

    Widget stat(String text, double width, {Color? color, FontWeight? w}) {
      return SizedBox(
        width: width,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: w ?? FontWeight.w600,
              color: color ?? const Color(0xFFCBD5E1),
              fontFeatures: _tabular,
            ),
          ),
        ),
      );
    }

    final displayName = _shortenMasters(teamName);
    final isLeader = index == 0 && _asInt(stats['P']) > 0;

    Color zoneColor = Colors.transparent;
    if (showZones) {
      if (index < 4) {
        zoneColor = _kAccent;
      } else if (index >= totalCount - 4) {
        zoneColor = classOrange;
      }
    }

    final av = _asInt(stats['AV']);
    final avText = av > 0 ? '+$av' : '$av';
    final avColor = av > 0 ? _kAccent : (av < 0 ? negative : _kMidText);

    final rowColor = isLeader
        ? _kAccent.withValues(alpha: 0.08)
        : (index.isOdd
              ? Colors.white.withValues(alpha: 0.025)
              : Colors.transparent);

    return Material(
      color: rowColor,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: zoneColor, width: 3),
              top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 9),
              // Sıra
              SizedBox(
                width: _kRankW,
                child: Center(
                  child: Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isLeader
                          ? _kAccent
                          : Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: isLeader ? Colors.white : teamText,
                        fontSize: 12,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Takım
              // Logo yok: ad her zaman tam görünür; yine de sığmazsa "…" ile
              // kesilmek yerine yazı hafifçe küçülür.
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    displayName,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: teamText,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              stat('${stats['P']}', _kStatW),
              if (!_isCompactStandings(context)) ...[
                stat('${stats['G']}', _kStatW),
                stat('${stats['B']}', _kStatW),
                stat('${stats['M']}', _kStatW),
              ],
              stat('${stats['AG']}:${stats['YG']}', _kGoalsW),
              stat(avText, _kAvW, color: avColor, w: FontWeight.w700),
              const SizedBox(width: 4),
              // Puan
              SizedBox(
                width: _kPtsW,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _kAccent.withValues(alpha: isLeader ? 0.25 : 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${stats['Puan']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: _kAccent,
                        fontSize: 15,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
