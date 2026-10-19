import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/service_locator.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/app_name_band.dart';
import '../../player/services/penalty_service.dart';
import '../../tournament/models/age_rules.dart';
import '../../tournament/screens/formation_tab.dart';
import '../models/match.dart';
import '../widgets/esame_scan.dart';

/// Esame girişi (tam ekran): üstte İlk 11 ve Yedekler kutuları (tüm yuvalar
/// aynı anda görünür), altta mevki sekmeli kadro. Oyuncu düğmeyle ya da
/// sürükleyerek kutuya geçer ve listeden düşer. Forma numarası her yerde
/// sarı kesik çerçeveli kutuda düzenlenir; dokununca numara seçili gelir.
class EsameEditScreen extends StatefulWidget {
  const EsameEditScreen({
    super.key,
    required this.match,
    required this.teamId,
    required this.teamName,
    required this.isHome,
  });

  final MatchModel match;
  final String teamId;
  final String teamName;
  final bool isHome;

  @override
  State<EsameEditScreen> createState() => _EsameEditScreenState();
}

/// Bırakma hedefi: ilk 11, yedek ya da kadro listesi.
enum _Box { starters, subs, list }

class _EsameEditScreenState extends State<EsameEditScreen> {
  final _teamService = ServiceLocator.teamService;
  final _matchService = ServiceLocator.matchService;

  List<PlayerModel> _players = [];
  Map<String, PlayerModel> _byId = {};

  /// Sıralı: ilk 11'in ilk oyuncusu kaleci olarak kaydedilir.
  final List<String> _starters = [];
  final List<String> _subs = [];
  String? _captainId;
  final Map<String, TextEditingController> _jersey = {};

  bool _isLoading = true;
  bool _isSaving = false;
  bool _dirty = false;

  int _startingLimit = 11;
  int _subLimit = 7;
  Map<String, PlayerPenalty> _penalized = const {};
  AgeRules _ageRules = const AgeRules();

  /// -1: Tümü, 0..3: Kaleci / Defans / Orta Saha / Forvet.
  int _tab = -1;

