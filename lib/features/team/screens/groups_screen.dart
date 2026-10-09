import 'package:flutter/material.dart';
import 'package:football_tournament/core/widgets/master_class_app_bar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../tournament/models/league.dart';
import '../../tournament/models/season.dart';
import '../../match/models/match.dart';
import '../models/team.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/services/global_filter.dart';
import '../../../core/services/active_tournament.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/utils/table_feed.dart';
import 'team_squad_screen.dart';

// YENİ OLUŞTURDUĞUMUZ ORTAK BİLEŞENİ IMPORT EDİYORUZ
import '../../../core/widgets/tournament_filter_dialog.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../utils/standings.dart';
import '../../share/poster_share.dart';
import '../../../core/services/app_session.dart';
import '../../share/standings_poster.dart';
import '../../../core/widgets/league_filter_header.dart';

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

  /// Ekranda açık olan grup sekmesi (paylaşım afişi bunun için hazırlanır).
  GroupModel? _activeGroup;
  bool _sharing = false;

  Stream<List<League>>? _leaguesStream;

  /// Puan tablosu başlığındaki turnuva logosu için (lig akışından doldurulur).
  Map<String, String> _leagueLogoById = const {};
  Map<String, String> _leagueNameById = const {};
  Map<String, String> _seasonNameById = const {};

  String? _lastLeagueIdForSeason;
  Stream<List<Season>>? _seasonsStream;

  String? _lastSeasonIdForGroup;
  Stream<List<GroupModel>>? _groupsStream;

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

  static bool _sameMap(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

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
      appBar: MasterClassAppBar(
        title: 'Puan Durumu',
        actions: [
          // Afişi yalnızca giriş yapmış kullanıcılar paylaşabilir.
          if (AppSession.of(context).value.user != null)
            IconButton(
              tooltip: 'Paylaş',
              onPressed: _sharing ? null : _shareStandings,
              icon: _sharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.ios_share_rounded, color: Colors.white),
            ),
        ],
      ),
      body: Stack(
        children: [
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

                    final logos = {for (final l in leagues) l.id: l.logoUrl};
                    final names = {for (final l in leagues) l.id: l.name};
                    if (!_sameMap(logos, _leagueLogoById) ||
                        !_sameMap(names, _leagueNameById)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _leagueLogoById = logos;
                            _leagueNameById = names;
                          });
                        }
                      });
                    }

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

                    return StreamBuilder<List<Season>>(
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

                        if (_selectedLeagueId != null && seasons.isNotEmpty) {
                          if (_selectedSeasonId == null ||
                              !seasons.any((s) => s.id == _selectedSeasonId)) {
                            final def = pickDefaultSeasonId(seasons);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              setState(() {
                                _selectedSeasonId = def;
                                _selectedGroupId = null;
                              });
                              GlobalFilter.setSeason(def);
                            });
                          }
                        }

                        final seasonNames = {
                          for (final s in seasons) s.id: s.name,
                        };
                        if (seasons.isNotEmpty &&
                            !_sameMap(seasonNames, _seasonNameById)) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() => _seasonNameById = seasonNames);
                            }
                          });
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
                            // Gruplar/bölgeler zaten sekme olarak görünür;
                            // filtre yalnızca turnuvada birden fazla aktif
                            // sezon varsa gösterilir.
                            if (seasons.where((s) => s.isActive).length < 2) {
                              return const SizedBox(height: 4);
                            }
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: LeagueFilterCapsule(
                                seasonName: currentSeasonName,
                                onTap: () =>
                                    _showFilterDialog(context, leagues),
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
                            // Sezon değişince eski sezonun grupları
                            // gösterilmesin.
                            if (!snapshot.hasData ||
                                snapshot.connectionState ==
                                    ConnectionState.waiting) {
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

                            // Sekmeler: sezondaki her grup. Seçili grup yoksa
                            // (ya da başka sezona aitse) ilk grup açılır.
                            final active = allGroups.firstWhere(
                              (g) => g.id == _selectedGroupId,
                              orElse: () => allGroups.first,
                            );
                            _activeGroup = active;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (allGroups.length > 1)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      8,
                                    ),
                                    child: GroupSegmentTabs(
                                      groups: [
                                        for (final g in allGroups)
                                          (id: g.id, name: g.name),
                                      ],
                                      selectedId: active.id,
                                      onSelect: (id) {
                                        GlobalFilter.setGroup(id);
                                        setState(() => _selectedGroupId = id);
                                      },
                                    ),
                                  ),
                                Expanded(
                                  child: ListView(
                                    padding: const EdgeInsets.only(bottom: 120),
                                    children: [
                                      _GroupStandingsTable(
                                        key: ValueKey(active.id),
                                        leagueId: _selectedLeagueId!,
                                        seasonId: _selectedSeasonId!,
                                        groupId: active.id,
                                        groupName: active.name,
                                        fetchGroupId: null,
                                        leagueLogoUrl:
                                            _leagueLogoById[_selectedLeagueId] ??
                                            '',
                                        leagueName:
                                            _leagueNameById[_selectedLeagueId] ??
                                            '',
                                        seasonName:
                                            _seasonNameById[_selectedSeasonId] ??
                                            '',
                                        showGroupName: allGroups.length > 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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

  /// Açık sekmedeki grubun puan durumu afişi (Instagram hikaye boyutu).
  Future<void> _shareStandings() async {
    final leagueId = _selectedLeagueId;
    final seasonId = _selectedSeasonId;
    final group = _activeGroup;
    if (leagueId == null || seasonId == null || group == null) return;
    setState(() => _sharing = true);
    try {
      final client = Supabase.instance.client;
      final results = await Future.wait<Object>([
        client
            .from('matches')
            .select()
            .eq('league_id', leagueId)
            .eq('season_id', seasonId),
        ServiceLocator.teamService.watchAllTeams().first,
      ]);
      final matches = (results[0] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final rows = computeGroupStandings(
        leagueId: leagueId,
        groupId: group.id,
        groupName: group.name,
        seasonMatches: matches,
        allTeams: results[1] as List<Team>,
      );
      if (!mounted) return;
      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paylaşılacak puan durumu yok.')),
        );
        return;
      }
      final leagueLogo = _leagueLogoById[leagueId] ?? '';
      final leagueName = _leagueNameById[leagueId] ?? '';
      final seasonName = _seasonNameById[seasonId] ?? '';
      await showPosterPreview(
        context: context,
        fileName: 'puan_durumu_${group.name}'.replaceAll(' ', '_'),
        leagueId: leagueId,
        imageUrls: [
          leagueLogo,
          for (final r in rows) r.logo,
        ].where((u) => u.trim().isNotEmpty).toList(),
        poster: StandingsPoster(
          leagueName: leagueName,
          leagueLogo: leagueLogo,
          subtitle: [
            seasonName,
            group.name,
          ].where((e) => e.trim().isNotEmpty).join(' · '),
          rows: rows,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Afiş hazırlanamadı: $e')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  // Kapsüle tıklandığında ORTADA açılacak Filtre Paneli; seçimler yalnızca
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
        groupId: _selectedGroupId,
      ),
      watchSeasons: _watchSeasons,
      watchGroups: _leagueService.watchGroups,
    );
    if (result == null || !mounted) return;
    GlobalFilter.setLeague(result.leagueId);
    ActiveTournament.noteViewed(result.leagueId);
    GlobalFilter.setSeason(result.seasonId);
    setState(() {
      _selectedLeagueId = result.leagueId;
      _selectedSeasonId = result.seasonId;
      _selectedGroupId = result.groupId;
    });
  }
}

class _GroupStandingsTable extends StatefulWidget {
  final String leagueId;
  final String seasonId;
  final String groupId;
  final String groupName;
  final String? fetchGroupId;

  /// Turnuva logosu; boşsa başlıkta kupa ikonu gösterilir.
  final String leagueLogoUrl;

  /// Logolu banner başlık için turnuva ve sezon adı.
  final String leagueName;
  final String seasonName;

  /// Sezonda birden fazla grup varsa başlığın sağında grup adı gösterilir.
  final bool showGroupName;

  const _GroupStandingsTable({
    super.key,
    required this.leagueId,
    required this.seasonId,
    required this.groupId,
    required this.groupName,
    required this.fetchGroupId,
    this.leagueLogoUrl = '',
    this.leagueName = '',
    this.seasonName = '',
    this.showGroupName = false,
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
    // Sezonun maçları tek akışta; gol vb. değişiklikte yalnızca değişen
    // satır işlenir (bkz. watchTableRows). Tüm grup tabloları aynı akışı
    // paylaşır.
    final feed = watchTableRows(
      Supabase.instance.client,
      table: 'matches',
      column: 'season_id',
      value: sId,
      orderBy: 'match_date',
    ).map(
      (rows) => rows
          .where((r) => (r['league_id'] ?? '').toString().trim() == id)
          .toList(),
    );
    if (fetchGroupId == null) return feed;
    return feed.map(
      (rows) => rows
          .where((r) => (r['group_id'] ?? '').toString().trim() == fetchGroupId)
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    const midText = Color(0xFF94A3B8);
    const accentGreen = Color(0xFF10B981);

    return Padding(
      padding: EdgeInsets.zero,
      child: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _matchesStream,
        builder: (context, mergedSnapshot) {
          if (mergedSnapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final seasonMatches =
              mergedSnapshot.data ?? const <Map<String, dynamic>>[];

          return StreamBuilder<List<Team>>(
            stream: _teamsStream,
            builder: (context, teamsSnapshot) {
              if (teamsSnapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final rows = computeGroupStandings(
                leagueId: widget.leagueId,
                groupId: widget.groupId,
                groupName: widget.groupName,
                seasonMatches: seasonMatches,
                allTeams: teamsSnapshot.data ?? const <Team>[],
              );

              if (rows.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '${widget.groupName} için henüz takım/maç verisi yok.',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                );
              }

              // 4'ten az takımda bölge şeritleri anlamsız (hepsi yeşil olur).
              final showZones = rows.length > 4;

              // Kenarlardan boşluklu, yuvarlak köşeli kart.
              return Container(
                margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Sütun başlıkları
                    Container(
                      color: Colors.white.withValues(alpha: 0.04),
                      padding: const EdgeInsets.fromLTRB(3, 7, 10, 7),
                      child: const _StandingsHeaderRow(),
                    ),
                    for (var i = 0; i < rows.length; i++)
                      _StandingsRow(
                        index: i,
                        entry: rows[i],
                        totalCount: rows.length,
                        showZones: showZones,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TeamSquadScreen(
                                teamId: rows[i].teamId,
                                tournamentId: widget.leagueId,
                                teamName: rows[i].name,
                                teamLogoUrl: rows[i].logo,
                              ),
                            ),
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
                          const _LegendDot(
                            color: accentGreen,
                            label: 'Galibiyet',
                          ),
                          const _LegendDot(
                            color: Color(0xFF64748B),
                            label: 'Beraberlik',
                          ),
                          const _LegendDot(
                            color: Color(0xFFF87171),
                            label: 'Mağlubiyet',
                          ),
                          Text(
                            'O: Oynanan  G: Galibiyet  B: Beraberlik  '
                            'M: Mağlubiyet  A: Atılan  Y: Yenilen  AV: Averaj',
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
const _kMidText = Color(0xFF94A3B8);
const _kAccent = Color(0xFF10B981);

/// Sütun genişlikleri başlık ve satırlarda ortak kullanılır. Dar ekranlarda
/// (ör. 360dp) G/B/M de görünsün diye sütunlar sıkıştırılır.
class _StandingsCols {
  const _StandingsCols({
    required this.rank,
    required this.stat,
    required this.av,
    required this.pts,
    required this.gap,
    required this.fontSize,
  });

  final double rank;
  final double stat;
  final double av;
  final double pts;
  final double gap;
  final double fontSize;

  static const wide = _StandingsCols(
    rank: 26,
    stat: 25,
    av: 30,
    pts: 30,
    gap: 6,
    fontSize: 14,
  );
  static const compact = _StandingsCols(
    rank: 22,
    stat: 21,
    av: 26,
    pts: 26,
    gap: 4,
    fontSize: 12.5,
  );

  static _StandingsCols of(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 390 ? compact : wide;
}

const _tabular = [FontFeature.tabularFigures()];

class _StandingsHeaderRow extends StatelessWidget {
  const _StandingsHeaderRow();

  @override
  Widget build(BuildContext context) {
    final c = _StandingsCols.of(context);
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
        h('#', c.rank),
        SizedBox(width: c.gap + 31),
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
        h('O', c.stat),
        h('G', c.stat),
        h('B', c.stat),
        h('M', c.stat),
        h('A', c.stat),
        h('Y', c.stat),
        h('AV', c.av),
        const SizedBox(width: 4),
        h('P', c.pts, highlight: true),
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
    required this.entry,
    required this.totalCount,
    required this.showZones,
    required this.onTap,
  });

  final int index;
  final StandingEntry entry;
  final int totalCount;
  final bool showZones;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const teamText = Color(0xFFF8FAFC);
    const classOrange = Color(0xFFF59E0B);
    const negative = Color(0xFFF87171);
    final c = _StandingsCols.of(context);

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
              fontSize: c.fontSize,
              fontWeight: w ?? FontWeight.w600,
              color: color ?? const Color(0xFFCBD5E1),
              fontFeatures: _tabular,
            ),
          ),
        ),
      );
    }

    final isLeader = index == 0 && entry.played > 0;

    Color zoneColor = Colors.transparent;
    if (showZones) {
      if (index < 4) {
        zoneColor = _kAccent;
      } else if (index >= totalCount - 4) {
        zoneColor = classOrange;
      }
    }

    final av = entry.goalDiff;
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
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(0, 5, 10, 5),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 3),
              // Sıra yuvarlak içinde: üst tur dolu yeşil, klasman turuncu.
              SizedBox(
                width: c.rank,
                child: Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: zoneColor == _kAccent
                          ? _kAccent
                          : zoneColor == classOrange
                          ? classOrange.withValues(alpha: 0.18)
                          : const Color(0xFF334155),
                      border: zoneColor == classOrange
                          ? Border.all(color: classOrange, width: 1.5)
                          : null,
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: zoneColor == _kAccent
                            ? const Color(0xFF052E20)
                            : zoneColor == classOrange
                            ? classOrange
                            : teamText,
                        fontSize: 11.5,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: c.gap - 2),
              WebSafeImage(
                url: entry.logo,
                width: 22,
                height: 22,
                fit: BoxFit.contain,
                fallbackIconSize: 18,
              ),
              const SizedBox(width: 8),
              // Uzun adlar küçülmek yerine 2 satıra iner.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      shortTeamName(entry.name),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: teamText,
                        fontSize: 12.5,
                        height: 1.15,
                      ),
                    ),
                    // Son 5 maç: yeşil galibiyet, gri beraberlik, kırmızı
                    // mağlubiyet.
                    if (entry.form.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          for (final r in entry.form)
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: r == 'G'
                                    ? _kAccent
                                    : r == 'B'
                                    ? const Color(0xFF64748B)
                                    : negative,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              stat('${entry.played}', c.stat),
              stat('${entry.won}', c.stat),
              stat('${entry.drawn}', c.stat),
              stat('${entry.lost}', c.stat),
              stat('${entry.goalsFor}', c.stat),
              stat('${entry.goalsAgainst}', c.stat),
              stat(avText, c.av, color: avColor, w: FontWeight.w700),
              const SizedBox(width: 4),
              SizedBox(
                width: c.pts,
                child: Text(
                  '${entry.points}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _kAccent,
                    fontSize: 15,
                    fontFeatures: _tabular,
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
