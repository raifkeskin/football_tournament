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
import '../../../core/widgets/web_safe_image.dart';
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
                    if (_selectedLeagueId == null || !leagueIds.contains(_selectedLeagueId)) {
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

                    final currentLeagueName = leagues.firstWhere(
                      (l) => l.id == _selectedLeagueId,
                      orElse: () => leagues.first,
                    ).name;

                    return StreamBuilder<List<Season>>(
                      stream: _selectedLeagueId == null
                          ? Stream.value([])
                          : _getSeasonsStream(_selectedLeagueId!),
                      builder: (context, seasonSnap) {
                        final seasons = seasonSnap.data ?? [];

                        if (_selectedLeagueId != null && seasons.isNotEmpty) {
                          if (_selectedSeasonId == null || !seasons.any((s) => s.id == _selectedSeasonId)) {
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
                            : seasons.firstWhere(
                                (s) => s.id == _selectedSeasonId,
                                orElse: () => seasons.first,
                              ).name;

                        // GRUP İSMİNİ BULMA 
                        return StreamBuilder<List<GroupModel>>(
                          stream: _selectedSeasonId == null
                              ? Stream.value([])
                              : _getGroupsStream(_selectedSeasonId!),
                          builder: (context, groupSnap) {
                            final groups = groupSnap.data ?? [];

                            String groupText = '';
                            if (_selectedGroupId != null && groups.any((g) => g.id == _selectedGroupId)) {
                              final g = groups.firstWhere((grp) => grp.id == _selectedGroupId);
                              groupText = ' • ${g.name}';
                            }

                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              child: InkWell(
                                onTap: () {
                                  // Kapsüle tıklanınca alt paneli aç (4 argüman eksiksiz)
                                  _showFilterDialog(context, leagues, seasons, groups);
                                },
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                      const Icon(Icons.tune_rounded, color: Color(0xFF10B981), size: 18),
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
                                      const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 18),
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

                            final allGroups = snapshot.data ?? const <GroupModel>[];
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
                                : allGroups.where((g) => g.id == _selectedGroupId).toList();

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
                    BoxShadow(color: Colors.black54, blurRadius: 15, offset: Offset(0, 8)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min, // KİLİT NOKTA: İçeriği ortada sıkıştırır
                  children: [
                    // 1. Turnuva Seçici
                    CustomPopupSelector<String>(
                      label: 'Turnuva',
                      selectedValue: _selectedLeagueId,
                      items: leagues.map((l) => l.id).toList(),
                      labelBuilder: (id) => leagues.firstWhere((l) => l.id == id, orElse: () => leagues.first).name,
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
                      labelBuilder: (id) => seasons.firstWhere((s) => s.id == id, orElse: () => seasons.first).name,
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Filtreleri Uygula', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
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
    if (id.isEmpty || sId.isEmpty)
      return const Stream<List<Map<String, dynamic>>>.empty();
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
    const bgDark = Color(0xFF0F172A);
    const tableBg = Color(0xFF1E293B);
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

                  if (h2hPointsB != h2hPointsA)
                    return h2hPointsB.compareTo(h2hPointsA);
                  if (h2hGoalDiffB != h2hGoalDiffA)
                    return h2hGoalDiffB.compareTo(h2hGoalDiffA);

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

              Widget headerCell(
                String text, {
                required double width,
                bool highlight = false,
              }) {
                return SizedBox(
                  width: width,
                  child: Center(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: highlight ? accentGreen : midText,
                      ),
                    ),
                  ),
                );
              }

              String groupLabel() {
                final name = widget.groupName.trim();
                if (name.isEmpty) return 'GRUP';
                final upper = name.toUpperCase();
                return upper.contains('GRUP') ? upper : '$upper GRUBU';
              }

              return Container(
                decoration: BoxDecoration(
                  color: tableBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.emoji_events_rounded,
                          color: trophy,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'PUAN DURUMU',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          groupLabel(),
                          style: const TextStyle(
                            color: midText,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Divider(color: midText.withValues(alpha: 0.35), height: 1),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: bgDark.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: midText.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 20,
                            child: Center(
                              child: Text(
                                '#',
                                style: TextStyle(
                                  color: midText,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'TAKIMLAR',
                              style: TextStyle(
                                color: midText,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          headerCell('O', width: 18),
                          headerCell('G', width: 18),
                          headerCell('B', width: 18),
                          headerCell('M', width: 18),
                          headerCell('A:Y', width: 34),
                          headerCell('AV', width: 24),
                          headerCell('P', width: 26, highlight: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: sortedTeamIds.length,
                      separatorBuilder: (_, _) => Divider(
                        color: midText.withValues(alpha: 0.18),
                        height: 1,
                      ),
                      itemBuilder: (context, i) {
                        final tId = sortedTeamIds[i];
                        final stats = standings[tId]!;
                        final tName = teamNames[tId] ?? 'Takım';
                        final tLogo = teamLogos[tId] ?? '';
                        return _StandingsRow(
                          index: i,
                          teamId: tId,
                          teamName: tName,
                          teamLogo: tLogo,
                          stats: stats,
                          totalCount: sortedTeamIds.length,
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

class _StandingsRow extends StatelessWidget {
  const _StandingsRow({
    required this.index,
    required this.teamId,
    required this.teamName,
    required this.teamLogo,
    required this.stats,
    required this.totalCount,
    required this.onTap,
  });

  final int index;
  final String teamId;
  final String teamName;
  final String teamLogo;
  final Map<String, dynamic> stats;
  final int totalCount;
  final VoidCallback onTap;

  String _normalizeUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return 'https://$url';
  }

  String _shortenMasters(String s) {
    return s
        .replaceAll('Masterlar', 'M.')
        .replaceAll('Master', 'M.')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    const midText = Color(0xFF94A3B8);
    const teamText = Color(0xFFF8FAFC);
    const accentGreen = Color(0xFF10B981);
    const classOrange = Color(0xFFF59E0B);
    const rowBg = Color(0xFF1E293B);
    const logoBg = Color(0xFF334155);

    Widget cell(
      dynamic text, {
      FontWeight weight = FontWeight.w700,
      Color? color,
      double width = 22,
      double fontSize = 11,
      FontStyle? fontStyle,
    }) {
      return SizedBox(
        width: width,
        child: Center(
          child: Text(
            text.toString(),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: weight,
              fontStyle: fontStyle,
              color: color ?? midText,
            ),
          ),
        ),
      );
    }

    final displayName = _shortenMasters(teamName);
    final url = _normalizeUrl(teamLogo);
    final isElite = index < 4;
    final isClass = totalCount >= 4 && index >= (totalCount - 4);
    final stripeColor = isElite
        ? accentGreen
        : (isClass ? classOrange : Colors.transparent);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: rowBg,
        child: Row(
          children: [
            SizedBox(
              width: 10,
              height: 46,
              child: Center(
                child: Container(
                  width: 2,
                  height: 25,
                  decoration: BoxDecoration(
                    color: stripeColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 24,
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: teamText,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: logoBg,
                    ),
                    child: WebSafeImage(
                      url: url,
                      width: 15,
                      height: 20,
                      isCircle: true,
                      fallbackIconSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: teamText,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            cell(stats['P'], width: 18),
            cell(stats['G'], width: 18),
            cell(stats['B'], width: 18),
            cell(stats['M'], width: 18),
            cell(
              '${stats['AG']}:${stats['YG']}',
              width: 34,
            ), 
            cell(stats['AV'], width: 24),
            cell(
              stats['Puan'],
              width: 26,
              weight: FontWeight.w900,
              color: accentGreen,
              fontSize: 14,
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}