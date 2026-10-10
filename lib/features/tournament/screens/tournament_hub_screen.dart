import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../../core/services/global_filter.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/utils/table_feed.dart';
import '../../../core/services/active_tournament.dart';
import '../../../core/widgets/app_name_band.dart';
import '../../match/models/match.dart';
import '../../match/screens/fixture_screen.dart';
import '../../news/screens/news_feed_screen.dart';
import '../../player/screens/stats_screen.dart';
import '../../team/screens/groups_screen.dart';
import '../models/league.dart';
import '../models/season.dart';

enum TournamentHubTab { standings, fixture, stats, news }

/// Turnuva Sayfası: bir turnuva + sezon + grubun Puan Durumu, Fikstür,
/// İstatistik ve Haberler sekmeleri. Bantta sezon seçici (aktif sezon seçili
/// gelir; önceki sezonlara geçilebilir). Birden fazla grup varsa sekmelerin
/// üstünde grup çipleri; [groupId] verilirse (ör. takvimden) o grup seçili
/// açılır.
class TournamentHubScreen extends StatefulWidget {
  const TournamentHubScreen({
    super.key,
    required this.leagueId,
    this.seasonId,
    this.groupId,
    this.initialTab = TournamentHubTab.standings,
  });

  final String leagueId;

  /// Boşsa turnuvanın varsayılan (aktif) sezonu.
  final String? seasonId;

  /// Boşsa sezonun ilk grubu.
  final String? groupId;
  final TournamentHubTab initialTab;

  static Future<void> open(
    BuildContext context, {
    required String leagueId,
    String? seasonId,
    String? groupId,
    TournamentHubTab initialTab = TournamentHubTab.standings,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'TournamentHubScreen'),
        builder: (_) => TournamentHubScreen(
          leagueId: leagueId,
          seasonId: seasonId,
          groupId: groupId,
          initialTab: initialTab,
        ),
      ),
    );
  }

  @override
  State<TournamentHubScreen> createState() => _TournamentHubScreenState();
}

