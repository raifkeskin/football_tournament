import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;

import '../../../core/services/app_session.dart';
import '../../auth/screens/login_screen.dart';
import '../../../core/services/active_tournament.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/services/league_access.dart';
import '../../team/screens/standings_list_screen.dart';
import 'home_screen.dart';
import '../../player/screens/profile_screen.dart';
import '../../../core/widgets/app_name_band.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/design_flags.dart';
import '../../../core/widgets/admin_page.dart';

/// Sol yan menü (Drawer) ile ana ekranlar arasında geçiş.
class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key, this.initialTabIndex = 0});

  /// Profil sekmesinin sırası (girişten sonra doğrudan açılır).
  static const int profileTab = 4;

  /// Ana gezginin Scaffold'u: yan menü bant gibi gezgin dışındaki
  /// parçalardan da açılabilsin.
  ///
  /// Anahtar her gezginin kendisine aittir: girişten sonra yeni gezgin açılırken
  /// eskisi geçiş bitene kadar ağaçta kalır; ortak (static) anahtar iki
  /// Scaffold'a birden verilince yeni sayfa boş kalıyordu.
  static GlobalKey<ScaffoldState>? _activeScaffoldKey;

  /// Yan menüyü açar (ör. yönetim panelinde bantaki ☰).
  static void openMenu() => _activeScaffoldKey?.currentState?.openDrawer();

  /// Gezgin dışından sekme değiştirme isteği (ör. canlı kura → Fikstür).
  static final tabRequest = ValueNotifier<int?>(null);

  /// Takvimli maçlar sekmesinin sırası.
  static const int fixtureTab = 1;

  /// Yayın Rehberi sekmesinin sırası.
  static const int broadcastTab = 3;

  final int initialTabIndex;

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  late int _aktifSekme = widget.initialTabIndex;

  @override
  void initState() {
    super.initState();
    MainNavigator._activeScaffoldKey = _scaffoldKey;
    LeagueSwitchScope.openMenu = MainNavigator.openMenu;
    MainNavigator.tabRequest.addListener(_onTabRequest);
    AppSettings.bottomNavEnabled.addListener(_onSettings);
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  /// Bu gezginin sayfası (bant turnuva seçicisini yalnızca bu sayfa en
  /// üstteyken gösterir).
  ModalRoute<dynamic>? _route;

  @override
  void dispose() {
    if (MainNavigator._activeScaffoldKey == _scaffoldKey) {
      MainNavigator._activeScaffoldKey = null;
    }
    MainNavigator.tabRequest.removeListener(_onTabRequest);
    AppSettings.bottomNavEnabled.removeListener(_onSettings);
    LeagueSwitchScope.clearHome(_route);
    super.dispose();
  }

  void _onTabRequest() {
    final i = MainNavigator.tabRequest.value;
    if (i == null || !mounted) return;
    setState(() => _aktifSekme = i);
    MainNavigator.tabRequest.value = null;
  }

  /// Yan menüyü kaydırma hareketinden açmak için.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _sekmeDegistir(int index) {
    setState(() {
      _aktifSekme = index;
    });
    // Menüden bir sayfa seçildiğinde çekmeceyi (Drawer) otomatik kapat
    Navigator.of(context).pop();
  }

  Future<void> _cikisYap(AppSessionController session) async {
    Navigator.of(context).pop(); // çekmeceyi kapat
    // Önce giriş ekranı (misafir seçeneğiyle), sonra oturum kapanır: kapanış
    // anında ana sayfanın misafir olarak yeniden çizildiği ara görüntü
    // kullanıcıya görünmez.
    final nav = Navigator.of(context, rootNavigator: true);
    await GuestMode.set(false);
    nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen(gate: true)),
      (route) => false,
    );
    await session.signOut();
  }

  /// Geri (Android'de kenardan kaydırma dahil): başka sekmedeyken Ana
  /// Sayfa'ya döner; Ana Sayfa'da yanlışlıkla çıkılmasın diye onay sorar.
  /// Bu kapsam, Profil'deki geri dinleyicisinden önce kayıtlı olduğu için
  /// önce çalışır.
  Future<void> _onBack() async {
    if (_aktifSekme != 0) {
      setState(() => _aktifSekme = 0);
      return;
    }
    if (kIsWeb) return;
    final exit = await showAdminConfirmDialog(
      context: context,
      title: 'Uygulamadan Çık',
      message: 'Uygulamadan çıkmak istiyor musunuz?',
      confirmLabel: 'ÇIKIŞ',
      icon: Icons.exit_to_app_rounded,
    );
    if (exit) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context);
    _route = ModalRoute.of(context);
    // Turnuva seçicisi yalnızca ana sekmelerde (Profil / yönetim panelinde
    // değil).
    LeagueSwitchScope.setHome(
      _route,
      // Turnuva seçici yalnızca Ana Sayfa'da.
      mainTab: _aktifSekme == 0,
      panelTab:
          _aktifSekme == MainNavigator.profileTab &&
          session.value.hasManagementPanel,
      homeTab: _aktifSekme == 0,
      calendarTab:
          _aktifSekme == MainNavigator.fixtureTab ||
          _aktifSekme == MainNavigator.broadcastTab,
    );
    final user = session.value.user;
    final loggedIn = user != null && !user.isAnonymous;
    final ekranlar = <Widget>[
      const HomeScreen(),
      const HomeScreen(showCalendar: true),
      const StandingsListScreen(),
      const HomeScreen(broadcastOnly: true),
      ProfileScreen(
        onRequestHomeTab: () {
          setState(() {
            _aktifSekme = 0;
          });
        },
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        onDrawerChanged: LeagueSwitchScope.setDrawerOpen,
        extendBody: !kNewHomeDesign,
        // Alt çubuk yok: admin ayarı kapalıysa ya da Profil sekmesinde yönetim
        // paneli / giriş formu açıkken (gezinme bantaki ya da yan menüden).
        bottomNavigationBar:
            kNewHomeDesign &&
                AppSettings.bottomNavEnabled.value &&
                !(_aktifSekme == MainNavigator.profileTab &&
                    (session.value.hasManagementPanel || !loggedIn))
            ? _BottomBar(
                index: _aktifSekme,
                onTap: (i) => setState(() => _aktifSekme = i),
              )
            : null,
        drawer: _MenuDrawer(
          activeIndex: _aktifSekme,
          session: session.value,
          loggedIn: loggedIn,
          onSelect: _sekmeDegistir,
          onLogout: () => _cikisYap(session),
          onEnterCode: () {
            Navigator.of(context).pop(); // çekmeceyi kapat
            showLeagueCodeDialog(this.context);
          },
        ),
        // Görülebilen turnuvalar değişince (giriş/çıkış, kod) ekranlar
        // baştan kurulur ve verilerini yeniden okur.
        body: ValueListenableBuilder<int>(
          valueListenable: LeagueAccess.dataEpoch,
          builder: (context, epoch, _) => KeyedSubtree(
            key: ValueKey('data_$epoch'),
            // Ana sekmeler parmakla kaydırılır (Ana Sayfa → Maç Takvimi →
            // Puan Durumu → Yayın Rehberi); Profil menüden açılır ve
            // sekmelerin üstünde durur. Haberler ve İstatistik Turnuva
            // Sayfası'nda.
            child: Stack(
              children: [
                _TabPager(
                  index: _aktifSekme < MainNavigator.profileTab
                      ? _aktifSekme
                      : null,
                  onChanged: (i) => setState(() => _aktifSekme = i),
                  onSwipePastFirst: () =>
                      _scaffoldKey.currentState?.openDrawer(),
                  children: ekranlar.take(MainNavigator.profileTab).toList(),
                ),
                Offstage(
                  offstage: _aktifSekme != MainNavigator.profileTab,
                  child: TickerMode(
                    enabled: _aktifSekme == MainNavigator.profileTab,
                    child: ekranlar[MainNavigator.profileTab],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Yeni tasarımın alt gezinme çubuğu (Profil yan menüde kalır). İkonlar yan
/// menüdekiyle aynı renkli kutular: seçili olan tam renkli ve büyük, diğerleri
/// soluk.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    const items = _MenuDrawer._items;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: _BottomItem(
                      icon: items[i].$1,
                      label: items[i].$2,
                      colors: items[i].$3,
                      selected: i == index,
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

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.icon,
    required this.label,
    required this.colors,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final List<Color> colors;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final size = selected ? 34.0 : 28.0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(selected ? 10 : 8),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                for (final c in colors)
                  selected ? c : c.withValues(alpha: 0.38),
              ],
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: colors.last.withValues(alpha: 0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: selected ? 20 : 17,
            color: selected ? Colors.white : Colors.white70,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? Colors.white : Colors.white54,
          ),
        ),
      ],
    );
  }
}

/// Kaydırılabilir ana sekmeler. Sayfalar açık kalır (sekmeye dönünce
/// yeniden yüklenmez). İlk sekmede sağa kaydırmak yan menüyü açar.
class _TabPager extends StatefulWidget {
  const _TabPager({
    required this.index,
    required this.onChanged,
    required this.onSwipePastFirst,
    required this.children,
  });

  /// Gösterilecek sekme; null ise (Profil açık) sayfa yerinde kalır.
  final int? index;
  final ValueChanged<int> onChanged;
  final VoidCallback onSwipePastFirst;
  final List<Widget> children;

  @override
  State<_TabPager> createState() => _TabPagerState();
}

class _TabPagerState extends State<_TabPager> {
  late final PageController _controller = PageController(
    initialPage: widget.index ?? 0,
  );

  /// Bir sürükleme boyunca menü yalnızca bir kez açılsın.
  bool _drawerFired = false;

  /// Kod ile sayfa atlatılıyor (alt çubuk / menü): PageView bunu sayfa
  /// değişikliği olarak bildirir, ama sekme zaten seçili; çizim sırasında
  /// üst gezgine setState yaptırmamak için bildirim yutulur.
  bool _jumping = false;

  @override
  void didUpdateWidget(covariant _TabPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    final i = widget.index;
    if (i != null && _controller.hasClients) {
      final current = _controller.page?.round();
      if (current != i) {
        _jumping = true;
        try {
          _controller.jumpToPage(i);
        } finally {
          _jumping = false;
        }
      }
    }
  }

  void _onPageChanged(int i) {
    if (_jumping) return;
    widget.onChanged(i);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    // Yalnızca sekmelerin kendi kaydırması (iç listeler değil).
    if (n.depth != 0 || n.metrics.axis != Axis.horizontal) return false;
    if (n is ScrollStartNotification) _drawerFired = false;
    if (n is OverscrollNotification &&
        n.overscroll < 0 &&
        n.metrics.pixels <= n.metrics.minScrollExtent &&
        !_drawerFired) {
      _drawerFired = true;
      widget.onSwipePastFirst();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: PageView(
        controller: _controller,
        physics: const ClampingScrollPhysics(),
        // Yandaki sekme önceden hazırlanır: kaydırınca boş ekran görünmez.
        allowImplicitScrolling: true,
        onPageChanged: _onPageChanged,
        children: [for (final c in widget.children) _KeepAlive(child: c)],
      ),
    );
  }
}

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

/// Yan menü: üstte turnuva kartı (logo, ad, sosyal simgeler), arkada silik
/// turnuva logosu, renkli ikonlu bölümler; altta giriş yapan kişinin kartı
/// (dokununca profil) ve çıkış. Fotoğraf yok: anında açılır.
class _MenuDrawer extends StatelessWidget {
  const _MenuDrawer({
    required this.activeIndex,
    required this.session,
    required this.loggedIn,
    required this.onSelect,
    required this.onLogout,
    required this.onEnterCode,
  });

  final int activeIndex;
  final AppSessionState session;
  final bool loggedIn;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;
  final VoidCallback onEnterCode;

  static const _ground = Color(0xFF0F172A);
  static const _surface = Color(0xFF1E293B);

  /// (ikon, ad, renk geçişi) — her bölümün kendi rengi.
  static const _items = [
    (Icons.home_rounded, 'Ana Sayfa', [Color(0xFF22C55E), Color(0xFF15803D)]),
    (
      Icons.calendar_month_rounded,
      'Maç Takvimi',
      [Color(0xFF60A5FA), Color(0xFF2563EB)],
    ),
    (
      Icons.emoji_events_rounded,
      'Puan Durumu',
      [Color(0xFFFCD34D), Color(0xFFD97706)],
    ),
    (
      Icons.live_tv_rounded,
      'Yayın Rehberi',
      [Color(0xFFFB7185), Color(0xFFE11D48)],
    ),
    // Haberler ve İstatistik şimdilik menüde yok (Turnuva Sayfası'nda).
  ];

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      // Instagram / YouTube varsa kendi uygulamasında açılır.
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TournamentTheme?>(
      valueListenable: ActiveTournament.theme,
      builder: (context, t, _) {
        final primary = t?.primary ?? const Color(0xFF064E3B);
        final accent = t?.secondary ?? const Color(0xFF10B981);
        final logo = (t?.logoUrl ?? '').trim();
        return Drawer(
          backgroundColor: _ground,
          elevation: 0,
          shape: const RoundedRectangleBorder(),
          child: Stack(
            children: [
              // Zemin: turnuva renginden koyuya.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, 0.55],
                      colors: [Color.lerp(primary, _ground, 0.55)!, _ground],
                    ),
                  ),
                ),
              ),
              // Silik turnuva logosu (bantta zaten indirilmiş olan).
              if (logo.isNotEmpty)
                Positioned(
                  right: -50,
                  bottom: 60,
                  width: 260,
                  height: 260,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.07,
                      child: WebSafeImage(url: logo, fit: BoxFit.contain),
                    ),
                  ),
                ),
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(t, primary, accent, logo),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        children: [
                          for (var i = 0; i < _items.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _item(i, accent),
                            ),
                        ],
                      ),
                    ),
                    if (AppSettings.privateLeaguesEnabled.value)
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: accent),
                        icon: const Icon(Icons.key_rounded, size: 20),
                        label: const Text(
                          'Turnuva Kodu Gir',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: onEnterCode,
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                      child: loggedIn
                          ? _userBlock(accent)
                          : _loginButton(accent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(TournamentTheme? t, Color primary, Color accent, String logo) {
    final links = [
      if ((t?.instagramUrl ?? '').isNotEmpty)
        (
          Icons.camera_alt_rounded,
          const Color(0xFFE1306C),
          t!.instagramUrl,
          'Instagram',
        ),
      if ((t?.facebookUrl ?? '').isNotEmpty)
        (Icons.facebook, const Color(0xFF1877F2), t!.facebookUrl, 'Facebook'),
      if ((t?.youtubeUrl ?? '').isNotEmpty)
        (
          Icons.smart_display_rounded,
          const Color(0xFFFF0000),
          t!.youtubeUrl,
          'YouTube',
        ),
      if ((t?.websiteUrl ?? '').isNotEmpty)
        (
          Icons.language_rounded,
          const Color(0xFF64748B),
          t!.websiteUrl,
          'Web sitesi',
        ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, Color.lerp(primary, _ground, 0.6)!],
        ),
        border: Border(bottom: BorderSide(color: accent, width: 2)),
      ),
      child: Row(
        children: [
          if (logo.isNotEmpty)
            WebSafeImage(url: logo, width: 54, height: 54, fit: BoxFit.contain)
          else
            const AppLogo(size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t?.name ?? (kShowAppName ? kAppName : 'Turnuva'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                if (links.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final (icon, color, url, label) in links)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Material(
                            color: color,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => _open(url),
                              child: SizedBox(
                                width: 32,
                                height: 32,
                                child: Icon(
                                  icon,
                                  size: 18,
                                  color: Colors.white,
                                  semanticLabel: label,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(int i, Color accent) {
    final (icon, label, colors) = _items[i];
    final selected = activeIndex == i;
    return Material(
      color: selected ? Color.lerp(_surface, accent, 0.16) : _surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => onSelect(i),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? accent : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Giriş yapan kişi: kartına dokununca profil; altında çıkış.
  Widget _userBlock(Color accent) {
    final name = (session.displayName ?? '').trim();
    final photo = (session.photoUrl ?? '').trim();
    final selected = activeIndex == MainNavigator.profileTab;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: selected ? Color.lerp(_surface, accent, 0.16) : _surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onSelect(MainNavigator.profileTab),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? accent
                      : Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent,
                    ),
                    child: photo.isNotEmpty
                        ? WebSafeImage(
                            url: photo,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                          )
                        : Text(
                            name.isEmpty ? '?' : name.characters.first,
                            style: TextStyle(
                              color: accent.computeLuminance() > 0.45
                                  ? const Color(0xFF0B1220)
                                  : Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? 'Profilim' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white38,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFCA5A5),
            side: BorderSide(
              color: const Color(0xFFF87171).withValues(alpha: 0.4),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.logout_rounded, size: 20),
          label: const Text(
            'Çıkış Yap',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: onLogout,
        ),
      ],
    );
  }

  Widget _loginButton(Color accent) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: accent.computeLuminance() > 0.45
            ? const Color(0xFF0B1220)
            : Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.login_rounded, size: 20),
      label: const Text(
        'Giriş Yap',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      onPressed: () => onSelect(MainNavigator.profileTab),
    );
  }
}
