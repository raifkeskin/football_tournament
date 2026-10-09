import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/table_feed.dart';
import '../../tournament/models/league.dart';
import '../../tournament/models/season.dart';
import '../../match/models/match.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/app_settings.dart';
import '../../team/models/team.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../../match/services/interfaces/i_match_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/services/global_filter.dart';
import '../../../core/services/active_tournament.dart';
import '../../../core/utils/resilient_stream.dart';
import '../../../core/widgets/app_date_picker.dart';
import '../../tournament/screens/tournament_hub_screen.dart';
import '../../match/screens/match_details_screen.dart';
import '../../match/widgets/match_score_line.dart';
import '../../../core/widgets/league_logo.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/widgets/youtube_player_page.dart';
import '../widgets/home_news_card.dart';
import '../widgets/home_dashboard.dart';
import '../../../core/design_flags.dart';
import '../../../core/widgets/app_name_band.dart';

/// Ana sayfa — günün maçları, tarih şeridi ve maç kartları.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.showCalendar = false});

  /// Ana gezinmede eski takvimli maç ekranını göstermek için.
  final bool showCalendar;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Takvim görünümü (Maç Takvimi).
  bool get _calendar => widget.showCalendar;

  static const int _yaricap = 2;

  static const List<String> _haftaKisa = [
    'Pzt',
    'Sal',
    'Çar',
    'Per',
    'Cum',
    'Cmt',
    'Paz',
  ];

  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final IMatchService _matchService = ServiceLocator.matchService;
  final ITeamService _teamService = ServiceLocator.teamService;
  late List<DateTime> _tarihler;
  int _seciliIndeks = 2;
  String? _activeLeagueId;
  bool _didAutoSelectDefaultLeague = false;

  /// Kişiye özel turnuva seçiminin yapıldığı kullanıcı (giriş değişince
  /// yeniden yapılır).
  String? _preferredForUid;
  late DateTime _selectedDate;

  /// Üst banttaki turnuva seçici. Şimdilik gizli: ana sayfa tüm turnuvaların
  /// maçlarını gösterir. Tekrar açmak için true yapın.
  static const bool _showLeagueFilter = false;

  /// Ana sayfada gösterilecek turnuvalar (seçici gizliyken hepsi).
  Set<String> _visibleLeagueIds = const <String>{};
  Map<String, String> _leagueNameById = const <String, String>{};
  Map<String, String> _leagueLogoById = const <String, String>{};
  Map<String, Color> _leaguePrimaryById = const <String, Color>{};
  Map<String, Color> _leagueSecondaryById = const <String, Color>{};

  static Color _themeColor(String? value, Color fallback) {
    final hex = (value ?? '').trim();
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return fallback;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Gün bazlı maç akışları ve son listeleri. Akış her yeniden çizimde
  /// kurulmaz; daha önce açılan bir güne dönünce maçlar hemen görünür.
  /// (Akış ve önbellek watchTableRows içinde tutulur.)
  /// Seçilen günün tüm turnuvalardaki maçları.
  Stream<List<MatchModel>> _watchMatchesOnDate(DateTime date) {
    final key = _dateKey(date);
    final feed = watchTableRows(
      Supabase.instance.client,
      table: 'matches',
      column: 'match_date',
      value: key,
    );
    return feed.map(
      (rows) => rows
          .where(
            (r) =>
                _visibleLeagueIds.contains((r['league_id'] ?? '').toString()),
          )
          .map((r) => MatchModel.fromMap(r, (r['id'] ?? '').toString()))
          .toList(),
    );
  }

  // Build içinde her seferinde yeniden kurulmasınlar diye saklanır.
  Stream<List<MatchModel>>? _dayMatchesStream;
  String? _dayMatchesKey;
  Set<String>? _dayMatchesLeagues;

  Stream<List<MatchModel>> _matchesOnDateStream(DateTime date) {
    final key = _dateKey(date);
    if (_dayMatchesStream == null ||
        _dayMatchesKey != key ||
        !setEquals(_dayMatchesLeagues, _visibleLeagueIds)) {
      _dayMatchesKey = key;
      _dayMatchesLeagues = _visibleLeagueIds;
      _dayMatchesStream = _watchMatchesOnDate(date);
    }
    return _dayMatchesStream!;
  }

  late final Stream<List<Season>> _allSeasonsStream = _watchAllSeasons();

  /// Tüm gruplar (id, season_id, name): bir sezonda birden fazla grup varsa
  /// ana sayfada maçlar gruba göre ayrılır.
  late final Stream<List<Map<String, dynamic>>> _groupsStream = watchTableRows(
    Supabase.instance.client,
    table: 'groups',
  );

  Stream<List<Season>> _watchAllSeasons() {
    return watchTableRows(
      Supabase.instance.client,
      table: 'seasons',
    ).map((rows) => rows.map((r) => Season.fromMap(r)).toList());
  }

  /// Takvimde işaretlenecek, maç olan günler (verilen ay için).
  Future<Set<int>> _loadMatchDays(int year, int month) async {
    try {
      final first = DateTime(year, month, 1);
      final last = DateTime(year, month + 1, 0);
      final rows = await Supabase.instance.client
          .from('matches')
          .select('match_date, league_id')
          .gte('match_date', _dateKey(first))
          .lte('match_date', _dateKey(last));
      final days = <int>{};
      for (final r in rows) {
        if (!_visibleLeagueIds.contains((r['league_id'] ?? '').toString())) {
          continue;
        }
        final d = DateTime.tryParse((r['match_date'] ?? '').toString());
        if (d != null) days.add(d.day);
      }
      return days;
    } catch (_) {
      return const <int>{};
    }
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final bugun = DateTime(now.year, now.month, now.day);
    _selectedDate = bugun;
    _rebuildDates(bugun);
    _activeLeagueId = GlobalFilter.leagueId.value;

    GlobalFilter.leagueId.addListener(_onGlobalFilterChanged);
    // Turnuva teması değişince tarih şeridi yeni renkle çizilsin.
    ActiveTournament.theme.addListener(_onThemeChanged);
  }

  void _onGlobalFilterChanged() {
    if (!mounted) return;
    setState(() {
      _activeLeagueId = GlobalFilter.leagueId.value ?? _activeLeagueId;
    });
  }

  /// Kişinin kendi turnuvalarından en yakın maçı olanı seçer
  /// (my_preferred_league). Fikstür, puan durumu ve istatistik bu ortak
  /// seçimle açılır. Kullanıcı bu arada kendisi seçim yaptıysa dokunulmaz.
  Future<void> _applyPreferredLeague(List<League> leagues) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || _preferredForUid == uid) return;
    _preferredForUid = uid;
    final before = GlobalFilter.leagueId.value;
    try {
      // Bantta seçilen turnuva (ActiveTournament) önce; yoksa en yakın maçı
      // olan kendi turnuvası.
      final pref =
          ActiveTournament.currentLeagueId.value ??
          (await Supabase.instance.client.rpc(
            'my_preferred_league',
          ))?.toString();
      if (!mounted || pref == null || pref.isEmpty) return;
      if (!leagues.any((l) => l.id == pref)) return;
      if (GlobalFilter.leagueId.value != before) return;
      setState(() => _activeLeagueId = pref);
      GlobalFilter.setLeague(pref);
    } catch (_) {}
  }

  /// Ana gezginin yan menüsünü açar (bu ekranın kendi Scaffold'u menüsüz).
  void _openMenu(BuildContext ctx) {
    ScaffoldState? scaffold = Scaffold.maybeOf(ctx);
    if (scaffold != null && !scaffold.hasDrawer) {
      scaffold = scaffold.context.findAncestorStateOfType<ScaffoldState>();
    }
    scaffold?.openDrawer();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    GlobalFilter.leagueId.removeListener(_onGlobalFilterChanged);
    ActiveTournament.theme.removeListener(_onThemeChanged);
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

  bool _bugunMu(DateTime t) {
    final n = DateTime.now();
    return t.year == n.year && t.month == n.month && t.day == n.day;
  }

  void _tarihSec(int index) {
    setState(() {
      _selectedDate = _tarihler[index];
      _rebuildDates(_selectedDate);
    });
  }

  void _rebuildDates(DateTime center) {
    final c = DateTime(center.year, center.month, center.day);
    _tarihler = List.generate(
      _yaricap * 2 + 1,
      (i) => c.add(Duration(days: i - _yaricap)),
      growable: true,
    );
    _seciliIndeks = 2;
  }

  void _setSelectedDate(DateTime date) {
    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day);
      _rebuildDates(_selectedDate);
    });
  }

  void _shiftDateWindow(int days) {
    final shifted = _tarihler
        .map((date) => date.add(Duration(days: days)))
        .toList();
    final selectedIndex = shifted.indexWhere(
      (date) =>
          date.year == _selectedDate.year &&
          date.month == _selectedDate.month &&
          date.day == _selectedDate.day,
    );
    setState(() {
      _tarihler = shifted;
      _seciliIndeks = selectedIndex;
    });
  }

  Future<void> _openModernCalendar() async {
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstYear: 2020,
      lastYear: DateTime.now().year + 5,
      markedDays: _loadMatchDays, // maç olan günlerde nokta
    );
    if (picked != null) _setSelectedDate(picked);
  }

  // YENİ EKLENEN: Erişim Kodu Soran Dialog
  Future<void> _showAccessCodeDialog(
    BuildContext parentContext,
    League league,
  ) async {
    final actualCode = (league.accessCode ?? '').trim().toLowerCase();
    final code = await showAdminTextInputDialog(
      context: parentContext,
      title: league.name,
      icon: Icons.lock_outline_rounded,
      subtitle: 'Bu turnuva gizlidir. Görüntülemek için erişim kodunu girin.',
      label: 'Erişim Kodu',
      fieldIcon: Icons.key_rounded,
      confirmLabel: 'GİRİŞ',
      validator: (v) {
        final entered = v.trim().toLowerCase();
        return entered.isNotEmpty && entered == actualCode
            ? null
            : 'Hatalı kod girdiniz.';
      },
    );
    if (code == null || !mounted) return;
    setState(() => _activeLeagueId = league.id);
    GlobalFilter.setLeague(league.id);
    if (parentContext.mounted) Navigator.pop(parentContext); // menüyü kapat
  }

  // YENİ EKLENEN: Özel Turnuva Seçici (Ortadan Açılan Ortak Dialog Tasarımı)
  // Turnuva filtresi kapalıyken kullanılmıyor; filtre tekrar açılınca
  // (bkz. build içindeki TURNUVA FİLTRESİ notu) yeniden kullanılacak.
  // ignore: unused_element
  void _showLeagueSelectionDialog(
    BuildContext context,
    List<League> leagues,
    bool isAdmin,
  ) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent, // Arka plan şeffaf
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1E293B), // Üst sol lacivert
                  Color(0xFF064E3B), // Alt sağ koyu zümrüt yeşili
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ), // Çok hafif çerçeve
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 15,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'Turnuva Seçin',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(color: Colors.white24),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: leagues.length,
                    separatorBuilder: (context, index) => const Divider(
                      color: Colors.white12,
                      height: 1,
                      indent: 24,
                      endIndent: 24,
                    ),
                    itemBuilder: (context, index) {
                      final l = leagues[index];
                      // Gizli ve admin değilse kilitli kabul et (özellik
                      // kapalıyken gizli turnuva yok sayılır).
                      final isLocked =
                          l.isPrivate &&
                          !isAdmin &&
                          AppSettings.privateLeaguesEnabled.value;
                      final isSelected = l.id == _activeLeagueId;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                        ),
                        leading: isLocked
                            ? const Icon(
                                Icons.lock_rounded,
                                color: Colors.white54,
                                size: 22,
                              )
                            : LeagueLogo(
                                url: l.logoUrl,
                                size: 26,
                                fallbackColor: isSelected
                                    ? const Color(0xFF10B981)
                                    : Colors.white70,
                              ),
                        title: Text(
                          l.name,
                          style: TextStyle(
                            color: isLocked
                                ? Colors.white54
                                : (isSelected
                                      ? const Color(0xFF10B981)
                                      : Colors.white),
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Color(0xFF10B981))
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onTap: () {
                          if (isLocked) {
                            Navigator.pop(context); // Önce seçiciyi kapat
                            _showAccessCodeDialog(
                              context,
                              l,
                            ); // Sonra erişim kodu ekranını aç
                          } else {
                            setState(() => _activeLeagueId = l.id);
                            GlobalFilter.setLeague(l.id);
                            ActiveTournament.noteViewed(l.id);
                            Navigator.pop(
                              context,
                            ); // Tıklandığı an popup kapanır
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          // Sade zemin; altta turnuvanın logosu silik filigran olarak.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF13203A), Color(0xFF0F172A)],
                ),
              ),
            ),
          ),
          if (!_calendar)
            Positioned(
              left: -40,
              right: -40,
              bottom: -60,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.06,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: (ActiveTournament.theme.value?.logoUrl ?? '').isEmpty
                        ? const FittedBox(child: AppLogo(size: 200))
                        : WebSafeImage(
                            url: ActiveTournament.theme.value!.logoUrl,
                            fit: BoxFit.contain,
                          ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: StreamBuilder<List<League>>(
              stream: _leagueService.watchLeagues(),
              builder: (context, leagueSnapshot) {
                if (!leagueSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final isAdmin = AppSession.of(context).value.isAdmin;

                // GÜNCELLENDİ: isPrivate olanları listede TUTUYORUZ (Kilitli göstermek için)
                final allLeagues = (leagueSnapshot.data ?? const <League>[]).where((
                  l,
                ) {
                  if (isAdmin) return true; // Admin her şeyi görür
                  if (!l.isActive) return false; // Pasif turnuvalar görünmez
                  return true; // isPrivate olanlar da gelsin, UI'da kilitleyeceğiz
                }).toList();

                if (allLeagues.isEmpty) {
                  return const Center(
                    child: Text(
                      'Görüntülenebilir turnuva yok.',
                      style: TextStyle(color: Colors.white),
                    ),
                  );
                }

                if (!_calendar &&
                    (!_didAutoSelectDefaultLeague ||
                        !allLeagues.any((l) => l.id == _activeLeagueId))) {
                  // Gizli turnuvalar yalnızca görme yetkisi olana gelir
                  // (veritabanı kuralı); burada ayrıca elenmez.
                  // Uygulamanın büründüğü turnuva (kişinin / misafirin son
                  // baktığı) önce; yoksa "varsayılan" işaretli turnuva.
                  final themed = ActiveTournament.currentLeagueId.value;
                  final def = allLeagues.any((l) => l.id == themed)
                      ? themed!
                      : allLeagues
                            .firstWhere(
                              (l) => l.isDefault,
                              orElse: () => allLeagues.first,
                            )
                            .id;
                  _activeLeagueId = def;
                  _didAutoSelectDefaultLeague = true;
                  // Dinleyiciler setState çağırır; build bittikten sonra yay.
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => GlobalFilter.setLeague(def),
                  );
                }

                final uid = Supabase.instance.client.auth.currentUser?.id;
                if (!_calendar && uid != null && uid != _preferredForUid) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _applyPreferredLeague(allLeagues),
                  );
                }

                final currentLeague = allLeagues.firstWhere(
                  (l) => l.id == _activeLeagueId,
                  orElse: () => allLeagues.first,
                );

                // Seçici gizliyken: kişinin görebildiği tüm aktif turnuvalar
                // (gizliler yetkisi/kodu olana zaten gelir); admin hepsini.
                _visibleLeagueIds = _calendar
                    ? {
                        for (final l in allLeagues)
                          if (isAdmin || l.isActive) l.id,
                      }
                    : _showLeagueFilter
                    ? {currentLeague.id}
                    : {
                        for (final l in allLeagues)
                          if (isAdmin || l.isActive) l.id,
                      };
                _leagueNameById = {for (final l in allLeagues) l.id: l.name};
                _leagueLogoById = {for (final l in allLeagues) l.id: l.logoUrl};
                _leaguePrimaryById = {
                  for (final l in allLeagues)
                    l.id: _themeColor(l.themePrimary, const Color(0xFF064E3B)),
                };
                _leagueSecondaryById = {
                  for (final l in allLeagues)
                    l.id: _themeColor(
                      l.themeSecondary,
                      const Color(0xFF10B981),
                    ),
                };

                if (kNewHomeDesign && !_calendar) {
                  return HomeDashboard(
                    key: ValueKey('dash_${currentLeague.id}'),
                    league: currentLeague,
                    onOpenMenu: () => _openMenu(context),
                  );
                }

                if (_calendar) {
                  return Column(
                    children: [
                      SizedBox(
                        height: 68,
                        child: Row(
                          children: [
                            // Menü: bantla aynı futbol topu düğmesi.
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: BandMenuButton(),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              tooltip: 'Önceki tarihler',
                              onPressed: () => _shiftDateWindow(-1),
                              icon: const Icon(
                                Icons.chevron_left_rounded,
                                color: Colors.white,
                              ),
                            ),
                            Expanded(
                              child: _TarihSeridi(
                                tarihler: _tarihler,
                                seciliIndeks: _seciliIndeks,
                                bugunMu: _bugunMu,
                                onSec: _tarihSec,
                                vurguRenk: cs.primary,
                                haftaKisa: _haftaKisa,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              tooltip: 'Sonraki tarihler',
                              onPressed: () => _shiftDateWindow(1),
                              icon: const Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.white,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: BandIconButton(
                                icon: Icons.calendar_month_rounded,
                                tooltip: 'Takvim',
                                onTap: _openModernCalendar,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: _buildMatchList(context, currentLeague)),
                    ],
                  );
                }

                // Tek satırlık üst bant: durum çubuğu + 60px tarih şeridi.
                final headerHeight = MediaQuery.of(context).padding.top + 80;

                return Stack(
                  children: [
                    // 1. KATMAN: YEŞİL ARKA PLAN
                    Container(
                      height: headerHeight + 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          // Turnuva temalıysa şerit turnuvanın renginde.
                          colors: [
                            (ActiveTournament.theme.value?.primary ??
                                    const Color(0xFF064E3B))
                                .withValues(alpha: 0.95),
                            (ActiveTournament.theme.value?.primary ??
                                    const Color(0xFF064E3B))
                                .withValues(alpha: 0.6),
                          ],
                        ),
                      ),
                    ),

                    // 2. KATMAN: ANA LİSTE
                    Column(
                      children: [
                        SizedBox(height: headerHeight),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF0F172A,
                              ).withValues(alpha: 0.30),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(24),
                              ),
                            ),
                            child: Column(
                              children: [
                                if (!_calendar) const HomeNewsCard(),
                                Expanded(
                                  child: _buildMatchList(
                                    context,
                                    currentLeague,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    // 3. KATMAN: ETKİLEŞİMLİ PANEL (HEADER BUTONLARI)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          4,
                          MediaQuery.of(context).padding.top + 6,
                          4,
                          8,
                        ),
                        // Tek satır: menü · ‹ · tarih şeridi · › · takvim
                        child: Row(
                          children: [
                            Builder(
                              builder: (ctx) => IconButton(
                                tooltip: 'Menü',
                                icon: const Icon(
                                  Icons.menu,
                                  color: Colors.white,
                                  size: 26,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black87,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                onPressed: () {
                                  ScaffoldState? scaffold = Scaffold.maybeOf(
                                    ctx,
                                  );
                                  if (scaffold != null && !scaffold.hasDrawer) {
                                    scaffold = scaffold.context
                                        .findAncestorStateOfType<
                                          ScaffoldState
                                        >();
                                  }
                                  scaffold?.openDrawer();
                                },
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              onPressed: () => _setSelectedDate(
                                _selectedDate.subtract(const Duration(days: 1)),
                              ),
                              icon: Icon(
                                Icons.chevron_left_rounded,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                            Expanded(
                              child: _TarihSeridi(
                                tarihler: _tarihler,
                                seciliIndeks: _seciliIndeks,
                                bugunMu: _bugunMu,
                                onSec: _tarihSec,
                                vurguRenk: cs.primary,
                                haftaKisa: _haftaKisa,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              onPressed: () => _setSelectedDate(
                                _selectedDate.add(const Duration(days: 1)),
                              ),
                              icon: Icon(
                                Icons.chevron_right_rounded,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Maç Takvimi',
                              onPressed: _openModernCalendar,
                              icon: Icon(
                                Icons.calendar_month_outlined,
                                color: cs.onPrimaryContainer,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black87,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // TURNUVA FİLTRESİ (şimdilik kapalı)
                    // Ana sayfa şu an tüm turnuvaların maçlarını gösteriyor.
                    // Tekrar açmak için: dosyanın başındaki
                    // `_showLeagueFilter` değerini true yapın ve aşağıdaki
                    // bloğu yorumdan çıkarıp başlık satırındaki menü ikonunun
                    // yanına (tarih şeridinin yerine veya üstüne) ekleyin.
                    //
                    // Expanded(
                    //   child: InkWell(
                    //     onTap: () => _showLeagueSelectionDialog(
                    //       context,
                    //       allLeagues,
                    //       isAdmin,
                    //     ),
                    //     borderRadius: BorderRadius.circular(8),
                    //     child: Padding(
                    //       padding: const EdgeInsets.symmetric(vertical: 8.0),
                    //       child: Row(
                    //         mainAxisSize: MainAxisSize.min,
                    //         children: [
                    //           Flexible(
                    //             child: Text(
                    //               currentLeague.name,
                    //               style: TextStyle(
                    //                 color: cs.onPrimaryContainer,
                    //                 fontWeight: FontWeight.w800,
                    //                 fontSize: 20,
                    //               ),
                    //               overflow: TextOverflow.ellipsis,
                    //             ),
                    //           ),
                    //           const SizedBox(width: 4),
                    //           Icon(
                    //             Icons.keyboard_arrow_down_rounded,
                    //             color: cs.onPrimaryContainer,
                    //           ),
                    //         ],
                    //       ),
                    //     ),
                    //   ),
                    // ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Takımlar bir kez dinlenir (her rebuild'de yeniden sorgulanmaz).
  late final Stream<List<Team>> _teamsStream = resilientStream(
    () => _teamService.watchAllTeams(caller: 'HomeScreen'),
  );

  Widget _buildMatchList(BuildContext context, League currentLeague) {
    return StreamBuilder<List<Team>>(
      stream: _teamsStream,
      builder: (context, teamSnapshot) {
        // Takım adları gelmeden kartlar çizilmez; aksi halde önce
        // "Ev Sahibi / Deplasman" görünüp sonra adlar geliyordu.
        if (!teamSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final Map<String, String> logoMap = {};
        final Map<String, String> nameMap = {};
        if (teamSnapshot.hasData) {
          for (final t in teamSnapshot.data!) {
            logoMap[t.id] = t.logoUrl;
            nameMap[t.id] = t.name;
          }
        }

        return StreamBuilder<List<Season>>(
          stream: _showLeagueFilter
              ? (_activeLeagueId == null
                    ? const Stream<List<Season>>.empty()
                    : _watchSeasons(_activeLeagueId!))
              : _allSeasonsStream,
          builder: (context, seasonsSnap) {
            final seasons = seasonsSnap.data ?? const <Season>[];

            if (_showLeagueFilter &&
                seasons.isNotEmpty &&
                GlobalFilter.seasonId.value == null) {
              final defaultSeason = pickDefaultSeasonId(seasons);

              WidgetsBinding.instance.addPostFrameCallback((_) {
                GlobalFilter.setSeason(defaultSeason);
              });
            }

            final seasonLeagueById = <String, String>{
              for (final s in seasons) s.id: s.leagueId,
            };

            return StreamBuilder<List<MatchModel>>(
              stream: !_showLeagueFilter
                  ? _matchesOnDateStream(_selectedDate)
                  : _activeLeagueId == null
                  ? const Stream<List<MatchModel>>.empty()
                  : _matchService.watchMatchesByDate(
                      leagueId: _activeLeagueId!,
                      date: _selectedDate,
                    ),
              builder: (context, matchSnapshot) {
                if (matchSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final matches = matchSnapshot.data ?? [];
                matches.sort((a, b) {
                  final timeA = (a.matchTime ?? '').trim();
                  final timeB = (b.matchTime ?? '').trim();

                  if (timeA.isEmpty && timeB.isEmpty) return 0;
                  if (timeA.isEmpty) return 1;
                  if (timeB.isEmpty) return -1;

                  return timeA.compareTo(timeB);
                });

                if (matches.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.event_busy_rounded,
                          size: 64,
                          color: Colors.white24,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Bu tarihte maç bulunamadı.',
                          style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _groupsStream,
                  builder: (context, groupsSnap) {
                    final groupRows =
                        groupsSnap.data ?? const <Map<String, dynamic>>[];
                    final groupNameById = <String, String>{};
                    final groupCountBySeason = <String, int>{};
                    for (final g in groupRows) {
                      final gid = (g['id'] ?? '').toString();
                      final sid = (g['season_id'] ?? '').toString();
                      groupNameById[gid] = (g['name'] ?? '').toString().trim();
                      groupCountBySeason[sid] =
                          (groupCountBySeason[sid] ?? 0) + 1;
                    }

                    // Bölümler grup varsa sezon+grup, yoksa yalnızca sezondur.
                    String sectionKey(MatchModel m) {
                      final sid = m.seasonId;
                      final gid = (m.groupId ?? '').trim();
                      return gid.isNotEmpty ? '$sid|$gid' : sid;
                    }

                    final Map<String, List<MatchModel>> sectionMap = {};
                    for (final m in matches) {
                      (sectionMap[sectionKey(m)] ??= []).add(m);
                    }

                    String leagueNameOf(String key) {
                      final m = sectionMap[key]!.first;
                      final leagueId =
                          seasonLeagueById[key.split('|').first] ?? m.leagueId;
                      return _leagueNameById[leagueId] ?? currentLeague.name;
                    }

                    // Sezonda tek grup varsa boş döner.
                    String groupNameOf(String key) {
                      final parts = key.split('|');
                      if (parts.length < 2 ||
                          (groupCountBySeason[parts.first] ?? 0) <= 1) {
                        return '';
                      }
                      return groupNameById[parts[1]] ?? '';
                    }

                    String titleOf(String key) =>
                        '${leagueNameOf(key)} ${groupNameOf(key)}';

                    final sortedKeys = sectionMap.keys.toList()
                      ..sort(
                        (a, b) => titleOf(
                          a,
                        ).toUpperCase().compareTo(titleOf(b).toUpperCase()),
                      );

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                      children: sortedKeys.map((key) {
                        final sId = key.split('|').first;
                        // Bölümün turnuvası: tüm turnuvalar gösterilirken
                        // sezonun bağlı olduğu turnuva.
                        final sectionLeagueId =
                            seasonLeagueById[sId] ??
                            sectionMap[key]!.first.leagueId;
                        final leagueText = leagueNameOf(key);
                        final groupText = groupNameOf(key);
                        void openSection() {
                          GlobalFilter.setLeague(sectionLeagueId);
                          GlobalFilter.setSeason(sId);
                          ActiveTournament.noteViewed(sectionLeagueId);
                          TournamentHubScreen.open(
                            context,
                            leagueId: sectionLeagueId,
                            seasonId: sId,
                            groupId: key.contains('|')
                                ? key.split('|').last
                                : null,
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!_calendar)
                              InkWell(
                                onTap: openSection,
                                borderRadius: BorderRadius.circular(12),
                                child: _LeagueSectionHeader(
                                  logoUrl: _leagueLogoById[sectionLeagueId],
                                  title: leagueText,
                                  subtitle: groupText,
                                ),
                              ),
                            ...sectionMap[key]!.asMap().entries.map((entry) {
                              final m = entry.value;
                              return _MatchCard(
                                match: m,
                                homeLogo: logoMap[m.homeTeamId] ?? '',
                                awayLogo: logoMap[m.awayTeamId] ?? '',
                                homeName:
                                    (nameMap[m.homeTeamId] ?? '').trim().isEmpty
                                    ? 'Ev Sahibi'
                                    : (nameMap[m.homeTeamId] ?? '').trim(),
                                awayName:
                                    (nameMap[m.awayTeamId] ?? '').trim().isEmpty
                                    ? 'Deplasman'
                                    : (nameMap[m.awayTeamId] ?? '').trim(),
                                sectionTitle: _calendar && entry.key == 0
                                    ? leagueText
                                    : null,
                                sectionLogoUrl:
                                    _leagueLogoById[sectionLeagueId],
                                sectionSubtitle: groupText,
                                sectionPrimary:
                                    _leaguePrimaryById[sectionLeagueId] ??
                                    const Color(0xFF064E3B),
                                sectionAccent:
                                    _leagueSecondaryById[sectionLeagueId] ??
                                    const Color(0xFF10B981),
                                compact: _calendar,
                                onTapSection: openSection,
                              );
                            }),
                          ],
                        );
                      }).toList(),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _MatchCard extends StatefulWidget {
  final MatchModel match;
  final String homeLogo;
  final String awayLogo;
  final String homeName;
  final String awayName;
  final String? sectionTitle;
  final String? sectionLogoUrl;
  final String sectionSubtitle;
  final Color sectionPrimary;
  final Color sectionAccent;
  final bool compact;

  final VoidCallback? onTapSection;
  const _MatchCard({
    required this.match,
    required this.homeLogo,
    required this.awayLogo,
    required this.homeName,
    required this.awayName,
    this.sectionTitle,
    this.sectionLogoUrl,
    this.sectionSubtitle = '',
    this.sectionPrimary = const Color(0xFF064E3B),
    this.sectionAccent = const Color(0xFF10B981),
    this.compact = false,
    this.onTapSection,
  });

  @override
  State<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<_MatchCard> {
  String? _broadcastUrl;

  @override
  void initState() {
    super.initState();
    _checkBroadcast();
  }

  Future<void> _checkBroadcast() async {
    final url = await ServiceLocator.matchService.getBroadcastUrl(
      widget.match.id,
    );
    if (mounted && url != _broadcastUrl) {
      setState(() => _broadcastUrl = url);
    }
  }

  @override
  void didUpdateWidget(covariant _MatchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.match.id != widget.match.id) {
      _broadcastUrl = null;
      _checkBroadcast();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;

    return Card(
      margin: EdgeInsets.only(bottom: widget.compact ? 5 : 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(widget.compact ? 10 : 16),
      ),
      color: const Color(0xFF1E293B).withValues(alpha: 0.78),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  MatchDetailsScreen(match: widget.match, isAdmin: isAdmin),
            ),
          );
          _checkBroadcast(); // Geri dönüldüğünde ikonu güncelle
        },
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 7 : 8,
            vertical: widget.compact ? 6 : 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.sectionTitle != null) ...[
                InkWell(
                  onTap: widget.onTapSection,
                  borderRadius: BorderRadius.circular(7),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.compact ? 7 : 8,
                      vertical: widget.compact ? 5 : 7,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color.lerp(
                            widget.sectionPrimary,
                            Colors.black,
                            0.58,
                          )!,
                          Color.lerp(
                            widget.sectionPrimary,
                            const Color(0xFF0B1220),
                            0.76,
                          )!,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: widget.sectionAccent.withValues(alpha: 0.42),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (widget.compact)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: LeagueLogo(
                              url: widget.sectionLogoUrl ?? '',
                              size: 18,
                              fallbackColor: widget.sectionAccent,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            widget.sectionTitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: widget.compact ? 12 : 13,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Barlow',
                            ),
                          ),
                        ),
                        if (widget.sectionSubtitle.trim().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 96),
                            child: Text(
                              widget.sectionSubtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: Color.lerp(
                                  Colors.white,
                                  widget.sectionAccent,
                                  0.56,
                                ),
                                fontSize: widget.compact ? 9.5 : 11,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Barlow',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                SizedBox(height: widget.compact ? 4 : 8),
              ],
              MatchScoreLine(
                match: widget.match,
                homeName: widget.homeName,
                awayName: widget.awayName,
                homeLogo: widget.homeLogo,
                awayLogo: widget.awayLogo,
                showLogos: widget.compact,
                compact: widget.compact,
                leading:
                    _broadcastUrl == null ||
                        widget.match.status == MatchStatus.finished
                    ? null
                    : InkWell(
                        onTap: () => openYoutubeInApp(context, _broadcastUrl!),
                        child: const YoutubeBrandIcon(size: 18),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TarihSeridi extends StatelessWidget {
  const _TarihSeridi({
    required this.tarihler,
    required this.seciliIndeks,
    required this.bugunMu,
    required this.onSec,
    required this.vurguRenk,
    required this.haftaKisa,
  });
  final List<DateTime> tarihler;
  final int seciliIndeks;
  final bool Function(DateTime) bugunMu;
  final void Function(int) onSec;
  final Color vurguRenk;
  final List<String> haftaKisa;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Row(
        children: List.generate(tarihler.length, (index) {
          final t = tarihler[index];
          final secili = index == seciliIndeks;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSec(index),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: secili
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Dar ekranlarda yazılar bölünmez, gerekirse küçülür.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        bugunMu(t) ? 'Bugün' : haftaKisa[t.weekday - 1],
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          color: secili ? Colors.white : Colors.white60,
                          fontWeight: FontWeight.bold,
                          shadows: const [
                            Shadow(
                              color: Colors.black87,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}',
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          shadows: [
                            Shadow(
                              color: Colors.black87,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Ana sayfadaki turnuva başlığı: kartın kenarından taşan büyük logo rozeti,
/// turnuva adı ve altında grup / hafta bilgisi.
class _LeagueSectionHeader extends StatelessWidget {
  const _LeagueSectionHeader({
    required this.logoUrl,
    required this.title,
    required this.subtitle,
  });

  final String? logoUrl;
  final String title;
  final String subtitle;

  static const _gold = Color(0xFFE2B845);
  static const _badge = 58.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Rozet kartın solundan taşar; ona yer açılır.
      padding: const EdgeInsets.only(top: 16, bottom: 10, left: 12),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.fromLTRB(_badge - 4, 10, 8, 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xF21B2A6B), Color(0xF20B1220)],
                stops: [0, 0.7],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _gold.withValues(alpha: 0.55),
                width: 1.2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          height: 1.2,
                          letterSpacing: 0.2,
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
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white54,
                  size: 20,
                ),
              ],
            ),
          ),
          // Altın ışımalı rozet.
          Positioned(
            left: -14,
            child: Container(
              width: _badge + 8,
              height: _badge + 8,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _gold.withValues(alpha: 0.38),
                    _gold.withValues(alpha: 0),
                  ],
                ),
              ),
              child: LeagueLogo(
                url: logoUrl,
                size: _badge - 6,
                fallbackColor: _gold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
