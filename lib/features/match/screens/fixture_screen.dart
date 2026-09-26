import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:football_tournament/core/widgets/master_class_app_bar.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:ui';

import '../../../core/config/app_config.dart';
import '../../tournament/models/league.dart';
import '../../tournament/models/season.dart';
import '../models/match.dart';
import '../../team/models/team.dart';
import '../../../core/services/app_session.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../services/interfaces/i_match_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/services/global_filter.dart';
import 'match_details_screen.dart';

// ORTAK BİLEŞEN IMPORT EDİLDİ
import '../../../core/widgets/custom_popup_selector.dart';

class FixtureScreen extends StatefulWidget {
  const FixtureScreen({super.key});

  @override
  State<FixtureScreen> createState() => _FixtureScreenState();
}

class _FixtureScreenState extends State<FixtureScreen> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final IMatchService _matchService = ServiceLocator.matchService;
  final ITeamService _teamService = ServiceLocator.teamService;
  String? _leagueId;
  String? _seasonId;
  String? _groupId;
  int? _week;

  Stream<List<Team>>? _teamsStream;
  Stream<List<League>>? _leaguesStream;

  String? _lastLeagueIdForSeason;
  Stream<List<Season>>? _seasonsStream;

  String? _lastSeasonIdForGroup;
  Stream<List<GroupModel>>? _groupsStream;

  @override
  void initState() {
    super.initState();
    _teamsStream = _teamService.watchAllTeams();
    _leaguesStream = _leagueService.watchLeagues();
    _leagueId = GlobalFilter.leagueId.value;
    _seasonId = GlobalFilter.seasonId.value;
    _groupId = GlobalFilter.groupId.value;

    GlobalFilter.leagueId.addListener(_onGlobalFilterChanged);
    GlobalFilter.seasonId.addListener(_onGlobalFilterChanged);
    GlobalFilter.groupId.addListener(_onGlobalFilterChanged);
  }

  void _onGlobalFilterChanged() {
    if (!mounted) return;
    setState(() {
      _leagueId = GlobalFilter.leagueId.value ?? _leagueId;
      _seasonId = GlobalFilter.seasonId.value ?? _seasonId;
      _groupId = GlobalFilter.groupId.value ?? _groupId;
    });
  }

  @override
  void dispose() {
    GlobalFilter.leagueId.removeListener(_onGlobalFilterChanged);
    GlobalFilter.seasonId.removeListener(_onGlobalFilterChanged);
    GlobalFilter.groupId.removeListener(_onGlobalFilterChanged);
    super.dispose();
  }

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

  DateTime? _parseYyyyMmDd(String yyyyMmDd) {
    final s = yyyyMmDd.trim();
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (m == null) return null;
    final y = int.tryParse(m.group(1) ?? '');
    final mo = int.tryParse(m.group(2) ?? '');
    final d = int.tryParse(m.group(3) ?? '');
    if (y == null || mo == null || d == null) return null;
    return DateTime(y, mo, d);
  }

  String _dateStripText(String yyyyMmDd) {
    final s = yyyyMmDd.trim();
    final dt = _parseYyyyMmDd(s);
    if (dt == null) return s;
    return DateFormat('dd.MM.yyyy EEEE', 'tr_TR').format(dt);
  }

  // ORTADA AÇILAN FİKSTÜR FİLTRE DİALOGU
  void _showFilterDialog(
    BuildContext context,
    List<League> leagues,
    List<Season> seasons,
    List<GroupModel> groups,
    Map<String, String> groupNameById,
    List<int> weeks,
    int currentWeek,
    String? currentGroupId,
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
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1. Turnuva Seçici
                    CustomPopupSelector<String>(
                      label: 'Turnuva',
                      selectedValue: _leagueId,
                      items: leagues.map((l) => l.id).toList(),
                      labelBuilder: (id) => leagues.firstWhere((l) => l.id == id, orElse: () => leagues.first).name,
                      onChanged: (val) {
                        setState(() {
                          _leagueId = val;
                          _seasonId = null;
                          _groupId = null;
                          _week = null;
                        });
                        setDialogState(() {});
                        GlobalFilter.setLeague(val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // 2. Sezon Seçici
                    CustomPopupSelector<String>(
                      label: 'Sezon',
                      selectedValue: _seasonId,
                      items: seasons.map((s) => s.id).toList(),
                      labelBuilder: (id) => seasons.firstWhere((s) => s.id == id, orElse: () => seasons.first).name,
                      onChanged: (val) {
                        setState(() {
                          _seasonId = val;
                          _groupId = null;
                          _week = null;
                        });
                        setDialogState(() {});
                        GlobalFilter.setSeason(val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // 3. Grup Seçici
                    if (groups.length > 1) ...[
                      CustomPopupSelector<String?>(
                        label: 'Grup',
                        selectedValue: _groupId,
                        items: [null, ...groups.map((g) => g.id)],
                        labelBuilder: (id) => id == null ? 'Tüm Gruplar' : (groupNameById[id] ?? ''),
                        onChanged: (val) {
                          setState(() {
                            _groupId = val;
                            _week = null;
                          });
                          setDialogState(() {});
                          GlobalFilter.setGroup(val);
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    // 4. Hafta Seçici
                    CustomPopupSelector<int>(
                      label: 'Hafta',
                      selectedValue: _week ?? currentWeek,
                      items: weeks,
                      labelBuilder: (w) => '$w. Hafta',
                      onChanged: (val) {
                        setState(() => _week = val);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 24),

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

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = AppSession.of(context).value.isAdmin;

    const bgDark = Color(0xFF0F172A);
    final cardBg = Colors.black.withOpacity(0.3);
    final outline = Colors.white.withOpacity(0.08);

    return Scaffold(
      backgroundColor: bgDark,
      extendBodyBehindAppBar: true,
      appBar: const MasterClassAppBar(title: 'Fikstür'),
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
            child: StreamBuilder<List<Team>>(
              stream: _teamsStream,
              builder: (context, teamsSnap) {
                final teamLogoById = <String, String>{};
                final teamNameById = <String, String>{};
                if (teamsSnap.hasData) {
                  for (final t in teamsSnap.data!) {
                    teamLogoById[t.id] = t.logoUrl;
                    teamNameById[t.id] = t.name;
                  }
                }

                return StreamBuilder<List<League>>(
                  stream: _leaguesStream,
                  builder: (context, leaguesSnap) {
                    if (!leaguesSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final leagues = [...(leaguesSnap.data ?? const <League>[])];

                    if (leagues.isEmpty) {
                      return const Center(
                        child: Text(
                          'Turnuva bulunamadı.',
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    }

                    if (_leagueId == null ||
                        !leagues.any((l) => l.id == _leagueId)) {
                      final newLeagueId = leagues.any((l) => l.isDefault)
                          ? (leagues.where((l) => l.isDefault).first.id)
                          : leagues.first.id;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          _leagueId = newLeagueId;
                          _seasonId = null;
                          _groupId = null;
                          _week = null;
                        });
                        GlobalFilter.setLeague(newLeagueId);
                      });
                      _leagueId = newLeagueId;
                    }

                    return StreamBuilder<List<Season>>(
                      stream: _leagueId == null
                          ? Stream.value([])
                          : _getSeasonsStream(_leagueId!),
                      builder: (context, seasonSnap) {
                        final seasons = seasonSnap.data ?? [];

                        if (_leagueId != null && seasons.isNotEmpty) {
                          final hasSelected =
                              _seasonId != null &&
                              seasons.any((s) => s.id == _seasonId);
                          if (!hasSelected) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                setState(() {
                                  _seasonId = seasons.first.id;
                                  _groupId = null;
                                  _week = null;
                                });
                                GlobalFilter.setSeason(seasons.first.id);
                              }
                            });
                          }
                        }

                        return StreamBuilder<List<GroupModel>>(
                          stream: _seasonId == null
                              ? const Stream<List<GroupModel>>.empty()
                              : _getGroupsStream(_seasonId!),
                          builder: (context, snapshot) {
                            final groupsRaw =
                                snapshot.data ?? const <GroupModel>[];
                            final groups = [...groupsRaw]
                              ..sort(
                                (a, b) => a.name.toLowerCase().compareTo(
                                  b.name.toLowerCase(),
                                ),
                              );

                            String groupDisplayName(GroupModel g, int index) {
                              final name = g.name.trim();
                              if (name.isNotEmpty) return name;
                              return 'Grup ${index + 1}';
                            }

                            final groupNameById = <String, String>{
                              for (final e in groups.indexed)
                                e.$2.id: groupDisplayName(e.$2, e.$1),
                            };

                            final selectedGroupId =
                                (_groupId != null &&
                                    groupNameById.containsKey(_groupId))
                                ? _groupId
                                : null;
                            final showGroupInHeader =
                                selectedGroupId == null || groups.length > 1;

                            return FutureBuilder<int?>(
                              key: ValueKey('$_seasonId|$selectedGroupId'),
                              future: _matchService.getFixtureMaxWeek(
                                _leagueId!,
                                groupId: selectedGroupId,
                              ),
                              builder: (context, maxWeekSnap) {
                                final maxWeek = maxWeekSnap.data ?? 30;

                                final safeMaxWeek = maxWeek > 0 ? maxWeek : 1;
                                final weeks = <int>[
                                  for (var i = 1; i <= safeMaxWeek; i++) i,
                                ];

                                final displayWeek = weeks.contains(_week)
                                    ? _week
                                    : weeks.first;

                                if (_week != displayWeek) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) {
                                      setState(() => _week = displayWeek);
                                    }
                                  });
                                }

                                return StreamBuilder<List<MatchModel>>(
                                  stream:
                                      displayWeek == null || _seasonId == null
                                      ? Stream.empty()
                                      : _matchService.watchFixtureMatches(
                                          _leagueId!,
                                          displayWeek,
                                          groupId: selectedGroupId,
                                        ),
                                  builder: (context, matchesSnap) {
                                    if (matchesSnap.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    }

                                    final matches = (matchesSnap.data ?? [])
                                      ..sort((a, b) {
                                        int dateComp = (a.matchDate ?? '')
                                            .compareTo(b.matchDate ?? '');
                                        if (dateComp != 0) return dateComp;
                                        return (a.matchTime ?? '').compareTo(
                                          b.matchTime ?? '',
                                        );
                                      });

                                    final currentLeagueName = leagues.firstWhere((l) => l.id == _leagueId, orElse: () => leagues.first).name;
                                    //final currentSeasonName = seasons.isEmpty ? '' : seasons.firstWhere((s) => s.id == _seasonId, orElse: () => seasons.first).name;
                                    final currentGroupName = selectedGroupId == null ? 'Tüm Gruplar' : (groupNameById[selectedGroupId] ?? '');

                                    return Column(
                                      children: [
                                        // YENİ FİLTRE KAPSÜLÜ
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                          child: InkWell(
                                            onTap: () {
                                              _showFilterDialog(
                                                context, 
                                                leagues, 
                                                seasons, 
                                                groups, 
                                                groupNameById, 
                                                weeks, 
                                                displayWeek ?? 1,
                                                selectedGroupId,
                                              );
                                            },
                                            borderRadius: BorderRadius.circular(24),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(0.4),
                                                borderRadius: BorderRadius.circular(24),
                                                border: Border.all(color: Colors.white24),
                                                boxShadow: const [
                                                  BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
                                                ],
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.tune_rounded, color: Color(0xFF10B981), size: 18),
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                    child: Text(
                                                      "$currentLeagueName • ${displayWeek ?? 1}. Hafta",
                                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
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
                                        ),

                                        // Liste Kısmı
                                        Expanded(
                                          child: Container(
                                            color: Colors.transparent,
                                            child: matches.isEmpty
                                                ? const Center(
                                                    child: Text(
                                                      'Maç bulunamadı.',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  )
                                                : _FixtureList(
                                                    matches: matches,
                                                    dateStripText:
                                                        _dateStripText,
                                                    groupNameById:
                                                        groupNameById,
                                                    showGroupInHeader:
                                                        showGroupInHeader,
                                                    teamLogoById: teamLogoById,
                                                    teamNameById: teamNameById,
                                                    isAdmin: isAdmin,
                                                    onMatchTap: (m) =>
                                                        Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (_) =>
                                                                MatchDetailsScreen(
                                                                  match: m,
                                                                ),
                                                          ),
                                                        ),
                                                    cardColor: cardBg,
                                                    outlineColor: outline,
                                                    onDataChanged: () =>
                                                        setState(() {}),
                                                  ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FixtureList extends StatelessWidget {
  const _FixtureList({
    required this.matches,
    required this.dateStripText,
    required this.groupNameById,
    required this.showGroupInHeader,
    required this.teamLogoById,
    required this.teamNameById,
    required this.onMatchTap,
    required this.cardColor,
    required this.outlineColor,
    required this.isAdmin,
    required this.onDataChanged,
  });

  final List<MatchModel> matches;
  final String Function(String yyyyMmDd) dateStripText;
  final Map<String, String> groupNameById;
  final bool showGroupInHeader;
  final Map<String, String> teamLogoById;
  final Map<String, String> teamNameById;
  final void Function(MatchModel match) onMatchTap;
  final Color cardColor;
  final Color outlineColor;
  final bool isAdmin;
  final VoidCallback onDataChanged;

  @override
  Widget build(BuildContext context) {
    String groupLabel(String groupId) {
      final name = groupNameById[groupId] ?? 'Grup';
      return name.toLowerCase().contains('grup') ? name : '$name Grubu';
    }

    final byDate = <String, List<MatchModel>>{};
    for (final m in matches) {
      final dateKey = (m.matchDate ?? '').trim().isEmpty
          ? '__NO_DATE__'
          : m.matchDate!.trim();
      (byDate[dateKey] ??= []).add(m);
    }

    final sortedDates = byDate.keys.toList()..sort();

    return ListView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        for (final dKey in sortedDates)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: outlineColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, top: 4),
                        child: Text(
                          dKey == '__NO_DATE__'
                              ? 'Tarih Belirlenmedi'
                              : dateStripText(dKey),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      const SizedBox(height: 12),
                      ..._buildGroupedSection(byDate[dKey]!, groupLabel),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

List<Widget> _buildGroupedSection(
    List<MatchModel> matchesInDate,
    String Function(String) groupLabel,
  ) {
    final groupedByGroup = <String, List<MatchModel>>{};
    for (var m in matchesInDate) {
      final gId = m.groupId ?? '';
      (groupedByGroup[gId] ??= []).add(m);
    }

    final sortedGroupIds = groupedByGroup.keys.toList()..sort();
    final List<Widget> items = [];

    for (var gId in sortedGroupIds) {
      if (showGroupInHeader && gId.isNotEmpty) {
        items.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              groupLabel(gId).toUpperCase(),
              style: TextStyle(
                color: Colors.amberAccent.withOpacity(0.8),
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 1.2,
              ),
            ),
          ),
        );
      }

      final groupMatches = groupedByGroup[gId]!;
      for (int i = 0; i < groupMatches.length; i++) {
        final m = groupMatches[i];
        items.add(
          _MatchCard(
            match: m,
            teamLogoById: teamLogoById,
            teamNameById: teamNameById,
            isAdmin: isAdmin,
            onTap: () => onMatchTap(m),
            onDataChanged: onDataChanged,
          ),
        );

        // Maçlar arasına ince çizgi ekleme (gruptaki son maç hariç)
        if (i < groupMatches.length - 1) {
          items.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: Colors.white.withOpacity(0.08), height: 1),
            ),
          );
        }
      }
    }
    return items;
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.teamLogoById,
    required this.teamNameById,
    required this.onTap,
    required this.isAdmin,
    required this.onDataChanged,
  });

  static final IMatchService _matchService = ServiceLocator.matchService;
  static final ILeagueService _leagueService = ServiceLocator.leagueService;

  final MatchModel match;
  final Map<String, String> teamLogoById;
  final Map<String, String> teamNameById;
  final VoidCallback onTap;
  final bool isAdmin;
  final VoidCallback onDataChanged;

  Widget _logo(String url) {
    return SizedBox(
      width: 28,
      height: 28,
      child: WebSafeImage(
        url: url,
        width: 28,
        height: 28,
        isCircle: true,
        fallbackIconSize: 18,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFinished = match.status == MatchStatus.finished;
    final timeTextRaw = (match.matchTime ?? '').trim();
    final timeText = timeTextRaw.length >= 5
        ? timeTextRaw.substring(0, 5)
        : timeTextRaw;
    final leftText = isFinished
        ? 'MS'
        : (timeText.isEmpty ? '--:--' : timeText);

    const mid = Color(0xFF94A3B8);
    const accent = Color(0xFF10B981);

    final homeLogo = (teamLogoById[match.homeTeamId] ?? '').trim();
    final awayLogo = (teamLogoById[match.awayTeamId] ?? '').trim();
    final homeName = (teamNameById[match.homeTeamId] ?? '').trim();
    final awayName = (teamNameById[match.awayTeamId] ?? '').trim();

    final hs = match.homeScore;
    final as = match.awayScore;
    final showScore = isFinished || hs != 0 || as != 0;

    return Card(
      margin: EdgeInsets.zero,
      color: Colors.transparent,
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: () {
          if (!isAdmin) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bu işlem için yetkiniz bulunmamaktadır.'),
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }
          _showQuickScoreDialog(context);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 50,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isAdmin)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(
                          Icons.edit_calendar,
                          size: 22,
                          color: Colors.white,
                        ),
                        onPressed: () => _showEditPopup(context),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      leftText,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: isFinished ? accent : mid,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _teamRow(
                      homeName.isEmpty ? 'Ev Sahibi' : homeName,
                      homeLogo,
                      hs,
                      showScore,
                      hs >= as,
                    ),
                    const SizedBox(height: 12),
                    _teamRow(
                      awayName.isEmpty ? 'Deplasman' : awayName,
                      awayLogo,
                      as,
                      showScore,
                      as >= hs,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _teamRow(
    String name,
    String logo,
    int score,
    bool showScore,
    bool highlight,
  ) {
    return Row(
      children: [
        _logo(logo),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: highlight ? Colors.white : Colors.white70,
              fontSize: 13,
            ),
          ),
        ),
        SizedBox(
          width: 25,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              showScore ? '$score' : '-',
              style: TextStyle(
                color: highlight ? Colors.white : Colors.white38,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showQuickScoreDialog(BuildContext context) {
    final homeName = (teamNameById[match.homeTeamId] ?? '').trim();
    final awayName = (teamNameById[match.awayTeamId] ?? '').trim();
    final homeScoreCtrl = TextEditingController(
      text: match.homeScore.toString(),
    );
    final awayScoreCtrl = TextEditingController(
      text: match.awayScore.toString(),
    );

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        title: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: const BoxDecoration(
            color: Color(0xFF064E3B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: const Text(
            'Hızlı Skor Girişi',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${homeName.isEmpty ? 'Ev Sahibi' : homeName} - ${awayName.isEmpty ? 'Deplasman' : awayName}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: homeScoreCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color(0xFF10B981),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  '-',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: awayScoreCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color(0xFF10B981),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('İptal', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              final homeScore = int.tryParse(homeScoreCtrl.text) ?? 0;
              final awayScore = int.tryParse(awayScoreCtrl.text) ?? 0;

              await _matchService.completeMatchWithScoreAndDefaultEvents(
                matchId: match.id,
                homeScore: homeScore,
                awayScore: awayScore,
              );

              if (c.mounted) {
                Navigator.pop(c);
                onDataChanged();
              }
            },
            child: const Text(
              'KAYDET',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditPopup(BuildContext context) async {
    String initialDate = '';
    if (match.matchDate != null && match.matchDate!.contains('-')) {
      final p = match.matchDate!.split('-');
      if (p.length == 3) initialDate = '${p[2]}/${p[1]}/${p[0]}';
    } else {
      initialDate = match.matchDate ?? '';
    }

    final dCtrl = TextEditingController(text: initialDate);
    final rawInitialTime = (match.matchTime ?? '').trim();
    final initialTimeText = rawInitialTime.length >= 5
        ? rawInitialTime.substring(0, 5)
        : rawInitialTime;
    final tCtrl = TextEditingController(text: initialTimeText);
    final dateFocus = FocusNode();
    final timeFocus = FocusNode();

    String? selectedPitchId = (match.pitchId ?? '').trim().isEmpty
        ? null
        : match.pitchId!.trim();
    String? selectedPitchName = (match.pitchName ?? '').trim().isEmpty
        ? null
        : match.pitchName!.trim();

    final pitches = await _leagueService.watchPitches().first;

    if (pitches.length == 1) {
      selectedPitchId = pitches.first.id;
      selectedPitchName = pitches.first.name.trim().isEmpty
          ? null
          : pitches.first.name.trim();
    }

    dCtrl.addListener(() {
      if (dCtrl.text.length == 10) {
        timeFocus.requestFocus();
      }
    });

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text(
            'Maçı Düzenle',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: dCtrl,
                  focusNode: dateFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_DateInputFormatter()],
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Tarih (GG/AA/YYYY)',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                TextField(
                  controller: tCtrl,
                  focusNode: timeFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_TimeInputFormatter()],
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Saat (SS:DD)',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                DropdownButtonFormField<String?>(
                  initialValue: pitches.any((p) => p.id == selectedPitchId)
                      ? selectedPitchId
                      : null,
                  dropdownColor: const Color(0xFF0F172A),
                  decoration: const InputDecoration(
                    labelText: 'Stad Seçin',
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'Stad Seçilmedi',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    for (final p in pitches)
                      DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text(
                          p.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                  ],
                  onChanged: (val) {
                    final selected = pitches
                        .where((e) => e.id == val)
                        .toList(growable: false);
                    final name = selected.isEmpty
                        ? ''
                        : selected.first.name.trim();
                    setDialogState(() {
                      selectedPitchId = val;
                      selectedPitchName = val == null || name.isEmpty
                          ? null
                          : name;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text(
                'İptal',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
              ),
              onPressed: () async {
                final dateText = dCtrl.text;
                final timeText = tCtrl.text;

                final dateMatch = RegExp(
                  r'^(\d{2})[\/\-](\d{2})[\/\-](\d{4})$',
                ).firstMatch(dateText);
                if (dateMatch == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tarih formatı hatalı! (GG/AA/YYYY)'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }
                final timeMatch = RegExp(
                  r'^(\d{2}):(\d{2})$',
                ).firstMatch(timeText);
                if (timeMatch == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Saat formatı hatalı! (SS:DD)'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }

                final dd = dateMatch.group(1)!;
                final mm = dateMatch.group(2)!;
                final yyyy = dateMatch.group(3)!;
                final dbDate = '$yyyy-$mm-$dd';

                try {
                  await _matchService.updateMatchSchedule(
                    matchId: match.id,
                    matchDateDb: dbDate,
                    matchTime: timeText,
                    pitchId: selectedPitchId,
                    pitchName: selectedPitchName,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Maç güncellendi.'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 2),
                      ),
                    );
                    dateFocus.dispose();
                    timeFocus.dispose();
                    dCtrl.dispose();
                    tCtrl.dispose();
                    Navigator.pop(c);
                    onDataChanged();
                  }
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Güncelleme başarısız: $e'),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
              child: const Text(
                'GÜNCELLE',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    if (newValue.text.length < oldValue.text.length) return newValue;
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length > 8) digitsOnly = digitsOnly.substring(0, 8);
    String formatted = '';
    for (int i = 0; i < digitsOnly.length; i++) {
      formatted += digitsOnly[i];
      if (i == 1 || i == 3) formatted += '/';
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _TimeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length < oldValue.text.length) return newValue;
    String cleanText = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanText.length > 4) cleanText = cleanText.substring(0, 4);
    StringBuffer buffer = StringBuffer();
    for (int i = 0; i < cleanText.length; i++) {
      buffer.write(cleanText[i]);
      if (i == 1) buffer.write(':');
    }
    String finalString = buffer.toString();
    return TextEditingValue(
      text: finalString,
      selection: TextSelection.collapsed(offset: finalString.length),
    );
  }
}