class _TournamentHubScreenState extends State<TournamentHubScreen>
    with SingleTickerProviderStateMixin {
  static const _bgDark = Color(0xFF0F172A);

  late final TabController _tabs = TabController(
    length: TournamentHubTab.values.length,
    vsync: this,
    initialIndex: widget.initialTab.index,
  )..addListener(_onTab);

  late final Stream<League?> _leagueStream = ServiceLocator.leagueService
      .watchLeagueById(widget.leagueId);
  late final Stream<List<Season>> _seasonsStream = watchTableRows(
    Supabase.instance.client,
    table: 'seasons',
    column: 'league_id',
    value: widget.leagueId,
    orderBy: 'start_date',
    ascending: false,
  ).map((rows) => rows.map((r) => Season.fromMap(r)).toList());

  String? _seasonId;
  String? _groupId;
  Stream<List<GroupModel>>? _groupsStream;

  /// Fikstür sekmesinin seçili hafta afişi (yetki ve maç varsa dolu).
  final _fixtureShare = ValueNotifier<VoidCallback?>(null);

  @override
  void initState() {
    super.initState();
    _seasonId = widget.seasonId;
    _groupId = widget.groupId;
    if (_seasonId != null) {
      _groupsStream = ServiceLocator.leagueService.watchGroups(_seasonId!);
    }
  }

  /// Bu sayfanın rotası: bant içeriği (geri, turnuva kimliği, sezon) ona
  /// bağlanır.
  ModalRoute<dynamic>? _route;

  @override
  void dispose() {
    LeagueSwitchScope.setPageBand(_route, null);
    _tabs.dispose();
    _fixtureShare.dispose();
    super.dispose();
  }

  /// Bant: solda geri, ortada turnuvanın logosu ve adı, sağda sezon.
  void _syncBand(
    League? league,
    Season? season,
    List<Season> seasons,
    List<GroupModel> groups,
  ) {
    _route = ModalRoute.of(context);
    if (league == null) return;
    final theme = TournamentTheme.fromRow({
      'id': league.id,
      'name': league.name,
      'short_name': league.shortName,
      'logo_url': league.logoUrl,
      'theme_primary': league.themePrimary,
      'theme_secondary': league.themeSecondary,
    });
    if (theme == null) return;
    LeagueSwitchScope.setPageBand(
      _route,
      PageBand(
        theme: theme,
        onBack: () => Navigator.of(context).maybePop(),
        trailing: season == null
            ? null
            : _BandSeasonButton(
                text: season.name,
                canPick: seasons.length > 1,
                onTap: () => _pickSeason(seasons, groups),
              ),
      ),
    );
  }

  void _onTab() {
    if (!_tabs.indexIsChanging && mounted) setState(() {});
  }

  void _useSeason(String seasonId) {
    _seasonId = seasonId;
    _groupsStream = ServiceLocator.leagueService.watchGroups(seasonId);
  }

  /// Başka sezona geçiş: aynı adlı grup varsa o, yoksa ilk grup açılır.
  Future<void> _changeSeason(String seasonId, List<GroupModel> current) async {
    if (seasonId == _seasonId) return;
    final currentName = current
        .where((g) => g.id == _groupId)
        .firstOrNull
        ?.name
        .trim()
        .toLowerCase();
    final groups = await ServiceLocator.leagueService
        .watchGroups(seasonId)
        .first;
    if (!mounted) return;
    final same = groups
        .where((g) => g.name.trim().toLowerCase() == currentName)
        .firstOrNull;
    setState(() {
      _useSeason(seasonId);
      _groupId = (same ?? groups.firstOrNull)?.id;
    });
  }

  /// Sezon listesi: bandın altında, sağa yaslı açılır.
  Future<void> _pickSeason(
    List<Season> seasons,
    List<GroupModel> groups,
  ) async {
    final band = bandRectInOverlay();
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (band == null || overlay == null) return;
    final picked = await showMenu<String>(
      context: context,
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      position: RelativeRect.fromRect(
        Rect.fromLTWH(band.right - 8, band.bottom, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final s in seasons)
          PopupMenuItem<String>(
            value: s.id,
            child: Row(
              children: [
                Icon(
                  s.id == _seasonId
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 18,
                  color: s.id == _seasonId ? Colors.white : Colors.white38,
                ),
                const SizedBox(width: 10),
                Text(
                  s.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (picked != null) await _changeSeason(picked, groups);
  }

  static Color _color(String? hex, Color fallback) {
    final h = (hex ?? '').replaceAll('#', '').trim();
    final v = int.tryParse(h, radix: 16);
    return h.length == 6 && v != null ? Color(0xFF000000 | v) : fallback;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<League?>(
      stream: _leagueStream,
      builder: (context, leagueSnap) {
        final league = leagueSnap.data;
        final accent = _color(league?.themeSecondary, const Color(0xFF10B981));
        return StreamBuilder<List<Season>>(
          stream: _seasonsStream,
          builder: (context, seasonSnap) {
            final seasons = seasonSnap.data ?? const <Season>[];
            if (_seasonId == null && seasons.isNotEmpty) {
              _useSeason(pickDefaultSeasonId(seasons));
            }
            return StreamBuilder<List<GroupModel>>(
              stream: _groupsStream,
              builder: (context, groupSnap) {
                final groups = [...groupSnap.data ?? const <GroupModel>[]]
                  ..sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );
                final group =
                    groups.where((g) => g.id == _groupId).firstOrNull ??
                    groups.firstOrNull;
                final season = seasons
                    .where((s) => s.id == _seasonId)
                    .firstOrNull;
                _syncBand(league, season, seasons, groups);
                // Başlık çubuğu yok: sekmeler doğrudan bandın altında.
                return Scaffold(
                  backgroundColor: _bgDark,
                  // Afiş paylaşma: sekmelerin yanında değil, sağ altta yüzer.
                  floatingActionButton: _shareButton(group, accent),
                  body: SafeArea(
                    top: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        // Birden fazla grup varsa sekmelerin üstünde ortalı
                        // grup çipleri; tek gruplu turnuvada satır yok.
                        if (groups.length > 1 && group != null)
                          _GroupChips(
                            groups: groups,
                            selectedId: group.id,
                            accent: accent,
                            onSelect: (id) => setState(() => _groupId = id),
                          ),
                        _HubTabBar(controller: _tabs, accent: accent),
                        Expanded(
                          child: season == null || group == null
                              ? Center(
                                  child: groupSnap.hasData && seasonSnap.hasData
                                      ? const Text(
                                          'Bu sezonda henüz grup yok.',
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                        )
                                      : const CircularProgressIndicator(),
                                )
                              : TabBarView(
                                  controller: _tabs,
                                  children: [
                                    _KeepAlive(
                                      child: StandingsView(
                                        key: ValueKey(
                                          'st|${season.id}|${group.id}',
                                        ),
                                        leagueId: widget.leagueId,
                                        seasonId: season.id,
                                        groupId: group.id,
                                      ),
                                    ),
                                    _KeepAlive(
                                      child: FixtureView(
                                        key: ValueKey(
                                          'fx|${season.id}|${group.id}',
                                        ),
                                        leagueId: widget.leagueId,
                                        seasonId: season.id,
                                        groupId: group.id,
                                        shareAction: _fixtureShare,
                                      ),
                                    ),
                                    _KeepAlive(
                                      child: StatsView(
                                        key: ValueKey('ss|${season.id}'),
                                        seasonId: season.id,
                                      ),
                                    ),
                                    _KeepAlive(
                                      child: NewsView(
                                        key: ValueKey(
                                          'nw|${season.id}|${group.regionId}',
                                        ),
                                        seasonId: season.id,
                                        regionId: group.regionId,
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
            );
          },
        );
      },
    );
  }

  /// Puan Durumu ve Fikstür sekmelerinde sağ altta yüzen afiş paylaşma
  /// düğmesi.
  Widget? _shareButton(GroupModel? group, Color accent) {
    Widget fab(VoidCallback onPressed) => FloatingActionButton(
      heroTag: null,
      tooltip: 'Afişi paylaş',
      backgroundColor: accent,
      foregroundColor: Colors.white,
      onPressed: onPressed,
      child: const Icon(Icons.ios_share_rounded),
    );
    final seasonId = _seasonId;
    switch (TournamentHubTab.values[_tabs.index]) {
      case TournamentHubTab.standings:
        // Afişi yalnızca giriş yapmış kullanıcılar paylaşabilir.
        if (group == null ||
            seasonId == null ||
            AppSession.of(context).value.user == null) {
          return null;
        }
        return fab(
          () => shareGroupStandings(
            context,
            leagueId: widget.leagueId,
            seasonId: seasonId,
            groupId: group.id,
          ),
        );
      case TournamentHubTab.fixture:
        return ValueListenableBuilder<VoidCallback?>(
          valueListenable: _fixtureShare,
          builder: (context, share, _) =>
              share == null ? const SizedBox.shrink() : fab(share),
        );
      case TournamentHubTab.stats:
      case TournamentHubTab.news:
        return null;
    }
  }
}

/// Grup çipleri: sığarsa ortalı, sığmazsa yana kayar.
class _GroupChips extends StatelessWidget {
  const _GroupChips({
    required this.groups,
    required this.selectedId,
    required this.accent,
    required this.onSelect,
  });

  final List<GroupModel> groups;
  final String selectedId;
  final Color accent;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: c.maxWidth - 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final g in groups)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _chip(g),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(GroupModel g) {
    final on = g.id == selectedId;
    return Material(
      color: on ? accent : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(
          color: on ? accent : Colors.white.withValues(alpha: 0.14),
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: on ? null : () => onSelect(g.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            g.name.trim().isEmpty ? 'Grup' : g.name.trim(),
            style: TextStyle(
              color: on ? Colors.white : Colors.white70,
              fontSize: 12.5,
              fontWeight: on ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bantta sağda sezon: birden fazla sezon varsa ▾ ile liste açılır.
class _BandSeasonButton extends StatelessWidget {
  const _BandSeasonButton({
    required this.text,
    required this.canPick,
    required this.onTap,
  });

  final String text;
  final bool canPick;
  final VoidCallback onTap;

  static const _style = TextStyle(
    color: Colors.white,
    fontSize: 12.5,
    fontWeight: FontWeight.w800,
    decoration: TextDecoration.none,
  );

  /// "2026 Sezonu" bantta sığmıyor: yıl üstte, "Sezonu" altında küçük ve
  /// ortalı. Yılla başlamayan ad tek satır.
  Widget _label() {
    final m = RegExp(
      r'^(\d{4}(?:\s*[-/]\s*\d{2,4})?)\s+(.+)$',
    ).firstMatch(text.trim());
    if (m == null) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _style,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          m.group(1)!,
          maxLines: 1,
          style: _style.copyWith(fontSize: 14, height: 1.05),
        ),
        Text(
          m.group(2)!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _style.copyWith(
            color: Colors.white70,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            height: 1.05,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: canPick ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: _label()),
              if (canPick)
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubTabBar extends StatelessWidget {
  const _HubTabBar({required this.controller, required this.accent});

  final TabController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: false,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(4),
        indicator: BoxDecoration(
          color: accent.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.6)),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white60,
        labelPadding: EdgeInsets.zero,
        labelStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        tabs: const [
          Tab(text: 'Puan Durumu', height: 40),
          Tab(text: 'Fikstür', height: 40),
          Tab(text: 'İstatistik', height: 40),
          Tab(text: 'Haberler', height: 40),
        ],
      ),
    );
  }
}

/// Sekmeler arasında geçince içerik yeniden kurulmasın.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
