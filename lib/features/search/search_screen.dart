import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/active_tournament.dart';
import '../../core/services/app_session.dart';
import '../../core/services/app_settings.dart';
import '../../core/services/follows.dart';
import '../../core/services/league_access.dart';
import '../../core/widgets/admin_page.dart';
import '../../core/widgets/web_safe_image.dart';
import '../player/widgets/player_card.dart';
import '../team/screens/team_squad_screen.dart';

/// Takım ve futbolcu araması. Bantta büyüteç ana sayfada arama çubuğunu
/// açıp kapatır; çubuğa dokununca [SearchScreen]. Yeni özellik: admin her
/// zaman, diğerleri search_enabled açıksa.
class HomeSearch {
  HomeSearch._();

  static final open = ValueNotifier<bool>(false);

  static bool visible(BuildContext context) {
    if (AppSettings.searchEnabled.value) return true;
    try {
      return AppSession.of(context).value.isAdmin;
    } catch (_) {
      return false;
    }
  }
}

/// Ana sayfada bandın altında açılıp kapanan arama çubuğu.
class HomeSearchBar extends StatelessWidget {
  const HomeSearchBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        HomeSearch.open,
        AppSettings.searchEnabled,
      ]),
      builder: (context, _) {
        final show = HomeSearch.open.value && HomeSearch.visible(context);
        return AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: !show
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                  child: Material(
                    color: const Color(0xFF131D33),
                    shape: const StadiumBorder(
                      side: BorderSide(color: Color(0xFF2B3954), width: 1.5),
                    ),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: () => SearchScreen.open(context),
                      child: const SizedBox(
                        height: 48,
                        child: Row(
                          children: [
                            SizedBox(width: 16),
                            Icon(
                              Icons.search_rounded,
                              color: Color(0xFF34D399),
                              size: 22,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Turnuva, takım ya da futbolcu ara',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _Hit {
  const _Hit({
    required this.id,
    required this.name,
    required this.sub,
    required this.image,
    this.seasonId = '',
    required this.kind,
    this.locked = false,
  });

  final String id;
  final String name;
  final String sub;
  final String image;
  final String seasonId;
  final FollowKind kind;

  /// Gizli turnuva, kişinin erişimi yok (kod gerekir).
  final bool locked;
  bool get player => kind == FollowKind.player;
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'SearchScreen'),
      builder: (_) => const SearchScreen(),
    ),
  );

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _green = Color(0xFF34D399);
  static const _muted = Color(0xFF94A3B8);
  static const _kRecent = 'search_recent_v1';

  final _ctrl = TextEditingController();
  Timer? _debounce;
  int _gen = 0;
  bool _loading = false;

  /// 0 Tümü, 1 Turnuvalar, 2 Takımlar, 3 Futbolcular.
  int _tab = 0;
  List<_Hit> _leagues = const [];
  List<_Hit> _teams = const [];
  List<_Hit> _players = const [];
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (mounted) setState(() => _recent = p.getStringList(_kRecent) ?? []);
    } catch (_) {}
  }

  Future<void> _remember(String q) async {
    final t = q.trim();
    if (t.length < 2) return;
    final next = [t, ..._recent.where((r) => r != t)].take(8).toList();
    setState(() => _recent = next);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kRecent, next);
    } catch (_) {}
  }

  Future<void> _clearRecent() async {
    setState(() => _recent = const []);
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kRecent);
    } catch (_) {}
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _search);
    setState(() {});
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    final gen = ++_gen;
    if (q.length < 2) {
      setState(() {
        _leagues = const [];
        _teams = const [];
        _players = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.rpc(
        'search_entities',
        params: {'p_q': q},
      );
      if (!mounted || gen != _gen) return;
      final m = Map<String, dynamic>.from(res as Map);
      String s(Object? v) => (v ?? '').toString().trim();
      setState(() {
        _loading = false;
        _leagues = [
          for (final r in (m['leagues'] as List? ?? const []))
            _Hit(
              id: s(r['id']),
              name: s(r['name']),
              sub: r['locked'] == true ? 'Gizli turnuva' : 'Turnuva',
              image: s(r['logo_url']),
              kind: FollowKind.league,
              locked: r['locked'] == true,
            ),
        ];
        _teams = [
          for (final r in (m['teams'] as List? ?? const []))
            _Hit(
              id: s(r['id']),
              name: s(r['name']),
              sub: s(r['league_name']),
              image: s(r['logo_url']),
              seasonId: s(r['season_id']),
              kind: FollowKind.team,
            ),
        ];
        _players = [
          for (final r in (m['players'] as List? ?? const []))
            _Hit(
              id: s(r['id']),
              name: '${s(r['name'])} ${s(r['surname'])}'.trim(),
              // Kadroda değilse "Boşta".
              sub: s(r['team_name']).isEmpty
                  ? 'Boşta'
                  : [
                      s(r['team_name']),
                      if (s(r['jersey_number']).isNotEmpty)
                        s(r['jersey_number']),
                    ].join(' · '),
              image: s(r['photo_url']),
              kind: FollowKind.player,
            ),
        ];
      });
    } catch (_) {
      if (mounted && gen == _gen) setState(() => _loading = false);
    }
  }

  void _open(_Hit h) {
    _remember(_ctrl.text);
    if (h.player) {
      showPlayerCard(context, playerKey: h.id);
      return;
    }
    // Gizli turnuva: erişim yoksa kod istenir.
    if (h.locked) {
      _askCode(h);
      return;
    }
    // Turnuva: uygulama o turnuvaya geçer, ana sayfaya dönülür.
    if (h.kind == FollowKind.league) {
      final nav = Navigator.of(context);
      ActiveTournament.choose(h.id);
      nav.popUntil((r) => r.isFirst);
      return;
    }
    if (h.seasonId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'TeamSquadScreen'),
        builder: (_) => TeamSquadScreen(
          teamId: h.id,
          tournamentId: h.seasonId,
          teamName: h.name,
          teamLogoUrl: h.image,
        ),
      ),
    );
  }

  Future<void> _askCode(_Hit h) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: h.name,
      message:
          'Bu turnuva gizli. Görmek için turnuva yöneticisinden turnuva '
          'kodunu isteyin ve kodu girin.',
      confirmLabel: 'KOD GİR',
      cancelLabel: 'VAZGEÇ',
      destructive: false,
      icon: Icons.lock_rounded,
    );
    if (!ok || !mounted) return;
    await showLeagueCodeDialog(context);
    if (mounted) _search();
  }

  /// Yazılan harfler adın içinde yeşil (Türkçe harfe duyarsız eşleşme).
  Widget _highlight(String name) {
    String fold(String v) => v
        .replaceAll('İ', 'i')
        .replaceAll('I', 'ı')
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ş', 's')
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ö', 'o')
        .replaceAll('ü', 'u')
        .replaceAll('â', 'a')
        .replaceAll('î', 'i')
        .replaceAll('û', 'u');
    const base = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w800,
      fontSize: 15,
    );
    final q = fold(_ctrl.text.trim());
    final i = q.isEmpty ? -1 : fold(name).indexOf(q);
    if (i < 0 || fold(name).length != name.length) {
      return Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: base,
      );
    }
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: name.substring(0, i)),
          TextSpan(
            text: name.substring(i, i + q.length),
            style: const TextStyle(color: _green),
          ),
          TextSpan(text: name.substring(i + q.length)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _row(_Hit h) {
    final fallback = Container(
      alignment: Alignment.center,
      color: const Color(0xFF1E293B),
      child: Text(
        h.name.isEmpty ? '?' : h.name.characters.first,
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: const Color(0xFF131D33),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(h),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(h.player ? 10 : 20),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: h.image.isEmpty
                        ? fallback
                        : WebSafeImage(url: h.image, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _highlight(h.name),
                      if (h.sub.isNotEmpty)
                        Text(
                          h.sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                if (h.locked)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Icon(
                      Icons.lock_rounded,
                      color: Color(0xFFFBBF24),
                      size: 22,
                    ),
                  )
                else
                  FollowStar(kind: h.kind, id: h.id),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String t, {Color color = _green}) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
    child: Text(
      t,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
      ),
    ),
  );

  Widget _chip(String label, bool on, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Material(
      color: on ? const Color(0xFF10B981) : const Color(0xFF131D33),
      shape: StadiumBorder(
        side: BorderSide(
          color: on ? Colors.transparent : const Color(0xFF263248),
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: on ? const Color(0xFF04291C) : Colors.white70,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _results() {
    final q = _ctrl.text.trim();
    if (q.length < 2) return _start();
    final total = _leagues.length + _teams.length + _players.length;
    Widget tab(int i, String label, int n) =>
        _chip('$label $n', _tab == i, () => setState(() => _tab = i));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              tab(0, 'Tümü', total),
              tab(1, 'Turnuvalar', _leagues.length),
              tab(2, 'Takımlar', _teams.length),
              tab(3, 'Futbolcular', _players.length),
            ],
          ),
        ),
        if (_loading && total == 0)
          const Padding(
            padding: EdgeInsets.only(top: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (total == 0)
          const Padding(
            padding: EdgeInsets.only(top: 32),
            child: Text(
              'Sonuç bulunamadı.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted),
            ),
          ),
        if ((_tab == 0 || _tab == 1) && _leagues.isNotEmpty) ...[
          _label('TURNUVALAR'),
          for (final l in _leagues) _row(l),
        ],
        if ((_tab == 0 || _tab == 2) && _teams.isNotEmpty) ...[
          _label('TAKIMLAR'),
          for (final t in _teams) _row(t),
        ],
        if ((_tab == 0 || _tab == 3) && _players.isNotEmpty) ...[
          _label('FUTBOLCULAR'),
          for (final p in _players) _row(p),
        ],
      ],
    );
  }

  /// İlk açılış: son aramalar.
  Widget _start() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        if (_recent.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: _label('SON ARAMALAR', color: _muted)),
              TextButton(
                onPressed: _clearRecent,
                child: const Text('Temizle', style: TextStyle(color: _green)),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in _recent)
                ActionChip(
                  avatar: const Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: _muted,
                  ),
                  label: Text(r),
                  labelStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  backgroundColor: const Color(0xFF131D33),
                  side: const BorderSide(color: Color(0xFF263248)),
                  shape: const StadiumBorder(),
                  onPressed: () {
                    _ctrl.text = r;
                    _ctrl.selection = TextSelection.collapsed(offset: r.length);
                    _search();
                    setState(() {});
                  },
                ),
            ],
          ),
        ] else
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 32, 8, 0),
            child: Text(
              'Aramak için en az iki harf yazın.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Ara',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _onChanged,
              onSubmitted: (v) {
                _remember(v);
                _search();
              },
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: 'Turnuva, takım ya da futbolcu adı',
                hintStyle: const TextStyle(color: _muted),
                prefixIcon: const Icon(Icons.search_rounded, color: _green),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Temizle',
                        icon: const Icon(Icons.close_rounded, color: _muted),
                        onPressed: () {
                          _ctrl.clear();
                          _search();
                        },
                      ),
                filled: true,
                fillColor: const Color(0xFF0B1220),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(
                    color: Color(0xFF2B3954),
                    width: 1.5,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: _green, width: 1.5),
                ),
              ),
            ),
          ),
          Expanded(child: _results()),
        ],
      ),
    );
  }
}
