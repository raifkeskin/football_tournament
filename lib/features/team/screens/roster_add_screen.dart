import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/utils/reveal_search.dart';
import '../../../core/utils/team_colors.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/list_filter.dart';
import '../../../core/widgets/team_crest.dart';
import '../../admin/services/approval_service.dart';
import '../../identity/identity_service.dart';
import '../../identity/identity_verify_screen.dart';
import '../../identity/verified_badge.dart';
import '../widgets/squad_popups.dart';

/// "Kadroya Futbolcu Ekle" kısayolu kimde görünür: admin her zaman; takım
/// sorumlusu anahtar açıksa ya da deneme listesindeyse.
class RosterAddAccess {
  RosterAddAccess._();

  static Listenable get changes => Listenable.merge([
    AppSettings.rosterAddShortcutEnabled,
    AppSettings.rosterAddShortcutUsers,
  ]);

  static bool visible(AppSessionState s) {
    final u = s.user;
    if (u == null || u.isAnonymous) return false;
    if (s.isAdmin) return true;
    if (s.managedTeams.isEmpty) return false;
    return AppSettings.rosterAddShortcutEnabled.value ||
        AppSettings.rosterAddShortcutUsers.value.contains(u.id);
  }
}

/// Sorumlusu olunan takım × turnuva (son sezon).
class RosterAddTarget {
  const RosterAddTarget({
    required this.seasonId,
    required this.teamId,
    required this.teamName,
    required this.logoUrl,
    required this.palette,
    required this.leagueName,
    required this.seasonYear,
    required this.rosterCount,
    required this.addOpen,
  });

  factory RosterAddTarget.fromMap(Map<String, dynamic> m) => RosterAddTarget(
    seasonId: '${m['season_id']}',
    teamId: '${m['team_id']}',
    teamName: '${m['team_name'] ?? ''}',
    logoUrl: '${m['logo_url'] ?? ''}',
    palette: TeamPalette.of(
      m['first_color'] as String?,
      m['second_color'] as String?,
    ),
    leagueName: '${m['league_name'] ?? ''}',
    seasonYear: (m['season_year'] as num?)?.toInt() ?? 0,
    rosterCount: (m['roster_count'] as num?)?.toInt() ?? 0,
    addOpen: m['add_open'] != false,
  );

  final String seasonId;
  final String teamId;
  final String teamName;
  final String logoUrl;
  final TeamPalette palette;
  final String leagueName;
  final int seasonYear;
  final int rosterCount;

  /// Lig başladıysa ekleme yalnız transfer döneminde (roster_add_allowed).
  final bool addOpen;

  String get tournamentLabel => '$leagueName · $seasonYear';
}

/// Menüden açılış: tek takım-turnuva varsa doğrudan liste, birden fazlaysa
/// önce hangi kadroya ekleneceği sorulur.
class RosterAddFlow {
  RosterAddFlow._();

