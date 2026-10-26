import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/service_locator.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/app_name_band.dart';
import '../../identity/identity_access.dart';
import '../../identity/identity_service.dart';
import '../../identity/identity_verify_screen.dart';
import '../../identity/verified_badge.dart';
import '../../player/services/penalty_service.dart';
import '../../tournament/models/age_rules.dart';
import '../../tournament/screens/formation_tab.dart';
import '../models/match.dart';
import '../utils/season_match_settings.dart';
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

/// Aşılan bir kontenjan kuralı: başlık, ilgili oyuncular ve çözüm.
class _QuotaIssue {
  const _QuotaIssue(this.title, this.ids, this.fix);

  final String title;
  final List<String> ids;
  final String fix;
}

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

  /// Ekran açıldığında (ya da son kayıtta) kayıtlı esamenin özeti. Kayıtta
  /// sunucudaki hâl bundan farklıysa esameyi başka bir sorumlu değiştirmiştir.
  String? _baseSig;

  /// Numarası yazılan oyuncu: satırı vurgulanır, klavyenin üstündeki
  /// şeritte adı görünür.
  String? _editingId;

  int _startingLimit = 11;
  int _subLimit = 7;
  Map<String, PlayerPenalty> _penalized = const {};
  AgeRules _ageRules = const AgeRules();

  /// Sezonda onaylı kimlik zorunlu mu; zorunluysa onaysız oyuncu esameye
  /// eklenemez.
  bool _requireId = false;
  Set<String> _verified = const {};

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

  /// Sezonda kağıttan okuma açık mı (Yapay Zekâ Yönetimi).
  late bool _aiEsame =
      SeasonMatchSettings.cached(widget.match.seasonId)?.aiEsame ?? true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadCaptainHint();
    SeasonMatchSettings.of(widget.match.seasonId).then((s) {
      if (mounted && s.aiEsame != _aiEsame) {
        setState(() => _aiEsame = s.aiEsame);
      }
    });
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

  static String _sigOf(Iterable<(String, bool, String?, bool)> rows) {
    final parts = [
      for (final r in rows)
        '${r.$1}|${r.$2 ? 1 : 0}|${(r.$3 ?? '').trim()}|${r.$4 ? 1 : 0}',
    ]..sort();
    return parts.join(',');
  }

  /// Sunucudaki güncel esamenin özeti.
  Future<String> _serverSig() async {
    final rows = await Supabase.instance.client
        .from('match_rosters')
        .select('player_id, is_starting, jersey_number, is_captain')
        .eq('match_id', widget.match.id)
        .eq('team_id', widget.teamId);
    return _sigOf([
      for (final r in rows)
        (
          r['player_id'].toString(),
          r['is_starting'] == true,
          r['jersey_number']?.toString(),
          r['is_captain'] == true,
        ),
    ]);
  }

  /// Esameyi sunucudan yeniden yükler (yerel değişiklikler atılır).
  Future<void> _reload() async {
    setState(() {
      _isLoading = true;
      _starters.clear();
      _subs.clear();
      _captainId = null;
      for (final c in _jersey.values) {
        c.dispose();
      }
      _jersey.clear();
      _dirty = false;
    });
    await _loadData();
  }

  Future<void> _loadData() async {
    try {
      Future<Map<String, dynamic>?> loadSeasonLimits() async {
        if (widget.match.seasonId.isEmpty) return null;
        try {
          return await Supabase.instance.client
              .from('seasons')
              .select(
                'starting_player_count, sub_player_count, age_rules, '
                'require_verified_id',
              )
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
        _requireId = sRes?['require_verified_id'] == true;
        _players = [...players]..sort(_compare);
        _byId = {for (final p in _players) p.id: p};
        _penalized = penalties;
        _baseSig = _sigOf([
          for (final r in rosters)
            (r.playerId, r.isStarting, r.jerseyNumber, r.isCaptain),
        ]);
        // Esame sırası kayıtlıysa (list_order) aynen o sırayla açılır.
        final ordered = rosters.every((r) => r.listOrder != null)
            ? ([...rosters]
                ..sort((a, b) => a.listOrder!.compareTo(b.listOrder!)))
            : const <MatchRosterModel>[];
        for (final r in ordered) {
          if (!_byId.containsKey(r.playerId)) continue;
          (r.isStarting ? _starters : _subs).add(r.playerId);
        }
        // Kayıtlı kaleci (pos_x = 0) ilk sırada.
        final gk = ordered.isNotEmpty
            ? null
            : rosters.where((x) => x.isStarting && x.slot == 0).firstOrNull;
        if (gk != null && _byId.containsKey(gk.playerId)) {
          _starters.add(gk.playerId);
        }
        for (final p in _players) {
          final r = rosters.where((x) => x.playerId == p.id).firstOrNull;
          if (r != null && !_starters.contains(p.id) && !_subs.contains(p.id)) {
            (r.isStarting ? _starters : _subs).add(p.id);
          }
          if (r != null && r.isCaptain && r.isStarting) _captainId = p.id;
          _jersey[p.id] = TextEditingController(
            text: r?.jerseyNumber ?? p.number ?? '',
          );
        }
        _isLoading = false;
      });
      _loadVerified();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadVerified() async {
    // Özellik gizliyken (ve sezon istemiyorsa) tik gösterilmez.
    if (!_requireId && !IdentityAccess.visibleIn(context)) return;
    try {
      final v = await IdentityService.verifiedAmong(_players.map((p) => p.id));
      if (mounted) setState(() => _verified = v);
    } catch (_) {}
  }

  /// Sezon onaylı kimlik istiyor ve oyuncunun kimliği onaylı değil.
  bool _unverified(String id) => _requireId && !_verified.contains(id);

  /// Esameden "Kimliği okut": doğrulama ekranı açılır, dönünce liste
  /// yenilenir.
  Future<void> _verifyPlayer(PlayerModel p) async {
    await IdentityVerifyScreen.open(
      context,
      expectedPlayerId: p.id,
      expectedName: p.name,
    );
    if (!mounted) return;
    await _loadVerified();
    if (mounted && _verified.contains(p.id)) {
      _toast('${p.name} onaylandı; esameye ekleyebilirsiniz.');
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

  /// Esamede [i]. kontenjandan (kaleci dışı) olan oyuncular.
  List<String> _quotaIds(int i) => [..._starters, ..._subs].where((id) {
    final p = _byId[id]!;
    final c = _ageRules.check(
      birthYear: AgeRules.birthYearOf(p.birthDate),
      isGk: (p.mainPosition ?? '').trim() == 'Kaleci',
    );
    return c.status == AgeStatus.quota && c.quotaIndex == i;
  }).toList();

  /// Sezonun maç günü kontenjan sınırlarından aşılanlar (kural yoksa boş).
  List<_QuotaIssue> get _quotaIssues {
    if (!_ageRules.hasMatchLimits) return const [];
    final issues = <_QuotaIssue>[];
    for (var i = 0; i < _ageRules.quotas.length; i++) {
      final q = _ageRules.quotas[i];
      final max = q.matchMax;
      if (q.gk || max == null) continue;
      final ids = _quotaIds(i);
      if (ids.length > max) {
        issues.add(
          _QuotaIssue(
            '${q.yearsLabel} doğumlu: esamede en fazla $max, şu an '
                '${ids.length}',
            ids,
            '${ids.length - max} oyuncuyu esameden çıkarın.',
          ),
        );
      }
    }
    final field = _starters.where((id) => _isQuota(_byId[id]!)).toList();
    final fieldMax = _ageRules.matchFieldMax;
    if (fieldMax != null && field.length > fieldMax) {
      issues.add(
        _QuotaIssue(
          "İlk 11'de en fazla $fieldMax kontenjan oyuncusu, şu an "
              '${field.length}',
          field,
          '${field.length - fieldMax} oyuncuyu yedeğe alın ya da esameden '
              'çıkarın.',
        ),
      );
    }
    final squad = [
      ..._starters,
      ..._subs,
    ].where((id) => _isQuota(_byId[id]!)).toList();
    final squadMax = _ageRules.matchMax;
    if (squadMax != null && squad.length > squadMax) {
      issues.add(
        _QuotaIssue(
          'Esamede en fazla $squadMax kontenjan oyuncusu, şu an '
              '${squad.length}',
          squad,
          '${squad.length - squadMax} oyuncuyu esameden çıkarın.',
        ),
      );
    }
    return issues;
  }

  /// Kaydetmeyi engelleyen kontenjan aşımı açıklaması.
  Future<void> _showQuotaDialog(List<_QuotaIssue> issues) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: adminDialogDecoration(),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline_rounded, color: _red, size: 22),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Esame kaydedilemedi',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 14),
                const Text(
                  'Sezonun kontenjan kuralına uymuyor. Kırmızı işaretli '
                  'oyuncuları düzenleyip tekrar kaydedin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13.5),
                ),
                const SizedBox(height: 14),
                for (final issue in issues)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                    decoration: BoxDecoration(
                      color: _red.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          issue.title,
                          style: const TextStyle(
                            color: _red,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          issue.ids.map((id) => _byId[id]!.name).join(', '),
                          style: const TextStyle(
                            color: Color(0xFFFECACA),
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          issue.fix,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                AdminPrimaryButton(
                  label: 'DÜZENLE',
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
    if (_unverified(id)) {
      _toast(
        'Kimliği onaylı değil; bu sezonda esameye eklenemez. Önce '
        'kimliğini okutun.',
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
    final unverified = <String>[];
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
        if (_unverified(pid)) {
          unverified.add(_byId[pid]!.name);
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
      if (_quotaIssues.isNotEmpty)
        'Kontenjan sınırı aşıldı. Kırmızı işaretli oyuncuları düzenleyin.'
      else
        'Esame kağıttan dolduruldu. Kontrol edip Kaydet\'e basın.',
      if (skipped.isNotEmpty) 'Cezalı, eklenmedi: ${skipped.join(', ')}.',
      if (unverified.isNotEmpty)
        'Kimliği onaylı değil, eklenmedi: ${unverified.join(', ')}.',
      if (overflow > 0)
        '$overflow oyuncu için İlk 11 ve yedeklerde yer kalmadı.',
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
    final issues = _quotaIssues;
    if (issues.isNotEmpty) {
      await _showQuotaDialog(issues);
      return false;
    }
    // Kaptan seçilmeden kaydedilmez: uyarı pazubant seçimine götürür.
    if (close && _starters.isNotEmpty && _captainId == null) {
      final pick = await showAdminConfirmDialog(
        context: context,
        title: 'Kaptan seçilmedi',
        message: "Kaydetmeden önce İlk 11'den takım kaptanını seçin.",
        confirmLabel: 'KAPTAN SEÇ',
        destructive: false,
        icon: Icons.shield_outlined,
      );
      if (!pick || !mounted) return false;
      await _pickCaptain();
      if (_captainId == null || !mounted) return false;
    }
    final ids = [..._starters, ..._subs];
    final notVerified = ids.where(_unverified).toList();
    if (notVerified.isNotEmpty) {
      await showAdminInfoDialog(
        context: context,
        title: 'Kimliği onaylı olmayan oyuncu',
        message:
            'Bu sezonda esameye yalnız kimliği onaylı oyuncular eklenebilir: '
            '${notVerified.map((id) => _byId[id]?.name ?? '').join(', ')}. '
            'Kimliklerini okutun ya da esameden çıkarın.',
      );
      return false;
    }
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
    // Aynı esameyi iki sorumlu birlikte düzenlerse sonraki kayıt öncekini
    // ezmesin: açıldığından beri değiştiyse kaydetmeden haber ver.
    try {
      if (_baseSig != null && await _serverSig() != _baseSig) {
        if (!mounted) return false;
        setState(() => _isSaving = false);
        final reload = await showAdminConfirmDialog(
          context: context,
          title: 'Esame değişti',
          message:
              'Bu kayıt, siz düzenlerken başka bir sorumlu tarafından '
              'düzenlendi. Güncel esameyi yükleyip değişikliklerinizi '
              'yeniden yapın.',
          confirmLabel: 'GÜNCEL ESAMEYİ YÜKLE',
          destructive: false,
          icon: Icons.sync_problem_rounded,
        );
        if (reload && mounted) await _reload();
        return false;
      }
    } catch (_) {
      // Kontrol yapılamazsa kayıt eskisi gibi devam eder.
    }
    if (!mounted) return false;
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
      _baseSig = _sigOf([
        for (final r in rosters)
          (r.playerId, r.isStarting, r.jerseyNumber, r.isCaptain),
      ]);
      if (mounted && close) Navigator.pop(context, true);
      return true;
    } catch (e) {
      final msg =
          e is PostgrestException && e.message.contains('KIMLIK_ONAYSIZ')
          ? e.message.replaceFirst('KIMLIK_ONAYSIZ: ', '')
          : 'Hata: $e';
      if (mounted) _toast(msg);
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
      // Pencere sürüklenince sahadaki oyuncu sürüklemesiyle çakışıyor.
      enableDrag: false,
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

  /// Geri tuşu: kaydedip çık (numara eksik/aynıysa uyarı verir, ekranda
  /// kalır), kaydetmeden çık ya da çarpıyla esameye dön.
  Future<void> _confirmLeave() async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: AdminDialogCloseOverlay(
          onClose: () => Navigator.pop(ctx),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: adminDialogDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.circle, color: kAdminAmber, size: 12),
                      SizedBox(width: 8),
                      Text(
                        'Kaydedilmedi',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 16),
                const Text(
                  'Esamede yaptığınız değişiklikler kaydedilmedi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 22),
                AdminPrimaryButton(
                  label: 'KAYDET VE ÇIK',
                  onPressed: () => Navigator.pop(ctx, true),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kAdminDanger,
                      side: BorderSide(
                        color: kAdminDanger.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(
                      'KAYDETMEDEN ÇIK',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice) {
      await _save(); // başarılıysa kendisi kapatır
    } else {
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
            if (_aiEsame && !_isLoading && _players.isNotEmpty)
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
        body: Stack(
          children: [
            Positioned.fill(
              child: _isLoading
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
            if (keyboard > 0 && _byId[_editingId] != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: keyboard,
                child: _numberStrip(_byId[_editingId]!),
              ),
          ],
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

  static const _captainHintKey = 'esame_captain_hint_hidden';

  /// Kaptan ipucu bir kez kapatılınca bu cihazda bir daha gösterilmez.
  bool _showCaptainHint = false;

  Future<void> _loadCaptainHint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hidden = prefs.getBool(_captainHintKey) ?? false;
      if (mounted && !hidden) setState(() => _showCaptainHint = true);
    } catch (_) {}
  }

  Future<void> _hideCaptainHint() async {
    setState(() => _showCaptainHint = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_captainHintKey, true);
    } catch (_) {}
  }

  Widget _captainHint() => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.fromLTRB(9, 6, 2, 6),
    decoration: BoxDecoration(
      color: _green.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: _green.withValues(alpha: 0.5)),
    ),
    child: Row(
      children: [
        _tag('C', _green),
        const SizedBox(width: 7),
        const Expanded(
          child: Text.rich(
            TextSpan(
              text: 'Kaptanı seçmek için ',
              children: [
                TextSpan(
                  text: 'kırmızı-beyaz pazubant',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: ' düğmesine dokunun.'),
              ],
            ),
            style: TextStyle(
              color: Color(0xFFA7F3D0),
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _hideCaptainHint,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Icon(Icons.close_rounded, size: 16, color: _mid),
          ),
        ),
      ],
    ),
  );

  /// Kontenjan paneli (yalnız sezonda maç günü sınırı varsa), kaptan ipucu
  /// ve diziliş / otomatik numara düğmeleri.
  Widget _topLine() {
    Widget? quota;
    if (_ageRules.hasMatchLimits) {
      final onField = _starters.where((id) => _isQuota(_byId[id]!)).length;
      final inSquad =
          onField + _subs.where((id) => _isQuota(_byId[id]!)).length;
      final maxSquad = _ageRules.matchMax;
      final maxField = _ageRules.matchFieldMax;
      Widget chip(String label, int n, int max) {
        final bad = n > max;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: bad
                ? _red.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text.rich(
            TextSpan(
              text: '$label ',
              style: TextStyle(
                color: bad ? _red : _mid,
                fontWeight: FontWeight.w600,
              ),
              children: [
                TextSpan(
                  text: '$n/$max',
                  style: TextStyle(
                    color: bad ? _red : _gold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            style: const TextStyle(
              fontSize: 11.5,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        );
      }

      // Kontenjan bazında esame sınırı (ör. 1988 en fazla 2, 1989 en fazla 1).
      final chips = <Widget>[
        for (var i = 0; i < _ageRules.quotas.length; i++)
          if (!_ageRules.quotas[i].gk && _ageRules.quotas[i].matchMax != null)
            chip(
              _ageRules.quotas[i].yearsLabel,
              _quotaIds(i).length,
              _ageRules.quotas[i].matchMax!,
            ),
        if (maxField != null) chip("İlk 11", onField, maxField),
        if (maxSquad != null) chip('Esame toplam', inSquad, maxSquad),
      ];
      final over = _quotaIssues.isNotEmpty;
      final c = over ? _red : _gold;
      quota = Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
        decoration: BoxDecoration(
          color: c.withValues(alpha: over ? 0.12 : 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withValues(alpha: over ? 0.6 : 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'KONTENJAN',
                  style: TextStyle(
                    color: c,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                Text(
                  over ? 'SINIR AŞILDI' : 'KURALA UYGUN',
                  style: TextStyle(
                    color: c,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 5, runSpacing: 5, children: chips),
          ],
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
          if (_showCaptainHint) _captainHint(),
          Row(
            children: [
              _captainButton(),
              const SizedBox(width: 8),
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

  /// Kırmızı-beyaz pazubant: kaptan seçimi. Kaptan seçiliyse yeşil çerçeve.
  Widget _captainButton() {
    final set = _captainId != null && _starters.contains(_captainId);
    return Tooltip(
      message: 'Kaptan seç',
      child: Material(
        color: const Color(0xFFDC2626).withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(
            color: set
                ? _green
                : const Color(0xFFDC2626).withValues(alpha: 0.6),
            width: set ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: _isSaving ? null : _pickCaptain,
          child: SizedBox(
            width: 52,
            height: 34,
            child: Center(child: _armband(size: 20)),
          ),
        ),
      ),
    );
  }

  /// Kaptan pazubandı: kırmızı zemin, beyaz şerit ve "C".
  static Widget _armband({double size = 20}) => Container(
    width: size * 1.5,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFDC2626),
      borderRadius: BorderRadius.circular(size * 0.22),
      border: Border.all(color: Colors.white, width: size * 0.09),
    ),
    alignment: Alignment.center,
    child: Text(
      'C',
      style: TextStyle(
        color: Colors.white,
        fontSize: size * 0.68,
        fontWeight: FontWeight.w900,
        height: 1,
      ),
    ),
  );

  /// İlk 11'den kaptan seçimi.
  Future<void> _pickCaptain() async {
    FocusScope.of(context).unfocus();
    if (_starters.isEmpty) {
      _toast("Önce İlk 11'e oyuncu ekleyin.");
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: _bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  _armband(size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Kaptanı Seçin',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                children: [
                  for (final id in _starters)
                    if (_byId[id] != null)
                      ListTile(
                        onTap: () => Navigator.pop(ctx, id),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        tileColor: id == _captainId
                            ? _green.withValues(alpha: 0.12)
                            : null,
                        leading: SizedBox(
                          width: 30,
                          child: Text(
                            _jersey[id]?.text.trim() ?? '',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _mid,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        title: Text(
                          _byId[id]!.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        trailing: id == _captainId ? _armband(size: 16) : null,
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _captainId = picked;
      _dirty = true;
    });
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
    final over = {for (final q in _quotaIssues) ...q.ids};
    // Kutu oyuncu geldikçe uzar: dolu satırlar + bir boş bırakma satırı
    // (doluysa yok). İki kutu aynı yükseklikte: kısa olan boşlukla tamamlanır.
    int shown(List<String> l, int lim) => math.min(lim, l.length + 1);
    final rows = math.max(
      shown(_starters, _startingLimit),
      shown(_subs, _subLimit),
    );
    final own = shown(list, limit);
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
            i < own
                ? _slot(box, i, list, bad, over)
                : const SizedBox(height: _slotH + 1),
        ],
      ),
    );
  }

  /// [over]: kontenjan sınırını aşan oyuncular (satır kırmızı çerçeveli).
  Widget _slot(
    _Box box,
    int i,
    List<String> list,
    Set<String> bad,
    Set<String> over,
  ) {
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
                active: id == _editingId,
                onChanged: _onJerseyChanged,
                onFocusChange: (f) => _onJerseyFocus(id, f),
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
        final editing = id != null && id == _editingId;
        final quotaOver = id != null && over.contains(id);
        final row = Container(
          height: _slotH,
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.only(left: 3),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: hover
                ? Colors.white.withValues(alpha: 0.14)
                : editing
                ? _gold.withValues(alpha: 0.16)
                : quotaOver
                ? _red.withValues(alpha: 0.14)
                : id == null
                ? Colors.white.withValues(alpha: 0.02)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: editing
                  ? _gold
                  : quotaOver
                  ? _red.withValues(alpha: 0.7)
                  : Colors.transparent,
              width: 1.5,
            ),
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
              style: TextStyle(
                color: p.id == _editingId ? _gold : Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (isGk) _tag('KL', _gold),
          if (isCap) _tag('C', _green),
          if (_ageRules.hasMatchLimits && _isQuota(p)) _tag('KONT.', _gold),
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

  void _onJerseyFocus(String id, bool focused) {
    if (focused) {
      setState(() => _editingId = id);
    } else if (_editingId == id) {
      setState(() => _editingId = null);
    }
  }

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

  /// Klavyenin üstünde: kimin numarası yazılıyor (klavye kutuyu örtse de).
  Widget _numberStrip(PlayerModel p) {
    final no = _jersey[p.id]?.text.trim() ?? '';
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Color.lerp(_bg, _gold, 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _gold.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Text(
            'Forma no · ',
            style: TextStyle(color: _mid, fontSize: 13),
          ),
          Expanded(
            child: Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _gold,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            no.isEmpty ? '–' : no,
            style: const TextStyle(
              color: _gold,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
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
          padding: EdgeInsets.fromLTRB(
            10,
            0,
            10,
            12 + keyboard + (keyboard > 0 ? 50 : 0),
          ),
          children: children,
        ),
      ),
    );
  }

  Widget _squadRow(PlayerModel p) {
    final pen = _penalized[p.id];
    final noId = pen == null && _unverified(p.id);
    final sub = (p.position ?? '').trim();
    final editing = p.id == _editingId;
    final row = Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: editing
            ? _gold.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: editing ? _gold : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          pen != null || noId
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
            active: editing,
            onChanged: _onJerseyChanged,
            onFocusChange: (f) => _onJerseyFocus(p.id, f),
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
                color: editing
                    ? _gold
                    : pen != null || noId
                    ? Colors.white38
                    : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_verified.contains(p.id))
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: VerifiedBadge(size: 15),
            ),
          if (_ageRules.hasMatchLimits && _isQuota(p))
            _tag('KONTENJAN ${AgeRules.birthYearOf(p.birthDate)}', _gold),
          const SizedBox(width: 6),
          if (noId)
            kIsWeb
                ? _tag('KİMLİK ONAYSIZ', _mid)
                : _addButton(
                    'Kimliği okut',
                    kVerifiedBlue,
                    () => _verifyPlayer(p),
                  )
          else if (pen != null)
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
    if (pen != null || noId) return row;
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
    required this.onFocusChange,
    this.active = false,
  });

  final TextEditingController controller;
  final bool bad;
  final bool small;
  final VoidCallback onChanged;
  final ValueChanged<bool> onFocusChange;

  /// Numarası şu an yazılıyor: kutu dolu sarı.
  final bool active;

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
                  color: active ? c : c.withValues(alpha: bad ? 0.14 : 0.07),
                  borderRadius: BorderRadius.circular(small ? 4 : 6),
                ),
                child: Focus(
                  onFocusChange: onFocusChange,
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
                      color: active ? const Color(0xFF1F1300) : Colors.white,
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
                      hintStyle: TextStyle(
                        color: active
                            ? const Color(0xFF1F1300)
                            : c.withValues(alpha: 0.7),
                      ),
                    ),
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
