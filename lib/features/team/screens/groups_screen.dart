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
import '../../../core/utils/team_name.dart';
import '../../../core/utils/realtime_signal.dart';
import '../../../core/utils/resilient_stream.dart';
import 'team_squad_screen.dart';

// YENİ OLUŞTURDUĞUMUZ ORTAK BİLEŞENİ IMPORT EDİYORUZ
import '../../../core/widgets/tournament_filter_dialog.dart';
import '../../../core/utils/string_utils.dart';
import '../../../core/widgets/league_logo.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../utils/standings.dart';
import '../../share/poster_share.dart';
import '../../../core/services/app_session.dart';
import '../../share/standings_poster.dart';

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
    return resilientStream(
      () => Supabase.instance.client
          .from('seasons')
          .stream(primaryKey: ['id'])
          .eq('league_id', leagueId)
          .order('start_date', ascending: false)
          .map((rows) => rows.map((r) => Season.fromMap(r)).toList()),
    );
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
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: InkWell(
                                onTap: () {
                                  _showFilterDialog(context, leagues);
                                },
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

                            final leagueLogo =
                                _leagueLogoById[_selectedLeagueId] ?? '';
                            final leagueName =
                                _leagueNameById[_selectedLeagueId] ?? '';
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Turnuva bandı: logo, ad ve sezon.
                                if (leagueLogo.trim().isNotEmpty &&
                                    leagueName.trim().isNotEmpty)
                                  _LeagueBanner(
                                    logoUrl: leagueLogo,
                                    leagueName: leagueName,
                                    subtitle:
                                        (_seasonNameById[_selectedSeasonId] ??
                                                '')
                                            .trim(),
                                  ),
                                if (allGroups.length > 1)
                                  _GroupTabs(
                                    groups: allGroups,
                                    activeId: active.id,
                                    onSelect: (g) =>
                                        setState(() => _selectedGroupId = g.id),
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
    GlobalFilter.setSeason(result.seasonId);
    setState(() {
      _selectedLeagueId = result.leagueId;
      _selectedSeasonId = result.seasonId;
      _selectedGroupId = result.groupId;
    });
  }
}

/// Sezondaki gruplar için sekme şeridi (yatay kaydırılır).
class _GroupTabs extends StatelessWidget {
  const _GroupTabs({
    required this.groups,
    required this.activeId,
    required this.onSelect,
  });

  final List<GroupModel> groups;
  final String activeId;
  final ValueChanged<GroupModel> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      // Sekmeler tüm genişliği eşit paylaşır; grup sayısı arttıkça daralır,
      // uzun adlar küçülerek sığar.
      child: Row(
        children: [
          for (final g in groups)
            Expanded(
              child: InkWell(
                onTap: () => onSelect(g),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: g.id == activeId ? _kAccent : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      g.name.trUpper,
                      maxLines: 1,
                      style: TextStyle(
                        color: g.id == activeId ? Colors.white : _kMidText,
                        fontWeight: FontWeight.w800,
                        fontSize: groups.length > 3 ? 12 : 14,
                        letterSpacing: 0.4,
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
    final feed = _seasonMatchFeeds.putIfAbsent(
      '$id|$sId',
      () => resilientStream(() => _seasonMatchesFeed(id, sId)),
    );
    if (fetchGroupId == null) return feed;
    return feed.map(
      (rows) => rows
          .where((r) => (r['group_id'] ?? '').toString().trim() == fetchGroupId)
          .toList(),
    );
  }

  /// Sezon maçları: tüm grup tabloları aynı akışı paylaşır ve son liste
  /// önbellekte tutulur ("leagueId|seasonId" anahtarıyla).
  static final Map<String, Stream<List<Map<String, dynamic>>>>
  _seasonMatchFeeds = {};
  static final Map<String, List<Map<String, dynamic>>> _seasonMatchCache = {};

  /// Önce önbellek, sonra yalnızca bu sezonun maçları; realtime yalnızca
  /// "değişti" sinyali verir (önceden tüm matches tablosu indiriliyordu).
  static Stream<List<Map<String, dynamic>>> _seasonMatchesFeed(
    String leagueId,
    String seasonId,
  ) async* {
    final key = '$leagueId|$seasonId';
    final client = Supabase.instance.client;

    Future<List<Map<String, dynamic>>> fetch() async {
      final rows = await client
          .from('matches')
          .select()
          .eq('league_id', leagueId)
          .eq('season_id', seasonId)
          .order('match_date', ascending: true);
      final list = rows.map((e) => Map<String, dynamic>.from(e)).toList();
      _seasonMatchCache[key] = list;
      return list;
    }

    final cached = _seasonMatchCache[key];
    if (cached != null) yield cached;
    yield await fetch();
    await for (final _ in realtimeChangeSignal(
      client,
      table: 'matches',
      column: 'season_id',
      value: seasonId,
    )) {
      yield await fetch();
    }
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

              return Container(
                // Ekranı kenardan kenara kaplar; sekmelerle tek parça görünür.
                color: Colors.black.withValues(alpha: 0.45),
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

class _LeagueBanner extends StatelessWidget {
  const _LeagueBanner({
    required this.logoUrl,
    required this.leagueName,
    required this.subtitle,
  });

  final String logoUrl;
  final String leagueName;
  final String subtitle;

  static const _gold = Color(0xFFE2B845);

  @override
  Widget build(BuildContext context) {
    // İnce bant (puan durumunda daha çok takım sığsın); logo bandın üstüne
    // hafifçe taşar.
    return Container(
      height: 46,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1B2A6B).withValues(alpha: 0.95),
            const Color(0xFF0F172A).withValues(alpha: 0.6),
          ],
          stops: const [0, 0.75],
        ),
        border: Border(
          bottom: BorderSide(color: _gold.withValues(alpha: 0.35)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            height: 46,
            child: OverflowBox(
              maxHeight: 58,
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: LeagueLogo(url: logoUrl, size: 54, fallbackColor: _gold),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  leagueName.trUpper,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    height: 1.1,
                    letterSpacing: 0.4,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
          height: 40,
          padding: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: zoneColor, width: 3),
              top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 3),
              SizedBox(
                width: c.rank,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: isLeader ? _kAccent : teamText,
                    fontSize: 13,
                    fontFeatures: _tabular,
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
                child: Text(
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
                    fontWeight: FontWeight.w900,
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
