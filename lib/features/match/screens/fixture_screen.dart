import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:football_tournament/core/widgets/master_class_app_bar.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/resilient_stream.dart';
import '../../../core/utils/table_feed.dart';
import '../../tournament/models/league.dart';
import '../../tournament/models/season.dart';
import '../models/match.dart';
import '../../team/models/team.dart';
import '../../../core/services/app_session.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../services/interfaces/i_match_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/services/global_filter.dart';
import '../../../core/services/active_tournament.dart';
import 'match_details_screen.dart';
import '../utils/match_clock.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/widgets/admin_form.dart';
import '../../share/fixture_poster.dart';
import '../../share/poster_share.dart';
import '../../../core/utils/team_name.dart';

// ORTAK BİLEŞEN IMPORT EDİLDİ
import '../../../core/widgets/tournament_filter_dialog.dart';
import '../../../core/widgets/app_date_picker.dart';
import '../../../core/utils/string_utils.dart';
import '../../../core/widgets/league_filter_header.dart';

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

  /// [_week] hangi turnuva|sezon|grup için seçildi; grup (bölge) değişince
  /// o grubun güncel haftası açılır.
  String? _weekKey;

  /// Başlık çubuğundaki paylaş düğmesinin işlevi (yetki ve veri varsa).
  final _shareAction = ValueNotifier<VoidCallback?>(null);

  /// Filtre (turnuva|sezon|grup) başına hafta bilgisi önbelleği.
  final Map<String, Future<({int? maxWeek, int? nextWeek})>> _weekInfo = {};

  /// En büyük hafta ve varsayılan (güncel) hafta: en son oynanan haftadan
  /// itibaren oynanmamış maçı olan ilk hafta (o haftanın kalan maçları
  /// sürüyorsa aynı hafta); hepsi oynandıysa son oynanan hafta. Ertelenmiş
  /// eski maçlar (ör. 5. hafta oynanırken bekleyen 3. hafta maçı) seçimi
  /// geriye çekmez.
  Future<({int? maxWeek, int? nextWeek})> _loadWeekInfo(
    String leagueId,
    String? seasonId,
    String? groupId,
  ) async {
    // Son hafta seçili sezon/grubun (bölgenin) kendi maçlarından: bölgelerin
    // hafta sayısı farklı olabilir; olmayan hafta listede görünmez.
    int? maxWeek;
    int? nextWeek;
    try {
      var q = Supabase.instance.client
          .from('matches')
          .select('week, status')
          .eq('league_id', leagueId);
      if (seasonId != null) q = q.eq('season_id', seasonId);
      if (groupId != null) q = q.eq('group_id', groupId);
      final rows = await q;

      int? lastPlayed;
      int? firstAny;
      final unplayed = <int>[];
      for (final r in rows) {
        final w = r['week'];
        final week = w is num ? w.toInt() : int.tryParse('${w ?? ''}');
        if (week == null) continue;
        if (firstAny == null || week < firstAny) firstAny = week;
        if (maxWeek == null || week > maxWeek) maxWeek = week;
        final status = (r['status'] ?? '').toString().trim();
        if (status == MatchStatus.finished.name) {
          if (lastPlayed == null || week > lastPlayed) lastPlayed = week;
        } else if (status != MatchStatus.cancelled.name) {
          unplayed.add(week);
        }
      }
      final pending = unplayed
          .where((w) => lastPlayed == null || w >= lastPlayed)
          .toList();
      nextWeek = pending.isNotEmpty
          ? pending.reduce((a, b) => a < b ? a : b)
          : (lastPlayed ?? firstAny);
    } catch (_) {}
    return (maxWeek: maxWeek, nextWeek: nextWeek);
  }

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
      // Dışarıdan gelen seçim (ör. canlı kura sonucu) yeni maçlar getirmiş
      // olabilir; hafta bilgisi yeniden okunur.
      _weekInfo.clear();
    });
  }

  @override
  void dispose() {
    GlobalFilter.leagueId.removeListener(_onGlobalFilterChanged);
    GlobalFilter.seasonId.removeListener(_onGlobalFilterChanged);
    GlobalFilter.groupId.removeListener(_onGlobalFilterChanged);
    _shareAction.dispose();
    super.dispose();
  }

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

  // Fikstür maç akışı: yalnızca turnuva/sezon/grup/hafta değişince yeniden
  // kurulur (önceden her yeniden çizimde tekrar sorgulanıyordu).
  Stream<List<MatchModel>>? _fixtureMatchesStream;
  String? _fixtureMatchesKey;

  Stream<List<MatchModel>> _fixtureStream(
    String leagueId,
    String seasonId,
    String? groupId,
    int week,
  ) {
    final key = '$leagueId|$seasonId|${groupId ?? ''}|$week';
    if (_fixtureMatchesStream == null || _fixtureMatchesKey != key) {
      _fixtureMatchesKey = key;
      _fixtureMatchesStream = resilientStream(
        () => _matchService.watchFixtureMatches(
          leagueId,
          week,
          groupId: groupId,
          seasonId: seasonId,
        ),
      );
    }
    return _fixtureMatchesStream!;
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

  /// Seçili turnuva / grup / haftanın maçlarıyla fikstür afişi hazırlar.
  Future<void> _shareFixturePoster({
    required League league,
    required String groupName,
    required int week,
    required List<MatchModel> matches,
    required Map<String, String> teamNameById,
    required Map<String, String> teamLogoById,
  }) async {
    final pitchNameById = <String, String>{};
    try {
      for (final p in await _leagueService.watchPitches().first) {
        pitchNameById[p.id] = p.name.trim();
      }
    } catch (_) {
      // Saha adları gelmezse afiş sahasız hazırlanır.
    }
    if (!mounted) return;

    String dateText(String? ymd) {
      final d = DateTime.tryParse((ymd ?? '').trim());
      return d == null
          ? 'Tarih belirsiz'
          : DateFormat('dd.MM.yyyy EEEE', 'tr_TR').format(d);
    }

    // Gün + saha bazında gruplanır (sıralı maç listesi korunur).
    final days = <String, List<MatchModel>>{};
    for (final m in matches) {
      (days['${m.matchDate ?? ''}|${m.pitchId ?? ''}'] ??= []).add(m);
    }
    PosterMatch toPoster(MatchModel m) {
      final t = (m.matchTime ?? '').trim();
      final played = m.status == MatchStatus.finished;
      return PosterMatch(
        homeName: shortTeamName(teamNameById[m.homeTeamId] ?? 'Ev Sahibi'),
        awayName: shortTeamName(teamNameById[m.awayTeamId] ?? 'Deplasman'),
        homeLogo: (teamLogoById[m.homeTeamId] ?? '').trim(),
        awayLogo: (teamLogoById[m.awayTeamId] ?? '').trim(),
        time: t.isEmpty
            ? '--.--'
            : (t.length >= 5 ? t.substring(0, 5) : t).replaceAll(':', '.'),
        score: played ? '${m.homeScore} - ${m.awayScore}' : null,
      );
    }

    final posterDays = [
      for (final e in days.entries)
        PosterDay(
          dateText: dateText(e.value.first.matchDate),
          pitchText: pitchNameById[e.value.first.pitchId ?? ''] ?? '',
          matches: [for (final m in e.value) toPoster(m)],
        ),
    ];
    final logos = <String>{
      league.logoUrl,
      for (final d in posterDays)
        for (final m in d.matches) ...[m.homeLogo, m.awayLogo],
    }.where((u) => u.isNotEmpty).toList();

    await showPosterPreview(
      context: context,
      fileName: 'fikstur_${week}_hafta',
      imageUrls: logos,
      leagueId: league.id,
      poster: FixturePoster(
        leagueName: league.name,
        leagueLogo: league.logoUrl,
        subtitle: groupName.isEmpty ? 'Fikstür' : '$groupName Fikstür',
        weekText: '$week. Hafta',
        days: posterDays,
      ),
    );
  }

  // ORTADA AÇILAN FİKSTÜR FİLTRE DİALOGU; seçimler yalnızca "Filtreleri
  // Uygula" ile ekrana yansır.
  Future<void> _showFilterDialog(
    BuildContext context,
    List<League> leagues,
    int currentWeek,
    String? currentGroupId,
  ) async {
    final result = await showTournamentFilterDialog(
      context: context,
      leagues: leagues,
      initial: TournamentFilter(
        leagueId: _leagueId,
        seasonId: _seasonId,
        groupId: currentGroupId,
        week: currentWeek,
      ),
      watchSeasons: _watchSeasons,
      watchGroups: _leagueService.watchGroups,
      loadWeekInfo: (leagueId, seasonId, groupId) => _weekInfo.putIfAbsent(
        '$leagueId|$seasonId|$groupId',
        () => _loadWeekInfo(leagueId, seasonId, groupId),
      ),
    );
    if (result == null || !mounted) return;
    GlobalFilter.setLeague(result.leagueId);
    ActiveTournament.noteViewed(result.leagueId);
    GlobalFilter.setSeason(result.seasonId);
    GlobalFilter.setGroup(result.groupId);
    setState(() {
      _leagueId = result.leagueId;
      _seasonId = result.seasonId;
      _groupId = result.groupId;
      _week = result.week;
      _weekKey = '${result.leagueId}|${result.seasonId}|${result.groupId}';
    });
  }

  /// Fikstür üst kısmı: gerekirse sezon/grup kapsülü (dokununca filtre) ve
  /// hafta şeridi.
  Widget _buildFixtureHeader({
    required BuildContext context,
    required List<League> leagues,
    required List<Season> seasons,
    required List<int> weeks,
    required int week,
    required List<GroupModel> groups,
    required Map<String, String> groupNameById,
    required String? selectedGroupId,
    required String currentGroupName,
    required List<MatchModel> matches,
    required Map<String, String> teamNameById,
    required Map<String, String> teamLogoById,
  }) {
    final league = leagues.firstWhere(
      (l) => l.id == _leagueId,
      orElse: () => leagues.first,
    );
    final seasonName = seasons
        .where((s) => s.id == _seasonId)
        .map((s) => s.name)
        .firstOrNull;
    final canShare =
        matches.isNotEmpty &&
        AppSession.of(context).value.canManageLeague(_leagueId);

    // Paylaş düğmesi başlık çubuğunda (sağda); seçili haftanın afişi.
    final VoidCallback? share = !canShare
        ? null
        : () => _shareFixturePoster(
            league: league,
            groupName: groups.length > 1 ? currentGroupName : '',
            week: week,
            matches: matches,
            teamNameById: teamNameById,
            teamLogoById: teamLogoById,
          );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _shareAction.value = share;
    });
    // Turnuva üst bantta duruyor; sezon/grup filtresi yalnızca seçilecek
    // birden fazla sezon ya da grup varsa görünür.
    final hasFilter = seasons.length > 1 || groups.length > 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasFilter) ...[
            LeagueFilterCapsule(
              seasonName: seasonName,
              detail: groups.length > 1 ? currentGroupName : null,
              onTap: () =>
                  _showFilterDialog(context, leagues, week, selectedGroupId),
            ),
            const SizedBox(height: 8),
          ],
          _WeekStrip(
            weeks: weeks,
            week: week,
            onSelect: (w) => setState(() => _week = w),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = AppSession.of(context).value.isAdmin;

    const bgDark = Color(0xFF0F172A);
    final cardBg = Colors.black.withValues(alpha: 0.3);
    final outline = Colors.white.withValues(alpha: 0.08);

    return Scaffold(
      backgroundColor: bgDark,
      extendBodyBehindAppBar: true,
      appBar: MasterClassAppBar(
        title: 'Fikstür',
        actions: [
          ValueListenableBuilder<VoidCallback?>(
            valueListenable: _shareAction,
            builder: (context, share, _) => share == null
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Afişi paylaş',
                    onPressed: share,
                    icon: const Icon(
                      Icons.ios_share_rounded,
                      color: Colors.white70,
                    ),
                  ),
          ),
        ],
      ),
      body: Stack(
        children: [
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
                        // Turnuva değişince yeni sezonlar gelene kadar eski
                        // turnuvanınkiler tutulur; onlarla seçim yapılmasın.
                        if (seasonSnap.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final seasons = seasonSnap.data ?? [];

                        if (_leagueId != null && seasons.isNotEmpty) {
                          final hasSelected =
                              _seasonId != null &&
                              seasons.any((s) => s.id == _seasonId);
                          if (!hasSelected) {
                            final def = pickDefaultSeasonId(seasons);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                setState(() {
                                  _seasonId = def;
                                  _groupId = null;
                                  _week = null;
                                });
                                GlobalFilter.setSeason(def);
                              }
                            });
                          }
                        }

                        return StreamBuilder<List<GroupModel>>(
                          stream: _seasonId == null
                              ? const Stream<List<GroupModel>>.empty()
                              : _getGroupsStream(_seasonId!),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
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

                            // "Tümü" yok: seçili grup yoksa ilk grup.
                            final selectedGroupId =
                                (_groupId != null &&
                                    groupNameById.containsKey(_groupId))
                                ? _groupId
                                : (groups.isEmpty ? null : groups.first.id);
                            // Tek grup gösterilir; grup adı sekmede.
                            const showGroupInHeader = false;

                            final weekKey =
                                '$_leagueId|$_seasonId|$selectedGroupId';
                            return FutureBuilder<
                              ({int? maxWeek, int? nextWeek})
                            >(
                              key: ValueKey(weekKey),
                              future: _weekInfo.putIfAbsent(
                                weekKey,
                                () => _loadWeekInfo(
                                  _leagueId!,
                                  _seasonId,
                                  selectedGroupId,
                                ),
                              ),
                              builder: (context, weekSnap) {
                                // Bilgi gelmeden hafta seçilmez; aksi halde
                                // geçici olarak 1. hafta seçilip kalıcı oluyordu.
                                if (!weekSnap.hasData) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }
                                final info = weekSnap.data!;
                                final maxWeek = info.maxWeek ?? 1;

                                final safeMaxWeek = maxWeek > 0 ? maxWeek : 1;
                                final weeks = <int>[
                                  for (var i = 1; i <= safeMaxWeek; i++) i,
                                ];

                                // Kullanıcı hafta seçmediyse: oynanmamış ilk
                                // maçın haftası.
                                final defaultWeek =
                                    weeks.contains(info.nextWeek)
                                    ? info.nextWeek
                                    : weeks.first;
                                final userWeek = _weekKey == weekKey
                                    ? _week
                                    : null;
                                final displayWeek = weeks.contains(userWeek)
                                    ? userWeek
                                    : defaultWeek;

                                if (_week != displayWeek ||
                                    _weekKey != weekKey) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) {
                                      setState(() {
                                        _week = displayWeek;
                                        _weekKey = weekKey;
                                      });
                                    }
                                  });
                                }

                                return StreamBuilder<List<MatchModel>>(
                                  stream:
                                      displayWeek == null || _seasonId == null
                                      ? Stream.empty()
                                      : _fixtureStream(
                                          _leagueId!,
                                          _seasonId!,
                                          selectedGroupId,
                                          displayWeek,
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
                                    //final currentSeasonName = seasons.isEmpty ? '' : seasons.firstWhere((s) => s.id == _seasonId, orElse: () => seasons.first).name;
                                    final currentGroupName =
                                        selectedGroupId == null
                                        ? 'Tüm Gruplar'
                                        : (groupNameById[selectedGroupId] ??
                                              '');

                                    final header = _buildFixtureHeader(
                                      context: context,
                                      leagues: leagues,
                                      seasons: seasons,
                                      weeks: weeks,
                                      week: displayWeek ?? 1,
                                      groups: groups,
                                      groupNameById: groupNameById,
                                      selectedGroupId: selectedGroupId,
                                      currentGroupName: currentGroupName,
                                      matches: matches,
                                      teamNameById: teamNameById,
                                      teamLogoById: teamLogoById,
                                    );
                                    // Başlık listeyle birlikte kayar; aşağı
                                    // kaydırınca ekranın tamamı maçlara kalır.
                                    return _FixtureList(
                                      header: header,
                                      matches: matches,
                                      dateStripText: _dateStripText,
                                      groupNameById: groupNameById,
                                      showGroupInHeader: showGroupInHeader,
                                      teamLogoById: teamLogoById,
                                      teamNameById: teamNameById,
                                      isAdmin: isAdmin,
                                      onMatchTap: (m) => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              MatchDetailsScreen(match: m),
                                        ),
                                      ),
                                      cardColor: cardBg,
                                      outlineColor: outline,
                                      // Akış önbellekli; kayıttan sonra
                                      // hafta listesi yeniden okunsun.
                                      onDataChanged: () => setState(
                                        () => _fixtureMatchesStream = null,
                                      ),
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
    required this.header,
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

  final Widget header;
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

    String dayLabel(String key) {
      if (key == '__NO_DATE__') return 'Tarih Belirlenmedi';
      final dt = DateTime.tryParse(key);
      if (dt == null) return key;
      // Ör. "04 Ekim Pazar"
      return DateFormat('dd MMMM EEEE', 'tr_TR').format(dt);
    }

    return ListView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
      children: [
        header,
        if (matches.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(
              child: Text(
                'Maç bulunamadı.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        for (final dKey in sortedDates) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(70, 12, 16, 6),
            child: Text(
              dayLabel(dKey),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                letterSpacing: 0.3,
              ),
            ),
          ),
          ..._buildGroupedSection(byDate[dKey]!, groupLabel),
        ],
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
            padding: const EdgeInsets.fromLTRB(70, 2, 16, 6),
            child: Text(
              groupLabel(gId).trUpper,
              style: TextStyle(
                color: Colors.amberAccent.withValues(alpha: 0.8),
                fontWeight: FontWeight.w800,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
            child: _MatchCard(
              match: m,
              teamLogoById: teamLogoById,
              teamNameById: teamNameById,
              isAdmin: isAdmin,
              onTap: () => onMatchTap(m),
              onDataChanged: onDataChanged,
            ),
          ),
        );
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

  @override
  Widget build(BuildContext context) {
    final homeName = (teamNameById[match.homeTeamId] ?? '').trim();
    final awayName = (teamNameById[match.awayTeamId] ?? '').trim();

    return MatchClockBuilder(
      match: match,
      builder: (context, liveMinute) => _timelineItem(
        context,
        homeName.isEmpty ? 'Ev Sahibi' : homeName,
        awayName.isEmpty ? 'Deplasman' : awayName,
        liveMinute,
      ),
    );
  }

  void _onLongPress(BuildContext context) {
    if (!isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu işlem için yetkiniz bulunmamaktadır.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    _showMatchActions(context);
  }

  /// Yönetici menüsü: hızlı skor, ertele, iptal et, yeniden oynanacak yap.
  Future<void> _showMatchActions(BuildContext context) async {
    final unplayed =
        match.status == MatchStatus.postponed ||
        match.status == MatchStatus.cancelled;
    final actions = <(String, String)>[
      ('score', 'Hızlı Skor Girişi'),
      ('postpone', 'Ertelendi (ERT)'),
      if (match.status != MatchStatus.cancelled) ('cancel', 'İptal Edildi (İPT)'),
      if (unplayed) ('restore', 'Oynanacak (Erteleme/İptali Kaldır)'),
    ];
    final picked = await showAdminOptionPicker<(String, String)>(
      context: context,
      title: 'Maç İşlemleri',
      items: actions,
      labelBuilder: (a) => a.$2,
      emptyText: 'İşlem yok.',
    );
    if (picked == null || !context.mounted) return;
    switch (picked.$1) {
      case 'score':
        _showQuickScoreDialog(context);
      case 'postpone':
        await _postpone(context);
      case 'cancel':
        await _setStatus(
          context,
          MatchStatus.cancelled,
          confirm:
              'Maç iptal edilsin mi? Oynanmamış sayılır; puan durumuna ve '
              'istatistiğe yansımaz.',
        );
      case 'restore':
        await _setStatus(context, MatchStatus.notStarted);
    }
  }

  /// Erteleme: yeni tarih (isteğe bağlı saat) sorulur; tarih seçilmezse
  /// maç tarihsiz ertelenmiş kalır.
  Future<void> _postpone(BuildContext context) async {
    final current = DateTime.tryParse((match.matchDate ?? '').trim());
    final date = await showAppDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      title: 'Ertelenen Tarih',
    );
    if (!context.mounted) return;
    TimeOfDay? time;
    if (date != null) {
      final raw = (match.matchTime ?? '').trim();
      final parts = raw.split(':');
      time = await showTimePicker(
        context: context,
        helpText: 'Maç Saati',
        initialTime: parts.length >= 2
            ? TimeOfDay(
                hour: int.tryParse(parts[0]) ?? 20,
                minute: int.tryParse(parts[1]) ?? 0,
              )
            : const TimeOfDay(hour: 20, minute: 0),
      );
      if (!context.mounted) return;
    }
    String two(int v) => v.toString().padLeft(2, '0');
    await _setStatus(
      context,
      MatchStatus.postponed,
      matchDate: date == null
          ? null
          : '${date.year}-${two(date.month)}-${two(date.day)}',
      matchTime: time == null ? null : '${two(time.hour)}:${two(time.minute)}',
    );
  }

  Future<void> _setStatus(
    BuildContext context,
    MatchStatus status, {
    String? confirm,
    String? matchDate,
    String? matchTime,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    if (confirm != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(confirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Evet'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await ServiceLocator.matchService.setMatchSchedulingStatus(
        matchId: match.id,
        status: status,
        matchDate: matchDate,
        matchTime: matchTime,
      );
      onDataChanged();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  // Zaman çizelgesi satırı: solda saat/durum, ortada çizgi ve nokta, sağda
  // iki takımlı kart. Kazanan beyaz ve kalın, kaybeden soluk.
  Widget _timelineItem(
    BuildContext context,
    String homeName,
    String awayName,
    String? liveMinute,
  ) {
    const mid = Color(0xFF94A3B8);
    const accent = Color(0xFF10B981);
    const live = Color(0xFFF87171);

    final rawTime = (match.matchTime ?? '').trim();
    final time = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
    final isLive =
        match.status == MatchStatus.live ||
        match.status == MatchStatus.halftime;
    final ({String text, Color color})? status = switch (match.status) {
      MatchStatus.notStarted => null,
      MatchStatus.finished => (text: 'MS', color: accent),
      MatchStatus.halftime => (text: 'İY', color: live),
      MatchStatus.live => (text: liveMinute ?? 'CANLI', color: live),
      MatchStatus.cancelled => (text: 'İPT', color: Colors.white54),
      MatchStatus.postponed => (text: 'ERT', color: Colors.white54),
    };
    final dotColor = isLive
        ? live
        : (match.status == MatchStatus.finished ? accent : Colors.white38);

    final hs = match.homeScore;
    final as = match.awayScore;
    // Ertelenen / iptal maçta skor yerine ERT / İPT yazar.
    final unplayed =
        match.status == MatchStatus.postponed ||
        match.status == MatchStatus.cancelled;
    final showScore =
        !unplayed &&
        (match.status == MatchStatus.finished || isLive || hs != 0 || as != 0);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    time.isEmpty ? '--:--' : time,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        status.text,
                        style: TextStyle(
                          color: status.color,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  if (isAdmin)
                    IconButton(
                      padding: const EdgeInsets.only(top: 6),
                      constraints: const BoxConstraints(),
                      tooltip: 'Tarih / saat düzenle',
                      icon: const Icon(
                        Icons.edit_calendar,
                        size: 18,
                        color: mid,
                      ),
                      onPressed: () => _showEditPopup(context),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 22,
            child: Stack(
              children: [
                Positioned(
                  left: 10,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                Positioned(
                  left: 6,
                  top: 12,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0F172A),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: const Color(0xFF152036).withValues(alpha: 0.9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: isLive
                        ? live.withValues(alpha: 0.45)
                        : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onTap,
                  onLongPress: () => _onLongPress(context),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _teamLine(
                          homeName,
                          (teamLogoById[match.homeTeamId] ?? '').trim(),
                          showScore ? '$hs' : '-',
                          !showScore || hs >= as,
                          isLive,
                        ),
                        const SizedBox(height: 4),
                        _teamLine(
                          awayName,
                          (teamLogoById[match.awayTeamId] ?? '').trim(),
                          showScore ? '$as' : '-',
                          !showScore || as >= hs,
                          isLive,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamLine(
    String name,
    String logo,
    String score,
    bool strong,
    bool isLive,
  ) {
    return Row(
      children: [
        WebSafeImage(
          url: logo,
          width: 22,
          height: 22,
          fit: BoxFit.contain,
          fallbackIconSize: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            compactTeamName(name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: strong ? Colors.white : const Color(0xFF94A3B8),
              fontSize: 13,
            ),
          ),
        ),
        // Uzun ad kesilse bile "…" skora yapışmasın.
        const SizedBox(width: 12),
        // Skor kutusu: yeşil kare; canlı maçta kırmızı.
        Container(
          width: 30,
          height: 25,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isLive
                ? const Color(0xFFF87171).withValues(alpha: 0.22)
                : const Color(0xFF064E3B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  (isLive ? const Color(0xFFF87171) : const Color(0xFF10B981))
                      .withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            score,
            style: TextStyle(
              color: isLive
                  ? const Color(0xFFF87171)
                  : (strong ? Colors.white : Colors.white60),
              fontWeight: FontWeight.w800,
              fontSize: 14,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  void _showQuickScoreDialog(BuildContext context) async {
    const accent = Color(0xFF10B981);
    final homeName = (teamNameById[match.homeTeamId] ?? '').trim();
    final awayName = (teamNameById[match.awayTeamId] ?? '').trim();
    final homeScoreCtrl = TextEditingController(
      text: match.homeScore.toString(),
    );
    final awayScoreCtrl = TextEditingController(
      text: match.awayScore.toString(),
    );
    var saving = false;

    Widget scoreBox(String teamName, TextEditingController ctrl) {
      return Expanded(
        child: Column(
          children: [
            Text(
              teamName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.4),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: accent, width: 2),
                ),
              ),
            ),
          ],
        ),
      );
    }

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) {
          Future<void> save() async {
            setDialogState(() => saving = true);
            try {
              await _matchService.completeMatchWithScoreAndDefaultEvents(
                matchId: match.id,
                homeScore: int.tryParse(homeScoreCtrl.text) ?? 0,
                awayScore: int.tryParse(awayScoreCtrl.text) ?? 0,
              );
              if (!c.mounted) return;
              Navigator.pop(c);
              onDataChanged();
            } catch (e) {
              if (!c.mounted) return;
              setDialogState(() => saving = false);
              ScaffoldMessenger.of(c).showSnackBar(
                SnackBar(
                  content: Text('Hata: $e'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
            child: AdminDialogCloseOverlay(
              onClose: saving ? null : () => Navigator.pop(c),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E293B), Color(0xFF064E3B)],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 15,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.scoreboard_outlined,
                            color: accent,
                            size: 22,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Hızlı Skor Girişi',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white24, height: 1),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          scoreBox(
                            homeName.isEmpty ? 'Ev Sahibi' : homeName,
                            homeScoreCtrl,
                          ),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(12, 0, 12, 18),
                            child: Text(
                              '-',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          scoreBox(
                            awayName.isEmpty ? 'Deplasman' : awayName,
                            awayScoreCtrl,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Kaydedildiğinde maç "Bitti" olarak işaretlenir.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            disabledBackgroundColor: accent.withValues(
                              alpha: 0.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: saving ? null : save,
                          child: saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'KAYDET',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    // Dialog kapanış animasyonu bitene kadar TextField'lar controller'ı
    // kullanmaya devam eder; hemen dispose etmek hata verir.
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      homeScoreCtrl.dispose();
      awayScoreCtrl.dispose();
    });
  }

  void _showEditPopup(BuildContext context) async {
    const accent = Color(0xFF10B981);
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

    final pitches = [...await _leagueService.watchPitches().first]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (pitches.length == 1) {
      selectedPitchId = pitches.first.id;
      selectedPitchName = pitches.first.name.trim().isEmpty
          ? null
          : pitches.first.name.trim();
    }
    if (selectedPitchId != null) {
      final m = pitches.where((p) => p.id == selectedPitchId);
      if (m.isNotEmpty) selectedPitchName = m.first.name.trim();
    }

    dCtrl.addListener(() {
      if (dCtrl.text.length == 10) {
        timeFocus.requestFocus();
      }
    });

    if (!context.mounted) return;

    InputDecoration deco(String label, IconData icon, {Widget? suffix}) =>
        InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          prefixIcon: Icon(icon, color: Colors.white70, size: 20),
          suffixIcon: suffix,
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.4),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: accent, width: 1.5),
          ),
        );

    BoxDecoration dialogBox() => BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1E293B), Color(0xFF064E3B)],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      boxShadow: const [
        BoxShadow(color: Colors.black54, blurRadius: 15, offset: Offset(0, 8)),
      ],
    );

    Future<void> pickDateFromCalendar(StateSetter setDialogState) async {
      final m = RegExp(
        r'^(\d{2})[\/\-](\d{2})[\/\-](\d{4})$',
      ).firstMatch(dCtrl.text.trim());
      final current = m == null
          ? null
          : DateTime.tryParse('${m.group(3)}-${m.group(2)}-${m.group(1)}');
      final picked = await showAppDatePicker(
        context: context,
        initialDate: current ?? DateTime.now(),
        firstYear: DateTime.now().year - 1,
        lastYear: DateTime.now().year + 2,
        title: 'Maç Tarihi',
      );
      if (picked == null) return;
      setDialogState(() {
        dCtrl.text =
            '${picked.day.toString().padLeft(2, '0')}/'
            '${picked.month.toString().padLeft(2, '0')}/'
            '${picked.year}';
      });
      timeFocus.requestFocus();
    }

    /// Stad seçimi: üstte isim filtresi olan ortada açılan popup.
    /// Sonuç: null → vazgeçildi, '' → "Stad Seçilmedi", aksi halde stad id.
    Future<String?> pickPitch() {
      var query = '';
      String norm(String v) =>
          v.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase().trim();
      return showDialog<String>(
        context: context,
        builder: (pc) => StatefulBuilder(
          builder: (pc, setLocal) {
            final q = norm(query);
            final list = pitches
                .where((p) => q.isEmpty || norm(p.name).contains(q))
                .toList();
            final h = MediaQuery.of(pc).size.height * 0.7;
            Widget tile(String id, String title, String sub) {
              final on = (selectedPitchId ?? '') == id;
              return ListTile(
                dense: true,
                title: Text(
                  title,
                  style: TextStyle(
                    color: on ? accent : Colors.white,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                subtitle: sub.isEmpty
                    ? null
                    : Text(
                        sub,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                trailing: on
                    ? const Icon(Icons.check_rounded, color: accent)
                    : null,
                onTap: () => Navigator.pop(pc, id),
              );
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: h,
                padding: const EdgeInsets.all(20),
                decoration: dialogBox(),
                child: Column(
                  children: [
                    const Text(
                      'Stad Seç',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      onChanged: (v) => setLocal(() => query = v),
                      decoration: deco('Stad ara', Icons.search_rounded),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: [
                          if (q.isEmpty) tile('', 'Stad Seçilmedi', ''),
                          for (final p in list)
                            tile(
                              p.id,
                              p.name,
                              [
                                if (p.city.trim().isNotEmpty) p.city.trim(),
                                if (p.country.trim().isNotEmpty)
                                  p.country.trim(),
                              ].join(' / '),
                            ),
                          if (list.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'Stad bulunamadı.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white54),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: AdminDialogCloseOverlay(
            onClose: () => Navigator.pop(c),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: dialogBox(),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.edit_calendar_rounded, color: accent),
                        SizedBox(width: 8),
                        Text(
                          'Maçı Düzenle',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(color: Colors.white24, height: 1),
                    const SizedBox(height: 18),
                    // Elle yazılabilir; buton standart takvimi açar.
                    TextField(
                      controller: dCtrl,
                      focusNode: dateFocus,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_DateInputFormatter()],
                      style: const TextStyle(color: Colors.white),
                      decoration: deco(
                        'Tarih (GG/AA/YYYY)',
                        Icons.event_rounded,
                        suffix: IconButton(
                          tooltip: 'Takvimden seç',
                          icon: const Icon(
                            Icons.calendar_month_outlined,
                            color: accent,
                          ),
                          onPressed: () => pickDateFromCalendar(setDialogState),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tCtrl,
                      focusNode: timeFocus,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_TimeInputFormatter()],
                      style: const TextStyle(color: Colors.white),
                      decoration: deco('Saat (SS:DD)', Icons.schedule_rounded),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final picked = await pickPitch();
                        if (picked == null) return;
                        setDialogState(() {
                          if (picked.isEmpty) {
                            selectedPitchId = null;
                            selectedPitchName = null;
                          } else {
                            selectedPitchId = picked;
                            final name = pitches
                                .firstWhere((p) => p.id == picked)
                                .name
                                .trim();
                            selectedPitchName = name.isEmpty ? null : name;
                          }
                        });
                      },
                      child: InputDecorator(
                        decoration: deco('Stad', Icons.stadium_outlined),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                selectedPitchName ?? 'Stad Seçilmedi',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selectedPitchName == null
                                      ? Colors.white54
                                      : Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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
                                content: Text(
                                  'Tarih formatı hatalı! (GG/AA/YYYY)',
                                ),
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
                            if (c.mounted) Navigator.pop(c);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Maç güncellendi.'),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                            onDataChanged();
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
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Dialog kapanış animasyonu bitene kadar alanlar bunları kullanır.
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      dateFocus.dispose();
      timeFocus.dispose();
      dCtrl.dispose();
      tCtrl.dispose();
    });
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

/// Hafta şeridi: ortada seçili hafta, yanlarında önceki ve sonraki hafta;
/// uçlardaki oklar birer hafta ilerletir. Haftaya dokunmak onu seçer.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.weeks,
    required this.week,
    required this.onSelect,
  });

  final List<int> weeks;
  final int week;
  final ValueChanged<int> onSelect;

  static const _accent = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    final sorted = [...weeks]..sort();
    final i = sorted.indexOf(week);
    final prev = i > 0 ? sorted[i - 1] : null;
    final next = i >= 0 && i < sorted.length - 1 ? sorted[i + 1] : null;

    Widget arrow(IconData icon, int? target) => IconButton(
      onPressed: target == null ? null : () => onSelect(target),
      icon: Icon(icon),
      color: Colors.white,
      disabledColor: Colors.white24,
      visualDensity: VisualDensity.compact,
    );

    Widget cell(int? w, {bool current = false}) => Expanded(
      flex: current ? 4 : 3,
      child: w == null
          ? const SizedBox()
          : GestureDetector(
              onTap: current ? null : () => onSelect(w),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 38,
                alignment: Alignment.center,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: current
                      ? _accent
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$w. Hafta',
                  maxLines: 1,
                  style: TextStyle(
                    color: current ? Colors.white : Colors.white60,
                    fontSize: current ? 15 : 13,
                    fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          arrow(Icons.chevron_left_rounded, prev),
          cell(prev),
          cell(week, current: true),
          cell(next),
          arrow(Icons.chevron_right_rounded, next),
        ],
      ),
    );
  }
}