  static const _bg = Color(0xFF0F172A);
  static const _card = Color(0xFF1E293B);
  static const _green = Color(0xFF10B981);
  static const _blue = Color(0xFF3B82F6);
  static const _gold = Color(0xFFFBBF24);
  static const _red = Color(0xFFF87171);
  static const _mid = Color(0xFF94A3B8);
  static const _slotH = 24.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// Esame ekranında üstteki ortak bant gizlenir.
  Route<dynamic>? _bandRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _bandRoute) return;
    LeagueSwitchScope.setBandHidden(_bandRoute, false);
    _bandRoute = route;
    LeagueSwitchScope.setBandHidden(route, true);
  }

  @override
  void dispose() {
    LeagueSwitchScope.setBandHidden(_bandRoute, false);
    for (final c in _jersey.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      Future<Map<String, dynamic>?> loadSeasonLimits() async {
        if (widget.match.seasonId.isEmpty) return null;
        try {
          return await Supabase.instance.client
              .from('seasons')
              .select('starting_player_count, sub_player_count, age_rules')
              .eq('id', widget.match.seasonId)
              .maybeSingle();
        } catch (_) {
          return null;
        }
      }

      Future<Map<String, PlayerPenalty>> loadPenalties() async {
        try {
          return await PenaltyService()
              .watchActivePenaltiesByPlayerId(widget.match.seasonId)
              .first;
        } catch (_) {
          return const {};
        }
      }

      final (sRes, players, rosters, penalties) = await (
        loadSeasonLimits(),
        _teamService.getEligiblePlayers(widget.teamId, widget.match.seasonId),
        _matchService.watchMatchRosters(widget.match.id, widget.teamId).first,
        loadPenalties(),
      ).wait;

      if (!mounted) return;
      setState(() {
        _startingLimit = sRes?['starting_player_count'] ?? 11;
        _subLimit = sRes?['sub_player_count'] ?? 7;
        _ageRules = AgeRules.fromJson(sRes?['age_rules']);
        _players = [...players]..sort(_compare);
        _byId = {for (final p in _players) p.id: p};
        _penalized = penalties;
        // Kayıtlı kaleci (pos_x = 0) ilk sırada.
        final gk = rosters
            .where((x) => x.isStarting && x.slot == 0)
            .firstOrNull;
        if (gk != null && _byId.containsKey(gk.playerId)) {
          _starters.add(gk.playerId);
        }
        for (final p in _players) {
          final r = rosters.where((x) => x.playerId == p.id).firstOrNull;
          if (r != null && !_starters.contains(p.id)) {
            (r.isStarting ? _starters : _subs).add(p.id);
          }
          if (r != null && r.isCaptain && r.isStarting) _captainId = p.id;
          _jersey[p.id] = TextEditingController(
            text: r?.jerseyNumber ?? p.number ?? '',
          );
        }
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _line(PlayerModel p) => positionLineOf(p.mainPosition, p.position);

  /// Mevki (Kaleci → Forvet), sonra kadro numarası, sonra ad.
  int _compare(PlayerModel a, PlayerModel b) {
    final la = _line(a), lb = _line(b);
    if (la != lb) return la.compareTo(lb);
    final na = int.tryParse(a.number ?? '') ?? 999;
    final nb = int.tryParse(b.number ?? '') ?? 999;
    return na != nb ? na.compareTo(nb) : a.name.compareTo(b.name);
  }

  bool _selected(String id) => _starters.contains(id) || _subs.contains(id);

  bool _isQuota(PlayerModel p) => _ageRules.isMatchQuota(
    birthYear: AgeRules.birthYearOf(p.birthDate),
    isGk: (p.mainPosition ?? '').trim() == 'Kaleci',
  );

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
  }

  void _removeFromBoxes(String id) {
    _starters.remove(id);
    _subs.remove(id);
    if (_captainId == id) _captainId = null;
  }

  /// Oyuncuyu kutuya (isteğe bağlı sıraya) koyar ya da listeye geri alır.
  void _place(String id, _Box box, [int? at]) {
    if (box == _Box.list) {
      if (!_selected(id)) return;
      setState(() {
        _removeFromBoxes(id);
        _dirty = true;
      });
      return;
    }
    final pen = _penalized[id];
    if (pen != null) {
      _toast(
        'Bu oyuncu cezalı (${pen.remainingMatches ?? pen.matchCount} maç '
        'kaldı); esameye eklenemez.',
      );
      return;
    }
    final list = box == _Box.starters ? _starters : _subs;
    final limit = box == _Box.starters ? _startingLimit : _subLimit;
    final old = list.indexOf(id);
    if (old >= 0) {
      // Aynı kutuda yer değiştirme.
      if (at == null) return;
      setState(() {
        list.removeAt(old);
        list.insert(math.min(at > old ? at - 1 : at, list.length), id);
        _dirty = true;
      });
      return;
    }
    if (list.length >= limit) {
      _toast(
        box == _Box.starters
            ? 'İlk 11 dolu ($limit). Önce birini çıkarın.'
            : 'Yedek kontenjanı dolu ($limit).',
      );
      return;
    }
    setState(() {
      _removeFromBoxes(id);
      list.insert(math.min(at ?? list.length, list.length), id);
      _dirty = true;
    });
  }

  void _autoNumber() {
    final ids = [..._starters, ..._subs];
    if (ids.isEmpty) {
      _toast('Önce esameye oyuncu ekleyin.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      for (var i = 0; i < ids.length; i++) {
        _jersey[ids[i]]?.text = '${i + 1}';
      }
      _dirty = true;
    });
    _toast("Forma numaraları 1'den sırayla verildi.");
  }

  /// Esamedeki numarası boş ya da başkasıyla aynı olan oyuncular.
  Set<String> get _badJersey {
    final ids = [..._starters, ..._subs];
    final count = <String, int>{};
    for (final id in ids) {
      final n = _jersey[id]?.text.trim() ?? '';
      if (n.isNotEmpty) count[n] = (count[n] ?? 0) + 1;
    }
    return {
      for (final id in ids)
        if ((_jersey[id]?.text.trim() ?? '').isEmpty ||
            count[_jersey[id]!.text.trim()]! > 1)
          id,
    };
  }

  Future<void> _readFromPaper() async {
    final picks = await scanEsameFromPhoto(
      context,
      matchId: widget.match.id,
      teamId: widget.teamId,
      teamName: widget.teamName,
      players: _players,
    );
    if (picks == null || !mounted) return;
    final skipped = <String>[];
    var overflow = 0;
    setState(() {
      _starters.clear();
      _subs.clear();
      for (final pick in picks) {
        final pid = pick.playerId;
        if (!_byId.containsKey(pid) || _selected(pid)) continue;
        if (_penalized[pid] != null) {
          skipped.add(_byId[pid]!.name);
          continue;
        }
        if (pick.starting && _starters.length < _startingLimit) {
          _starters.add(pid);
        } else if (_subs.length < _subLimit) {
          _subs.add(pid);
        } else {
          overflow++;
          continue;
        }
        final no = (pick.jersey ?? '').trim();
        if (RegExp(r'^\d{1,2}$').hasMatch(no)) _jersey[pid]?.text = no;
      }
      if (_captainId != null && !_starters.contains(_captainId)) {
        _captainId = null;
      }
      _dirty = true;
    });
    final notes = [
      'Esame kağıttan dolduruldu: ilk 11 ${_starters.length}, '
          'yedek ${_subs.length}.',
      if (skipped.isNotEmpty) 'Cezalı, eklenmedi: ${skipped.join(', ')}.',
      if (overflow > 0) '$overflow oyuncu kontenjanı aştığı için eklenmedi.',
      'Kontrol edip Kaydet\'e basın.',
    ];
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(notes.join(' ')),
          duration: const Duration(seconds: 5),
        ),
      );
  }

  /// Esameyi kaydeder; [close] ise ekranı kapatır. Başarılıysa true.
  Future<bool> _save({bool close = true}) async {
    FocusScope.of(context).unfocus();
    final ids = [..._starters, ..._subs];
    final used = <String>{};
    for (final id in ids) {
      final n = _jersey[id]?.text.trim() ?? '';
      if (!RegExp(r'^\d+$').hasMatch(n)) {
        await showAdminInfoDialog(
          context: context,
          title: 'Forma numarası eksik',
          message:
              '${_byId[id]?.name ?? 'Bir oyuncu'} için forma numarası girin. '
              'Numara önemsizse "Otomatik Forma No" düğmesini kullanın.',
        );
        return false;
      }
      if (!used.add(n)) {
        await showAdminInfoDialog(
          context: context,
          title: 'Aynı forma numarası',
          message: '$n numarası birden fazla oyuncuda var.',
        );
        return false;
      }
    }

    setState(() => _isSaving = true);
    try {
      final rosters = <MatchRosterModel>[
        for (final id in ids)
          MatchRosterModel(
            id: '',
            matchId: widget.match.id,
            leagueId: widget.match.leagueId,
            seasonId: widget.match.seasonId,
            teamId: widget.teamId,
            playerId: id,
            isHome: widget.isHome,
            isStarting: _starters.contains(id),
            jerseyNumber: _jersey[id]?.text.trim(),
            isCaptain: _starters.contains(id) && id == _captainId,
            slot: _starters.isNotEmpty && id == _starters.first ? 0 : null,
          ),
      ];
      await _matchService.updateMatchRoster(
        matchId: widget.match.id,
        leagueId: widget.match.leagueId,
        seasonId: widget.match.seasonId,
        teamId: widget.teamId,
        isHome: widget.isHome,
        rosters: rosters,
      );
      _dirty = false;
      if (mounted && close) Navigator.pop(context, true);
      return true;
    } catch (e) {
      if (mounted) _toast('Hata: $e');
      return false;
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Diziliş penceresi. Diziliş kayıtlı esameden çizilir: kaydedilmemiş
  /// değişiklik varsa önce esame kaydedilir.
  Future<void> _openFormation() async {
    if (_starters.isEmpty) {
      _toast("Önce ilk 11'i seçin.");
      return;
    }
    if (_dirty) {
      if (!await _save(close: false)) return;
      if (!mounted) return;
      setState(() {});
      _toast('Esame kaydedildi.');
    }
    if (!mounted) return;
    final home = widget.isHome;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Diziliş · ${widget.teamName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FormationTab(
                match: widget.match,
                homeName: widget.teamName,
                awayName: widget.teamName,
                canEditHome: home,
                canEditAway: !home,
                initialTeam: home ? 0 : 1,
                singleTeam: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLeave() async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Kaydedilmedi',
      message: 'Esamede yaptığınız değişiklikler kaydedilmedi. Çıkılsın mı?',
      confirmLabel: 'ÇIK',
      icon: Icons.logout_rounded,
    );
    if (ok && mounted) {
      _dirty = false;
      Navigator.pop(context);
    }
  }

  // ---------------------------------------------------------------------------
  // Görünüm
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return PopScope(
      canPop: !_dirty || _isSaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: _bg,
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: Colors.white,
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Esame Listesi',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              Text(
                [
                  widget.teamName,
                  if ((widget.match.matchDate ?? '').length >= 10)
                    _shortDate(widget.match.matchDate!),
                  ?widget.match.matchTime,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _mid),
              ),
            ],
          ),
          actions: [
            if (!_isLoading && _players.isNotEmpty)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: _green),
                onPressed: _isSaving ? null : _readFromPaper,
                icon: const Icon(Icons.document_scanner_outlined, size: 18),
                label: const Text(
                  'Kağıttan oku',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _players.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Bu takımın sezon kadrosunda oyuncu yok.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    children: [
                      _topLine(),
                      _boxes(),
                      _tabs(),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(14, 0, 14, 4),
                        child: Text.rich(
                          TextSpan(
                            text: 'Sürükleyin ya da düğmeye dokunun · ',
                            children: [
                              TextSpan(
                                text: '✎ numarayı değiştirin',
                                style: TextStyle(color: _gold),
                              ),
                            ],
                          ),
                          style: TextStyle(color: _mid, fontSize: 11),
                        ),
                      ),
                      Expanded(child: _squadList(keyboard)),
                      if (keyboard == 0) _footer(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  static const _months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', //
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];

  String _shortDate(String ymd) {
    final m = int.tryParse(ymd.substring(5, 7)) ?? 0;
    final d = int.tryParse(ymd.substring(8, 10)) ?? 0;
    return m < 1 || m > 12 ? ymd : '$d ${_months[m - 1]}';
  }

  /// Kontenjan sayacı ve "1'den otomatik ver".
  Widget _topLine() {
    Widget? quota;
    if (_ageRules.hasMatchLimits) {
      final onField = _starters.where((id) => _isQuota(_byId[id]!)).length;
      final inSquad =
          onField + _subs.where((id) => _isQuota(_byId[id]!)).length;
      final maxSquad = _ageRules.matchMax;
      final maxField = _ageRules.matchFieldMax;
      // Kontenjan bazında esame sınırı (ör. 1988 en fazla 2, 1989 en fazla 1).
      final perQuota = <String>[];
      var quotaOver = false;
      for (var i = 0; i < _ageRules.quotas.length; i++) {
        final q = _ageRules.quotas[i];
        final qMax = q.matchMax;
        if (q.gk || qMax == null) continue;
        final n = [..._starters, ..._subs].where((id) {
          final p = _byId[id]!;
          final c = _ageRules.check(
            birthYear: AgeRules.birthYearOf(p.birthDate),
            isGk: (p.mainPosition ?? '').trim() == 'Kaleci',
          );
          return c.status == AgeStatus.quota && c.quotaIndex == i;
        }).length;
        if (n > qMax) quotaOver = true;
        perQuota.add('${q.yearsLabel} $n/$qMax');
      }
      final over =
          quotaOver ||
          (maxSquad != null && inSquad > maxSquad) ||
          (maxField != null && onField > maxField);
      quota = Text(
        [
          'Kontenjan',
          if (maxSquad != null) 'esame $inSquad/$maxSquad',
          ...perQuota,
          if (maxField != null) 'ilk 11 $onField/$maxField',
          if (over) 'sınır aşıldı',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: over ? _red : _gold,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    Widget button(String label, IconData icon, Color c, VoidCallback onTap) =>
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isSaving ? null : onTap,
            icon: Icon(icon, size: 16),
            label: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: c,
              backgroundColor: c.withValues(alpha: 0.1),
              side: BorderSide(color: c.withValues(alpha: 0.6)),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (quota != null)
            Padding(padding: const EdgeInsets.only(bottom: 6), child: quota),
          Row(
            children: [
              button(
                'Dizilişi Ayarla',
                Icons.sports_soccer_rounded,
                _green,
                _openFormation,
              ),
              const SizedBox(width: 8),
              button(
                'Otomatik Forma No',
                Icons.format_list_numbered_rounded,
                _gold,
                _autoNumber,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _boxes() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _box(_Box.starters)),
          const SizedBox(width: 6),
          Expanded(child: _box(_Box.subs)),
        ],
      ),
    );
  }

  Widget _box(_Box box) {
    final starters = box == _Box.starters;
    final list = starters ? _starters : _subs;
    final limit = starters ? _startingLimit : _subLimit;
    final color = starters ? _green : _blue;
    final full = list.length >= limit;
    final bad = _badJersey;
    // İki kutu aynı yükseklikte: kısa olan boş satırla tamamlanır.
    final rows = math.max(_startingLimit, _subLimit);
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 5, 5, 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(3, 0, 3, 3),
            child: Row(
              children: [
                Text(
                  starters ? 'İLK 11' : 'YEDEKLER',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${list.length}/$limit',
                  style: TextStyle(
                    color: full && starters ? _green : Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < rows; i++)
            i < limit
                ? _slot(box, i, list, bad)
                : const SizedBox(height: _slotH),
        ],
      ),
    );
  }

  Widget _slot(_Box box, int i, List<String> list, Set<String> bad) {
    final id = i < list.length ? list[i] : null;
    final starters = box == _Box.starters;
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _place(d.data, box, i),
      builder: (context, cand, _) {
        final hover = cand.isNotEmpty;
        final Widget content;
        if (id == null) {
          content = Text(
            starters && i == 0 ? 'kaleci' : '${i + 1}.',
            style: const TextStyle(color: Colors.white24, fontSize: 11),
          );
        } else {
          final p = _byId[id]!;
          content = Row(
            children: [
              _JerseyBox(
                controller: _jersey[id]!,
                bad: bad.contains(id),
                small: true,
                onChanged: _onJerseyChanged,
              ),
              const SizedBox(width: 4),
              Expanded(child: _slotName(box, i, p)),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _place(id, _Box.list),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3),
                  child: Icon(Icons.close_rounded, size: 14, color: _mid),
                ),
              ),
            ],
          );
        }
        final row = Container(
          height: _slotH,
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.only(left: 3),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: hover
                ? Colors.white.withValues(alpha: 0.14)
                : id == null
                ? Colors.white.withValues(alpha: 0.02)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(5),
          ),
          child: content,
        );
        if (id == null) return row;
        return LongPressDraggable<String>(
          data: id,
          feedback: _dragChip(_byId[id]!.name),
          childWhenDragging: Opacity(opacity: 0.35, child: row),
          child: row,
        );
      },
    );
  }

  /// Kutudaki ad: dokununca kaleci / kaptan / taşı / çıkar menüsü.
  Widget _slotName(_Box box, int i, PlayerModel p) {
    final starters = box == _Box.starters;
    final isGk = starters && i == 0;
    final isCap = starters && p.id == _captainId;
    return PopupMenuButton<String>(
      tooltip: '',
      padding: EdgeInsets.zero,
      color: _card,
      position: PopupMenuPosition.under,
      onSelected: (v) {
        switch (v) {
          case 'gk':
            setState(() {
              _starters
                ..remove(p.id)
                ..insert(0, p.id);
              _dirty = true;
            });
          case 'cap':
            setState(() {
              _captainId = isCap ? null : p.id;
              _dirty = true;
            });
          case 'move':
            _place(p.id, starters ? _Box.subs : _Box.starters);
          case 'out':
            _place(p.id, _Box.list);
        }
      },
      itemBuilder: (_) => [
        if (starters && !isGk) _menuItem('gk', 'Kaleci yap'),
        if (starters)
          _menuItem('cap', isCap ? 'Kaptanlığı kaldır' : 'Kaptan yap'),
        _menuItem('move', starters ? 'Yedeğe al' : "İlk 11'e al"),
        _menuItem('out', 'Esameden çıkar'),
      ],
      child: Row(
        children: [
          Flexible(
            child: Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (isGk) _tag('KL', _gold),
          if (isCap) _tag('C', _green),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String v, String label) => PopupMenuItem(
    value: v,
    height: 38,
    child: Text(
      label,
      style: const TextStyle(color: Colors.white, fontSize: 13.5),
    ),
  );

  Widget _tag(String t, Color c) => Container(
    margin: const EdgeInsets.only(left: 3),
    padding: const EdgeInsets.symmetric(horizontal: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      t,
      style: TextStyle(color: c, fontSize: 9, fontWeight: FontWeight.w900),
    ),
  );

  Widget _dragChip(String name) => Material(
    color: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _green),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
      ),
      child: Text(
        name,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    ),
  );

  void _onJerseyChanged() => setState(() => _dirty = true);

  List<PlayerModel> get _remaining =>
      _players.where((p) => !_selected(p.id)).toList();

  Widget _tabs() {
    final left = _remaining;
    final labels = ['Tümü', ...positionLineLabels];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, k) {
          final t = k - 1;
          final on = _tab == t;
          final n = t < 0
              ? left.length
              : left.where((p) => _line(p) == t).length;
          return GestureDetector(
            onTap: () => setState(() => _tab = t),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? Colors.white.withValues(alpha: 0.14) : _card,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: on ? Colors.white54 : Colors.transparent,
                ),
              ),
              child: Text.rich(
                TextSpan(
                  text: labels[k],
                  children: [
                    TextSpan(
                      text: '  $n',
                      style: const TextStyle(color: _mid),
                    ),
                  ],
                ),
                style: TextStyle(
                  color: on ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _squadList(double keyboard) {
    final left = _remaining;
    final shown = _tab < 0
        ? left
        : left.where((p) => _line(p) == _tab).toList();
    final children = <Widget>[];
    if (shown.isEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Bu mevkide seçilmemiş oyuncu kalmadı.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12.5),
          ),
        ),
      );
    } else if (_tab < 0) {
      for (var g = 0; g < positionLineLabels.length; g++) {
        final group = shown.where((p) => _line(p) == g).toList();
        if (group.isEmpty) continue;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 3),
            child: Text(
              positionLineLabels[g].toUpperCase(),
              style: const TextStyle(
                color: _mid,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        );
        children.addAll(group.map(_squadRow));
      }
    } else {
      children.addAll(shown.map(_squadRow));
    }
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => _selected(d.data),
      onAcceptWithDetails: (d) => _place(d.data, _Box.list),
      builder: (context, cand, _) => Container(
        color: cand.isNotEmpty ? Colors.white.withValues(alpha: 0.04) : null,
        child: ListView(
          padding: EdgeInsets.fromLTRB(10, 0, 10, 12 + keyboard),
          children: children,
        ),
      ),
    );
  }

  Widget _squadRow(PlayerModel p) {
    final pen = _penalized[p.id];
    final sub = (p.position ?? '').trim();
    final row = Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          pen != null
              ? const SizedBox(width: 26)
              : Draggable<String>(
                  data: p.id,
                  feedback: _dragChip(p.name),
                  child: const SizedBox(
                    width: 26,
                    height: 38,
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 18,
                      color: Colors.white38,
                    ),
                  ),
                ),
          _JerseyBox(
            controller: _jersey[p.id]!,
            bad: false,
            small: false,
            onChanged: _onJerseyChanged,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: p.name,
                children: [
                  if (sub.isNotEmpty)
                    TextSpan(
                      text: '  $sub',
                      style: const TextStyle(
                        color: _mid,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: pen != null ? Colors.white38 : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_ageRules.hasMatchLimits && _isQuota(p)) _tag('K', _gold),
          const SizedBox(width: 6),
          if (pen != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'CEZALI · ${pen.remainingMatches ?? pen.matchCount} maç',
                style: const TextStyle(
                  color: _red,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else ...[
            if (_starters.length < _startingLimit)
              _addButton("İlk 11", _green, () => _place(p.id, _Box.starters)),
            if (_subs.length < _subLimit) ...[
              const SizedBox(width: 5),
              _addButton('Yedek', _blue, () => _place(p.id, _Box.subs)),
            ],
          ],
        ],
      ),
    );
    if (pen != null) return row;
    return LongPressDraggable<String>(
      data: p.id,
      feedback: _dragChip(p.name),
      childWhenDragging: Opacity(opacity: 0.35, child: row),
      child: row,
    );
  }

  Widget _addButton(String label, Color c, VoidCallback onTap) => SizedBox(
    height: 28,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: c,
        backgroundColor: c.withValues(alpha: 0.1),
        side: BorderSide(color: c.withValues(alpha: 0.6)),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    ),
  );

  Widget _footer() {
    final bad = _badJersey;
    final missing = bad
        .where((id) => (_jersey[id]?.text.trim() ?? '').isEmpty)
        .length;
    final dup = bad.length > missing;
    final ready = _starters.length == _startingLimit && bad.isEmpty;
    final label = ready
        ? 'KAYDET'
        : missing > 0
        ? "KAYDET · $missing oyuncunun forma no'su eksik"
        : dup
        ? 'KAYDET · aynı forma no iki kez'
        : 'KAYDET · İlk 11 ${_starters.length}/$_startingLimit';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: ready ? _green : const Color(0xFFB45309),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Forma numarası kutusu: sarı kesik çerçeve ve köşede ✎. Dokununca numara
/// seçili gelir, yazılan rakam eskisinin yerine geçer; en fazla iki hane.
class _JerseyBox extends StatelessWidget {
  const _JerseyBox({
    required this.controller,
    required this.bad,
    required this.small,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool bad;
  final bool small;
  final VoidCallback onChanged;

  static const _gold = Color(0xFFFBBF24);
  static const _red = Color(0xFFF87171);

  void _selectAll() {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = bad ? _red : _gold;
    final w = small ? 26.0 : 34.0;
    final h = small ? 19.0 : 28.0;
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _DashedBorder(color: c.withValues(alpha: 0.7)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.withValues(alpha: bad ? 0.14 : 0.07),
                  borderRadius: BorderRadius.circular(small ? 4 : 6),
                ),
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  textAlign: TextAlign.center,
                  textAlignVertical: TextAlignVertical.center,
                  onTap: () {
                    _selectAll();
                    // Odak alınca imleç sona gidebilir; bir kare sonra yine seç.
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _selectAll(),
                    );
                  },
                  onChanged: (_) => onChanged(),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: small ? 11 : 13.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  // Tema dolgu ve boşluk vermesin (küçük kutuda numara
                  // görünmez oluyordu).
                  decoration: InputDecoration(
                    isCollapsed: true,
                    isDense: true,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: '#',
                    hintStyle: TextStyle(color: c.withValues(alpha: 0.7)),
                  ),
                ),
              ),
            ),
          ),
          if (!small)
            Positioned(
              right: -4,
              top: -5,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.all(1),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.edit_rounded, size: 9, color: c),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Yuvarlak köşeli kesik çizgi çerçeve.
class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(6.0, size.height / 3);
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(r),
        ).deflate(0.75),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 3, m.length)), paint);
        d += 5.5;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