  static Future<void> start(BuildContext context) async {
    List<RosterAddTarget> targets;
    try {
      final r = await Supabase.instance.client.rpc('my_roster_add_targets');
      targets = [
        for (final m in (r as List? ?? const []))
          RosterAddTarget.fromMap(Map<String, dynamic>.from(m as Map)),
      ];
    } catch (e) {
      if (!context.mounted) return;
      await showAdminInfoDialog(
        context: context,
        title: 'Takımlar yüklenemedi',
        message: 'Bağlantıyı kontrol edip tekrar deneyin.',
      );
      return;
    }
    if (!context.mounted) return;
    if (targets.isEmpty) {
      await showAdminInfoDialog(
        context: context,
        title: 'Takım bulunamadı',
        message: 'Sorumlusu olduğun, devam eden bir turnuvada takım yok.',
      );
      return;
    }
    final picked = targets.length == 1
        ? targets.first
        : await pickTarget(context, targets, null);
    if (picked == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'RosterAddScreen'),
        builder: (_) => RosterAddScreen(targets: targets, initial: picked),
      ),
    );
  }

  /// Birden çok turnuva varsa önce turnuva, sonra o turnuvanın takımları
  /// seçilir (uzun tek listede takım aranmaz).
  static Future<RosterAddTarget?> pickTarget(
    BuildContext context,
    List<RosterAddTarget> targets,
    RosterAddTarget? current,
  ) async {
    final bySeason = <String, List<RosterAddTarget>>{};
    for (final t in targets) {
      bySeason.putIfAbsent(t.seasonId, () => []).add(t);
    }
    var list = targets;
    if (bySeason.length > 1) {
      final sid = await _pickSeason(context, bySeason, current?.seasonId);
      if (sid == null || !context.mounted) return null;
      list = bySeason[sid]!;
      if (list.length == 1) return list.first;
    }
    return _pickTeam(context, list, current);
  }

  static Future<String?> _pickSeason(
    BuildContext context,
    Map<String, List<RosterAddTarget>> bySeason,
    String? currentSeasonId,
  ) => showAdminPopup<String>(
    context: context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminDialogHeader(
          icon: Icons.emoji_events_rounded,
          title: 'Hangi turnuva?',
          subtitle: 'Birden fazla turnuvada takım sorumlususun.',
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
            children: [
              for (final e in bySeason.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SeasonTile(
                    label: e.value.first.tournamentLabel,
                    teamCount: e.value.length,
                    selected: e.key == currentSeasonId,
                    onTap: () => Navigator.pop(ctx, e.key),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  static Future<RosterAddTarget?> _pickTeam(
    BuildContext context,
    List<RosterAddTarget> targets,
    RosterAddTarget? current,
  ) => showAdminPopup<RosterAddTarget>(
    context: context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminDialogHeader(
          icon: Icons.group_add_rounded,
          title: 'Hangi kadroya ekleyeceksin?',
          subtitle: targets.first.tournamentLabel,
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
            children: [
              for (final t in targets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TargetTile(
                    target: t,
                    selected:
                        current != null &&
                        current.seasonId == t.seasonId &&
                        current.teamId == t.teamId,
                    onTap: () => Navigator.pop(ctx, t),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Turnuva seçimi satırı: turnuva adı · sezon ve takım sayısı.
class _SeasonTile extends StatelessWidget {
  const _SeasonTile({
    required this.label,
    required this.teamCount,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final int teamCount;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? kAdminAccent.withValues(alpha: 0.10)
          : const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected
              ? kAdminAccent.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              const Icon(
                Icons.emoji_events_rounded,
                size: 26,
                color: Color(0xFFFCD34D),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$teamCount takım',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetTile extends StatelessWidget {
  const _TargetTile({
    required this.target,
    required this.onTap,
    this.selected = false,
    this.trailing,
  });

  final RosterAddTarget target;
  final VoidCallback onTap;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = target;
    return Material(
      color: selected
          ? kAdminAccent.withValues(alpha: 0.10)
          : const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected
              ? kAdminAccent.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                TeamCrest(
                  name: t.teamName,
                  logoUrl: t.logoUrl,
                  size: 38,
                  circle: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.teamName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.emoji_events_rounded,
                            size: 13,
                            color: Color(0xFFFCD34D),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              t.tournamentLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFFCD34D),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${t.rosterCount} oyuncu · '
                        '${t.addOpen ? 'Ekleme açık' : 'Transfer dönemi değil'}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bu turnuvanın kadrolarında olmayan futbolcular (boşta ya da başka
/// turnuvada); seçilen forma numarasıyla kadro talebi açılır. Listede
/// olmayan futbolcu kimlik kartı okutularak eklenir (uygulamada).
class RosterAddScreen extends StatefulWidget {
  const RosterAddScreen({
    super.key,
    required this.targets,
    required this.initial,
  });

  final List<RosterAddTarget> targets;
  final RosterAddTarget initial;

  @override
  State<RosterAddScreen> createState() => _RosterAddScreenState();
}

class _RosterAddScreenState extends State<RosterAddScreen> {
  static const _pageSize = 40;
  static const _defaults = {'status': 'all', 'position': 'all', 'id': 'all'};

  final _sb = Supabase.instance.client;
  final _approval = ApprovalService();
  final _scroll = ScrollController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  late RosterAddTarget _target = widget.initial;
  Map<String, String> _filter = {..._defaults};
  String _q = '';
  bool _searchOpen = false;
  Timer? _debounce;

  List<Map<String, dynamic>> _rows = const [];
  int _total = 0;
  bool _loading = true;
  String? _error;
  int _req = 0;

  /// Bu oturumda talebi gönderilenler (satırda "Talep ✓").
  final _sent = <String>{};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        _loadMore();
      }
    });
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  bool get _isAdmin => AppSession.of(context).value.isAdmin;

  Future<Map<String, dynamic>> _call(
    Map<String, String> f, {
    int offset = 0,
    int limit = _pageSize,
  }) async {
    final pos = f['position'] ?? 'all';
    final r = await _sb.rpc(
      'roster_add_candidates',
      params: {
        'p_season_id': _target.seasonId,
        'p_team_id': _target.teamId,
        'p_q': _q,
        'p_status': f['status'] ?? 'all',
        'p_positions': pos == 'all' ? null : [pos],
        'p_verified': f['id'] == 'ver',
        'p_offset': offset,
        'p_limit': limit,
      },
    );
    return Map<String, dynamic>.from(r as Map);
  }

  List<Map<String, dynamic>> _rowsOf(Map<String, dynamic> r) => [
    for (final x in (r['rows'] as List? ?? const []))
      Map<String, dynamic>.from(x as Map),
  ];

  Future<void> _reload() async {
    final id = ++_req;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _call(_filter);
      if (!mounted || id != _req) return;
      setState(() {
        _rows = _rowsOf(r);
        _total = (r['total'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _req) return;
      setState(() {
        _loading = false;
        _error = 'Liste yüklenemedi. Aşağı çekip yenileyin.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _rows.length >= _total) return;
    final id = _req;
    setState(() => _loading = true);
    try {
      final r = await _call(_filter, offset: _rows.length);
      if (!mounted || id != _req) return;
      setState(() {
        _rows = [..._rows, ..._rowsOf(r)];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _q = v.trim();
      _reload();
    });
  }

  List<ListFilterSection> _sections(Map<String, String> _) => const [
    ListFilterSection(
      key: 'status',
      label: 'Durum',
      options: [
        ('all', 'Hepsi'),
        ('free', 'Boşta'),
        ('other', 'Başka turnuvada'),
      ],
      defaultValue: 'all',
      hint:
          'Boşta: hiçbir turnuva kadrosunda değil. Başka turnuvada: başka '
          'bir turnuvada oynuyor, bu turnuvaya da eklenebilir.',
    ),
    ListFilterSection(
      key: 'position',
      label: 'Mevki',
      options: [
        ('all', 'Tümü'),
        ('Kaleci', 'Kaleci'),
        ('Defans', 'Defans'),
        ('Orta Saha', 'Orta saha'),
        ('Forvet', 'Forvet'),
      ],
      defaultValue: 'all',
      hint: 'Tümü: mevkisi girilmemiş futbolcular da listelenir.',
    ),
    ListFilterSection(
      key: 'id',
      label: 'Kimlik',
      options: [('all', 'Hepsi'), ('ver', 'Kimliği onaylı')],
      defaultValue: 'all',
    ),
  ];

  Future<ListFilterCounts> _counts(Map<String, String> v) async {
    // Durum sayıları sunucudan; diğer bölümler için yalnız toplam.
    final r = await _call(v, limit: 1);
    final c = Map<String, dynamic>.from(r['counts'] as Map? ?? {});
    return ListFilterCounts(
      total: (r['total'] as num?)?.toInt() ?? 0,
      options: {
        'status': {for (final e in c.entries) e.key: (e.value as num).toInt()},
      },
    );
  }

  Future<Set<int>> _takenNumbers() async {
    final rows = await _sb
        .from('season_team_players')
        .select('jersey_number')
        .eq('season_id', _target.seasonId)
        .eq('team_id', _target.teamId)
        .eq('is_active', true);
    return {
      for (final r in rows)
        if (r['jersey_number'] is num) (r['jersey_number'] as num).toInt(),
    };
  }

  /// Forma numarası: önce seçim yapılmadan devam edilebilir (numarasız ya
  /// da ilk boş numara otomatik); "Numara seç" denirse numara ızgarası açılır.
  /// Vazgeçilirse null, numarasız ise ''.
  Future<String?> _askJersey(String name) async {
    Set<int> taken = const {};
    try {
      taken = await _takenNumbers();
    } catch (_) {}
    if (!mounted) return null;
    final auto = [
      for (var n = 1; n <= 99; n++) n,
    ].firstWhere((n) => !taken.contains(n), orElse: () => 0);
    final choice = await showAdminPopup<String>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminDialogHeader(
            icon: Icons.checkroom_rounded,
            title: 'Forma numarası',
            subtitle: name,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _jerseyChoice(
                  ctx,
                  'pick',
                  Icons.dialpad_rounded,
                  'Numara seç',
                  'Boş numaralardan seç',
                ),
                if (auto > 0)
                  _jerseyChoice(
                    ctx,
                    'auto',
                    Icons.auto_awesome_rounded,
                    'Otomatik ata',
                    'İlk boş numara: $auto',
                  ),
                _jerseyChoice(
                  ctx,
                  'none',
                  Icons.arrow_forward_rounded,
                  'Numarasız devam et',
                  'Numara sonra verilebilir',
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return null;
    if (choice == 'auto') return '$auto';
    if (choice == 'none') return '';
    return showSquadJerseyPicker(
      context: context,
      playerName: name,
      current: '',
      taken: taken,
      palette: _target.palette,
    );
  }

  Widget _jerseyChoice(
    BuildContext ctx,
    String value,
    IconData icon,
    String title,
    String sub,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.pop(ctx, value),
        child: SizedBox(
          height: 58,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(icon, color: kAdminAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        sub,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  bool _checkOpen() {
    if (_target.addOpen || _isAdmin) return true;
    showAdminInfoDialog(
      context: context,
      title: 'Kadroya ekleme kapalı',
      message:
          'Lig başladığı için kadroya ekleme yalnızca transfer döneminde '
          'yapılabilir.',
    );
    return false;
  }

  Future<void> _add(Map<String, dynamic> p) async {
    if (!_checkOpen()) return;
    final id = '${p['id']}';
    final name = '${p['name'] ?? ''} ${p['surname'] ?? ''}'.trim();
    final jersey = await _askJersey(name);
    if (jersey == null || !mounted) return;
    final number = int.tryParse(jersey);
    try {
      if (_isAdmin) {
        // Bu sezon kadrodan çıkarılmış (pasif) kaydı varsa o canlanır.
        final old = await _sb
            .from('season_team_players')
            .select('id')
            .eq('season_id', _target.seasonId)
            .eq('player_id', id)
            .maybeSingle();
        if (old != null) {
          await _sb
              .from('season_team_players')
              .update({
                'team_id': _target.teamId,
                'is_active': true,
                'jersey_number': ?number,
              })
              .eq('id', old['id']);
        } else {
          await _sb.from('season_team_players').insert({
            'season_id': _target.seasonId,
            'team_id': _target.teamId,
            'player_id': id,
            'jersey_number': number,
          });
        }
      } else {
        await _approval.submit(
          type: PendingActionType.rosterAdd,
          seasonId: _target.seasonId,
          teamId: _target.teamId,
          payload: {
            'player_id': id,
            'player_name': name,
            'jersey_number': ?number,
          },
        );
      }
      if (!mounted) return;
      setState(() => _sent.add(id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAdmin
                ? '$name kadroya eklendi.'
                : '$name için talep gönderildi. Turnuva sorumlusu '
                      'onaylayınca kadroda görünür.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      await showAdminInfoDialog(
        context: context,
        title: 'Talep gönderilemedi',
        message:
            msg.contains('pending_actions_one_open_per_player') ||
                msg.contains('23505')
            ? '$name için zaten onay bekleyen bir talep var.'
            : msg.replaceFirst('Exception: ', '').trim(),
      );
    }
  }

  Future<void> _addWithIdentity() async {
    if (!_checkOpen()) return;
    final jersey = await _askJersey('Yeni futbolcu');
    if (jersey == null || !mounted) return;
    final r = await IdentityVerifyScreen.addToRoster(
      context,
      RosterTarget(
        seasonId: _target.seasonId,
        teamId: _target.teamId,
        teamName: _target.teamName,
        jersey: jersey,
      ),
    );
    if (r == null || !mounted) return;
    await showAdminInfoDialog(
      context: context,
      title: r.pending ? 'Talep gönderildi' : 'Kadroya eklendi',
      message: r.pending
          ? '${r.name} için kadro talebi gönderildi. Turnuva sorumlusu '
                'onaylayınca kadroda görünür.'
          : '${r.name} kadroya eklendi.',
    );
    if (mounted) _reload();
  }

  Future<void> _changeTarget() async {
    if (widget.targets.length < 2) return;
    final t = await RosterAddFlow.pickTarget(context, widget.targets, _target);
    if (t == null || !mounted) return;
    setState(() {
      _target = t;
      _sent.clear();
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.targets.length > 1;
    final topActions = <Widget>[
      if (!_searchOpen)
        IconButton(
          tooltip: 'Futbolcu ara',
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF1E293B),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            fixedSize: const Size(42, 42),
          ),
          onPressed: () {
            setState(() => _searchOpen = true);
            revealSearchField(_searchFocus);
          },
          icon: const Icon(Icons.search_rounded, color: Colors.white),
        ),
    ];
    return AdminPageScaffold(
      title: 'Kadroya Futbolcu Ekle',
      bottomBar: kIsWeb ? null : _identityBar(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: _TargetTile(
              target: _target,
              onTap: _changeTarget,
              trailing: multi
                  ? const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Text(
                        'Değiştir',
                        style: TextStyle(
                          color: kAdminAccent,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
          if (_searchOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                style: const TextStyle(color: Colors.white),
                cursorColor: kAdminAccent,
                decoration:
                    adminInputDecoration(
                      hint: 'İsimle ara',
                      icon: Icons.search_rounded,
                    ).copyWith(
                      suffixIcon: IconButton(
                        tooltip: 'Aramayı kapat',
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white54,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _searchFocus.unfocus();
                          setState(() => _searchOpen = false);
                          if (_q.isNotEmpty) {
                            _q = '';
                            _reload();
                          }
                        },
                      ),
                    ),
                onChanged: _onSearch,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: ListFilterBar(
              title: 'Futbolcuları filtrele',
              unit: 'futbolcu',
              trailing: topActions,
              sections: _sections,
              values: _filter,
              onChanged: (v) {
                setState(() => _filter = v);
                _reload();
              },
              total: _total,
              counts: _counts,
            ),
          ),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _list() {
    if (_loading && _rows.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: kAdminAccent),
      );
    }
    final message =
        _error ??
        (_rows.isEmpty
            ? (_q.isNotEmpty
                  ? '"$_q" ile eşleşen futbolcu yok.'
                  : 'Bu filtreye uyan futbolcu yok.')
            : null);
    return RefreshIndicator(
      color: kAdminAccent,
      onRefresh: _reload,
      child: message != null
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 80),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54),
                ),
              ],
            )
          : ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 24),
              itemCount: _rows.length + (_rows.length < _total ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, i) => i >= _rows.length
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: CircularProgressIndicator(color: kAdminAccent),
                      ),
                    )
                  : _row(_rows[i]),
            ),
    );
  }

  static int? _age(String? birth) {
    final d = DateTime.tryParse(birth ?? '');
    if (d == null) return null;
    final now = DateTime.now();
    var a = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) a--;
    return a;
  }

  Widget _row(Map<String, dynamic> p) {
    final id = '${p['id']}';
    final name = '${p['name'] ?? ''} ${p['surname'] ?? ''}'.trim();
    final age = _age(p['birth_date'] as String?);
    final pos = (p['main_position'] ?? '').toString().trim();
    final other = (p['other_league'] ?? '').toString().trim();
    final sent = _sent.contains(id);
    final sub = [if (age != null) '$age yaş', if (pos.isNotEmpty) pos];
    final tagColor = other.isEmpty ? kAdminAccent : const Color(0xFFFCD34D);
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: sent
            ? kAdminAccent.withValues(alpha: 0.06)
            : const Color(0xFF16213A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: sent
              ? kAdminAccent.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          SquadPlayerAvatar(
            name: name,
            photoUrl: (p['photo_url'] ?? '').toString(),
            size: 38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (p['verified'] == true) ...[
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.verified_rounded,
                        size: 15,
                        color: kVerifiedBlue,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (sub.isNotEmpty) ...[
                      Text(
                        sub.join(' · '),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: tagColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          other.isEmpty ? 'Boşta' : other,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tagColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 40,
            child: sent
                ? TextButton(
                    onPressed: null,
                    child: const Text(
                      'Talep ✓',
                      style: TextStyle(
                        color: kAdminAccent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAdminAccent,
                      foregroundColor: const Color(0xFF04221A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _add(p),
                    child: const Text(
                      'Ekle',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _identityBar() {
    const amber = Color(0xFFFBBF24);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Material(
          color: amber.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: amber.withValues(alpha: 0.6), width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _addWithIdentity,
            child: const SizedBox(
              height: 60,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(Icons.badge_outlined, color: amber),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Listede yok mu?',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Kimlik kartını okutarak yeni futbolcu ekle',
                            style: TextStyle(
                              color: Color(0xFFFCD34D),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: amber),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
