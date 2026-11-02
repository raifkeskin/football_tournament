import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../../../core/services/photo_cutouts.dart';

import '../../match/insights/insight_widgets.dart';
import '../../match/insights/match_insights.dart';
import 'package:football_tournament/features/tournament/utils/pitch_layout.dart';
import 'package:football_tournament/core/widgets/pitch_token_style.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../match/models/match.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/services/service_locator.dart';
import '../../match/services/supabase/supabase_match_service.dart';

const _accent = Color(0xFF10B981);
const _midText = Color(0xFF94A3B8);

/// Oyuncunun mevkisinden saha hattını çıkarır:
/// 0 = Kaleci, 1 = Defans, 2 = Orta Saha, 3 = Forvet.
/// Hem ana mevki ('Defans') hem alt mevki ('Stoper') hem de eski serbest
/// değerler ('Sol Bek', 'On Numara', 'Kanat') desteklenir.
int positionLineOf(String? mainPosition, String? subPosition) {
  String n(String? s) => (s ?? '').trim().toLowerCase();
  final main = n(mainPosition);
  final sub = n(subPosition);
  for (final p in [main, sub]) {
    if (p.isEmpty) continue;
    if (p.contains('kaleci') || p == 'gk') return 0;
    if (p.contains('forvet') || p.contains('santrfor') || p == 'for') {
      return 3;
    }
    if (p.contains('defans') ||
        p.contains('stoper') ||
        p.contains('bek') ||
        p == 'def') {
      return 1;
    }
    if (p.contains('orta') ||
        p.contains('numara') ||
        p.contains('kanat') ||
        p.contains('merkez') ||
        p == 'ort') {
      return 2;
    }
  }
  return 2; // bilinmeyen mevki: orta saha
}

const positionLineLabels = ['Kaleci', 'Defans', 'Orta Saha', 'Forvet'];
const positionLineShort = ['KL', 'DF', 'OS', 'FV'];

/// "Enis Çalkın" -> "Enis Ç."
String shortPlayerName(String raw) {
  final parts = raw
      .trim()
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .toList();
  if (parts.length <= 1) return raw.trim();
  return '${parts.first} ${parts.last.substring(0, 1)}.';
}

/// Kaptan pazubandı: kırmızı zemin üzerinde beyaz "C".
class CaptainBadge extends StatelessWidget {
  const CaptainBadge({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626),
        borderRadius: BorderRadius.circular(size * 0.25),
        border: Border.all(color: Colors.white70, width: 0.8),
      ),
      child: Text(
        'C',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.68,
          height: 1,
        ),
      ),
    );
  }
}

/// Hat içinde kenar oyuncuları (bek, kanat) yanlara, merkezdekileri ortaya
/// yerleştirmek için.
bool _isWide(String? main, String? sub) {
  final s = '${main ?? ''} ${sub ?? ''}'.toLowerCase();
  return s.contains('bek') || s.contains('kanat');
}

int _jersey(String? n) => int.tryParse((n ?? '').trim()) ?? 999;

class _PitchPlayer {
  const _PitchPlayer({
    required this.id,
    required this.name,
    required this.number,
    required this.line,
    required this.wide,
    required this.isCaptain,
    this.photoUrl,
  });

  final String id;
  final String name;
  final String number;
  final int line;
  final bool wide;
  final bool isCaptain;
  final String? photoUrl;
}

List<int> _parseFormation(String f) => f
    .split('-')
    .map((e) => int.tryParse(e.trim()) ?? 0)
    .where((e) => e > 0)
    .toList();

/// Hattı kenar oyuncular iki uca, merkezdekiler ortaya gelecek şekilde dizer.
List<_PitchPlayer> _arrangeLine(List<_PitchPlayer> line) {
  final sorted = [...line]
    ..sort((a, b) => _jersey(a.number).compareTo(_jersey(b.number)));
  final wide = sorted.where((e) => e.wide).toList();
  final center = sorted.where((e) => !e.wide).toList();
  final half = (wide.length / 2).ceil();
  return [...wide.take(half), ...center, ...wide.skip(half)];
}

const _classic10 = [
  '4-4-2',
  '4-3-3',
  '4-2-3-1',
  '4-5-1',
  '4-1-4-1',
  '3-5-2',
  '3-4-3',
  '5-3-2',
  '5-4-1',
];

/// Saha oyuncusu sayısına uygun diziliş seçenekleri. 11'li maçta yalnız
/// klasik dizilişler; küçük sahada üç hatlı tüm kombinasyonlar.
List<String> _formationOptions(int outfield) {
  if (outfield == 10) return [..._classic10];
  final out = <String>[];
  if (outfield >= 3) {
    for (var d = 1; d <= outfield - 2; d++) {
      for (var m = 1; m <= outfield - d - 1; m++) {
        out.add('$d-$m-${outfield - d - m}');
      }
    }
  }
  return out;
}

/// Mevkilerden çıkan diziliş (ör. 2-1-8) seçeneklerde yoksa ona en yakın
/// geçerli dizilişi döner: defans, orta saha toplamı ve hücum farkı en az
/// olan; eşitlikte listede önce gelen (daha yaygın) seçilir.
String _snapFormation(String formation, int outfield) {
  final options = _formationOptions(outfield);
  if (options.isEmpty || options.contains(formation)) return formation;
  (int, int, int) shape(String f) {
    final c = _parseFormation(f);
    if (c.isEmpty) return (0, 0, 0);
    if (c.length == 1) return (c.first, 0, 0);
    final mid = c.sublist(1, c.length - 1).fold<int>(0, (a, b) => a + b);
    return (c.first, mid, c.last);
  }

  final (d, m, a) = shape(formation);
  var best = options.first;
  var bestDist = 1 << 30;
  for (final o in options) {
    final (od, om, oa) = shape(o);
    final dist = (od - d).abs() + (om - m).abs() + (oa - a).abs();
    if (dist < bestDist) {
      best = o;
      bestDist = dist;
    }
  }
  return best;
}

class _Layout {
  const _Layout({
    required this.lines,
    required this.formation,
    required this.autoFormation,
    required this.outfieldCount,
    required this.ids,
  });

  /// lines[0]: kaleci, sonrakiler defanstan hücuma hatlar.
  final List<List<_PitchPlayer>> lines;
  final String formation;
  final String autoFormation;
  final int outfieldCount;

  /// Saha sırasıyla oyuncu id'leri (kaleci → defans → orta saha → forvet).
  final List<String> ids;
}

/// İlk 11'in sahadaki yerleşimi. Sıra önceliği: [order] (ekranda yapılan
/// değişiklik) → kaydedilmiş saha sırası (pos_x) → mevkilere göre otomatik.
_Layout? _computeLayout(
  List<MatchRosterModel> starterRosters,
  Map<String, PlayerModel> players, {
  String? formation,
  List<String>? order,
}) {
  // Esamede ilk seçilen oyuncu kaleci olarak kaydedilir (pos_x = 0); saha
  // sırası henüz kaydedilmemişse mevkisi ne olursa olsun kaleye geçer.
  final fullySlotted =
      starterRosters.every((r) => r.slot != null) &&
      starterRosters.map((r) => r.slot).toSet().length == starterRosters.length;
  final keepers = starterRosters.where((r) => r.slot == 0).toList();
  final chosenGk = !fullySlotted && keepers.length == 1
      ? keepers.first.playerId
      : null;
  final starters = starterRosters.map((r) {
    final p = players[r.playerId];
    final natural = positionLineOf(p?.mainPosition, p?.position);
    return _PitchPlayer(
      id: r.playerId,
      name: (p?.name ?? '').trim().isEmpty ? '-' : p!.name,
      number: (r.jerseyNumber ?? p?.number ?? '').trim(),
      line: chosenGk == null
          ? natural
          : (r.playerId == chosenGk ? 0 : (natural == 0 ? 1 : natural)),
      wide: _isWide(p?.mainPosition, p?.position),
      isCaptain: r.isCaptain,
      photoUrl: p?.photoUrl,
    );
  }).toList();
  if (starters.isEmpty) return null;

  // Mevkiye göre doğal hatlar (kaleci birden fazlaysa fazlası defansa).
  final natural = List.generate(4, (_) => <_PitchPlayer>[]);
  for (final p in starters) {
    natural[p.line].add(p);
  }
  while (natural[0].length > 1) {
    natural[1].add(natural[0].removeLast());
  }
  if (natural[0].isEmpty) {
    // Kaleci yoksa en düşük numaralı oyuncu kaleye.
    final all = [...natural[1], ...natural[2], ...natural[3]]
      ..sort((a, b) => _jersey(a.number).compareTo(_jersey(b.number)));
    final gk = all.first;
    for (final l in natural) {
      l.remove(gk);
    }
    natural[0].add(gk);
  }
  final outfieldCount = starters.length - 1;
  // Mevkiler gerçek dışı bir diziliş verirse (ör. 8 forvet → 2-1-8) en
  // yakın geçerli dizilişe yuvarlanır.
  final autoFormation = _snapFormation(
    natural.skip(1).map((l) => l.length).where((c) => c > 0).join('-'),
    outfieldCount,
  );

  // 11'li maçta kayıtlı diziliş yoksa 4-2-3-1 (sahada en yaygın dizilim);
  // küçük sahada mevkilerden çıkan diziliş.
  final fallback = outfieldCount == 10 ? '4-2-3-1' : autoFormation;
  var f = (formation ?? '').trim().isEmpty ? fallback : formation!.trim();
  var counts = _parseFormation(f);
  final options = _formationOptions(outfieldCount);
  if (counts.fold<int>(0, (a, b) => a + b) != outfieldCount ||
      (options.isNotEmpty && !options.contains(f))) {
    // Kadro değiştiyse ya da kayıtlı diziliş geçersizse varsayılan.
    f = fallback;
    counts = _parseFormation(f);
  }

  // Saha oyuncularını defanstan hücuma dizilişin hatlarına dağıt.
  final outfield = [
    for (var li = 1; li < 4; li++) ..._arrangeLine(natural[li]),
  ];
  final baseLines = <List<_PitchPlayer>>[natural[0]];
  var idx = 0;
  for (final c in counts) {
    baseLines.add(_arrangeLine(outfield.sublist(idx, idx + c)));
    idx += c;
  }

  final baseIds = [for (final l in baseLines) ...l.map((e) => e.id)];
  bool sameSet(List<String> ids) =>
      ids.length == baseIds.length && ids.toSet().containsAll(baseIds);
  final slotted = fullySlotted
      ? ([...starterRosters]..sort((a, b) => a.slot!.compareTo(b.slot!)))
            .map((r) => r.playerId)
            .toList()
      : null;
  var ids = baseIds;
  if (order != null && sameSet(order)) {
    ids = order;
  } else if (slotted != null && sameSet(slotted)) {
    ids = slotted;
  }

  final byId = {for (final p in starters) p.id: p};
  final lines = <List<_PitchPlayer>>[];
  var k = 0;
  for (final l in baseLines) {
    lines.add([for (var i = 0; i < l.length; i++) byId[ids[k++]]!]);
  }
  return _Layout(
    lines: lines,
    formation: f,
    autoFormation: autoFormation,
    outfieldCount: outfieldCount,
    ids: ids,
  );
}

/// Kadrolar sekmesi için: ilk 11 oyuncu id'lerini diziliş sahasındaki
/// sırayla döndürür (kaleci → defans → orta saha → forvet). Oyuncunun
/// kayıtlı mevkisi değil, o maçtaki saha yeri esas alınır.
List<String> starterIdsInFormationOrder({
  required List<MatchRosterModel> starters,
  required Map<String, PlayerModel> players,
  String? formation,
}) {
  return _computeLayout(starters, players, formation: formation)?.ids ??
      const <String>[];
}

/// Diziliş afişi için: dizilişin adı ve hatlara göre ilk 11 oyuncu id'leri
/// (lines[0] kaleci, sonra defanstan hücuma). İlk 11 yoksa null.
({String formation, List<List<String>> lines})? formationLinesFor({
  required List<MatchRosterModel> starters,
  required Map<String, PlayerModel> players,
  String? formation,
}) {
  final l = _computeLayout(starters, players, formation: formation);
  if (l == null) return null;
  return (
    formation: l.formation,
    lines: [
      for (final line in l.lines) [for (final p in line) p.id],
    ],
  );
}

/// Maç detayı "Diziliş" sekmesi: esamedeki ilk 11 sahaya yerleşir.
/// Diziliş seçilmemişse oyuncuların mevkilerinden otomatik hesaplanır;
/// yetkili kullanıcı dizilişi değiştirebilir (matches.home/away_formation).
class FormationTab extends StatefulWidget {
  const FormationTab({
    super.key,
    required this.match,
    required this.homeName,
    required this.awayName,
    required this.canEditHome,
    required this.canEditAway,
    this.canShareHome = false,
    this.canShareAway = false,
    this.initialTeam = 0,
    this.singleTeam = false,
    this.onShare,
    this.homeColor,
    this.awayColor,
    this.embedded = false,
    this.onPlayerTap,
    this.collapsed = false,
    this.onToggleCollapsed,
  });

  /// Gömülü dizilişte gizle/göster: kapalıyken yalnız başlık çubuğu.
  final bool collapsed;
  final VoidCallback? onToggleCollapsed;

  /// Kadro sekmesine gömülü: kaydırma ve kenar boşluğu dışarıda; ilk 11
  /// girilmemişse hiçbir şey çizilmez.
  final bool embedded;

  /// Oyuncuya dokunma (takım, oyuncu, ad, forma no): canlı maçta olay ekleme,
  /// değilse oyuncu kartı. Verilmezse düzenleyen dokunarak yer değiştirir.
  final void Function(
    String teamId,
    String playerId,
    String name,
    String number,
  )?
  onPlayerTap;

  /// Diziliş afişini paylaşır (takım kimliğiyle); [canShareHome] /
  /// [canShareAway] olana görünür (maç başladıktan sonra da).
  final ValueChanged<String>? onShare;

  final MatchModel match;
  final String homeName;
  final String awayName;

  /// Maç başlığındaki takım renkleri (çakışma çözülmüş); seçili takım
  /// düğmesi bu renkle boyanır. Yoksa yeşil.
  final Color? homeColor;
  final Color? awayColor;

  /// Takım başına düzenleme yetkisi: sorumlu yalnızca kendi takımını,
  /// yöneticiler ikisini de düzenler.
  final bool canEditHome;
  final bool canEditAway;
  final bool canShareHome;
  final bool canShareAway;

  /// Açılışta seçili takım (0: ev sahibi, 1: deplasman); sorumlu kendi
  /// takımıyla açar.
  final int initialTeam;

  /// Takım seçimi gizlenir; yalnız [initialTeam] gösterilir (esame
  /// ekranındaki diziliş penceresi).
  final bool singleTeam;

  @override
  State<FormationTab> createState() => _FormationTabState();
}

class _FormationTabState extends State<FormationTab>
    with AutomaticKeepAliveClientMixin {
  // Sekme değişince durum (seçilen diziliş, yerleşim) kaybolmasın.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadSavedFormations();
    PitchTokenStylePref.load();
    PhotoCutouts.ensureLoaded();
  }

  /// Kayıtlı dizilişi doğrudan veritabanından okur; ekranın açılışındaki
  /// maç verisi (widget.match) kayıttan sonra güncel olmayabilir.
  Future<void> _loadSavedFormations() async {
    try {
      final row = await Supabase.instance.client
          .from('matches')
          .select('home_formation, away_formation')
          .eq('id', widget.match.id)
          .maybeSingle();
      if (row == null || !mounted) return;
      final home = (row['home_formation'] ?? '').toString().trim();
      final away = (row['away_formation'] ?? '').toString().trim();
      setState(() {
        if (home.isNotEmpty) _chosen.putIfAbsent(0, () => home);
        if (away.isNotEmpty) _chosen.putIfAbsent(1, () => away);
      });
    } catch (_) {
      // Kolonlar yoksa otomatik diziliş kullanılır.
    }
  }

  late int _selected = widget.initialTeam; // 0: ev sahibi, 1: deplasman

  bool get _canEdit => _selected == 0 ? widget.canEditHome : widget.canEditAway;
  bool get _canShare =>
      _canEdit || (_selected == 0 ? widget.canShareHome : widget.canShareAway);

  /// Kullanıcının bu oturumda seçtiği dizilişler (teamIndex -> "4-4-2").
  final Map<int, String> _chosen = {};

  /// Sürükle-bırak sonrası saha sırası (teamIndex -> slot sırasıyla oyuncu id).
  final Map<int, List<String>> _order = {};

  /// Kaydedilmemiş değişikliği olan takımlar (teamIndex).
  final Set<int> _dirty = {};

  /// Otomatik kayıt: değişiklikten kısa süre sonra arkada kaydedilir; kaydet
  /// düğmesi yok. [_edits] her değişiklikte artar: kayıt sürerken yeni
  /// değişiklik gelirse o da ayrıca kaydedilir.
  Timer? _saveTimer;
  int _edits = 0;
  Future<void>? _inFlight;

  /// Son çizimdeki diziliş ve saha sırası (takım → değerler); zamanlayıcı
  /// bunları kaydeder.
  final Map<int, (String, List<String>)> _latest = {};

  /// Son otomatik kayıt hata verdi; ikona dokununca yeniden denenir.
  bool _saveFailed = false;

  void _changed() {
    _edits++;
    _saveFailed = false;
    _saveTimer?.cancel();
    final team = _selected;
    _saveTimer = Timer(const Duration(milliseconds: 900), () {
      _saveTimer = null;
      _autoSave(team);
    });
  }

  Future<void> _autoSave(int team) {
    final prev = _inFlight ?? Future<void>.value();
    final next = prev.then((_) async {
      final v = _latest[team];
      if (v == null || !_dirty.contains(team)) return;
      await _saveLayout(team, v.$1, v.$2);
    });
    _inFlight = next;
    return next;
  }

  /// Paylaşmadan önce: bekleyen kayıt hemen yapılır, sürüyorsa beklenir.
  Future<void> _flush() async {
    if (_saveTimer != null) {
      _saveTimer!.cancel();
      _saveTimer = null;
      await _autoSave(_selected);
    } else {
      await _inFlight;
    }
  }

  @override
  void dispose() {
    // Ekrandan hızlı çıkılırsa bekleyen kayıt yine gönderilir.
    if (_saveTimer != null) {
      _saveTimer!.cancel();
      for (final team in _dirty) {
        final v = _latest[team];
        if (v != null) _persist(team, v.$1, v.$2).catchError((_) {});
      }
    }
    super.dispose();
  }

  /// Dokunarak yer değiştirmede ilk seçilen oyuncu.
  String? _picked;

  void _pick(List<String> current, String id) {
    final first = _picked;
    if (first == null) {
      setState(() => _picked = id);
      return;
    }
    setState(() => _picked = null);
    if (first != id) _swap(current, first, id);
  }

  bool _saving = false;

  void _swap(List<String> current, String fromId, String toId) {
    if (fromId == toId) return;
    final next = [...current];
    final a = next.indexOf(fromId);
    final b = next.indexOf(toId);
    if (a < 0 || b < 0) return;
    next[a] = toId;
    next[b] = fromId;
    setState(() {
      _order[_selected] = next;
      _dirty.add(_selected);
    });
    _changed();
  }

  /// Dizilişi (matches) ve saha sırasını (match_rosters.pos_x) yazar.
  /// Güncelleme hiçbir satırı etkilemezse (ör. yetki) hata verilir.
  Future<void> _persist(int team, String formation, List<String> ids) async {
    final sb = Supabase.instance.client;
    final teamId = team == 0
        ? widget.match.homeTeamId
        : widget.match.awayTeamId;
    // Yetki kontrolü sunucuda: sorumlu yalnızca kendi takımını yazar.
    await sb.rpc(
      'set_match_formation',
      params: {
        'p_match_id': widget.match.id,
        'p_team_id': teamId,
        'p_formation': formation,
      },
    );
    for (var i = 0; i < ids.length; i++) {
      final r = await sb
          .from('match_rosters')
          .update({'pos_x': i})
          .eq('match_id', widget.match.id)
          .eq('team_id', teamId)
          .eq('player_id', ids[i])
          .select('id');
      if (r.isEmpty) {
        throw Exception('Oyuncu yerleşimi kaydedilemedi (yetki yok).');
      }
    }
    SupabaseMatchService.notifyLocalChange(widget.match.id);
  }

  /// Arkada kaydeder; ekran beklemez, yalnız küçük durum ikonu değişir.
  Future<void> _saveLayout(int team, String formation, List<String> ids) async {
    final edits = _edits;
    setState(() => _saving = true);
    try {
      await _persist(team, formation, ids);
      if (!mounted) return;
      setState(() {
        // Kayıt sürerken yeni değişiklik geldiyse o ayrıca kaydedilecek.
        if (_edits == edits) _dirty.remove(team);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saveFailed = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kaydedilemedi: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _teamId =>
      _selected == 0 ? widget.match.homeTeamId : widget.match.awayTeamId;

  String? get _savedFormation {
    final v = _selected == 0
        ? widget.match.homeFormation
        : widget.match.awayFormation;
    final s = (v ?? '').trim();
    return s.isEmpty ? null : s;
  }

  /// Saha oyuncusu sayısına uygun diziliş seçenekleri.
  static List<String> _optionsFor(int outfield, String auto) {
    final out = _formationOptions(outfield);
    if (out.isEmpty && auto.isNotEmpty) out.add(auto);
    return out;
  }

  void _changeFormation(String value) {
    setState(() {
      _chosen[_selected] = value;
      _order.remove(_selected); // yeni dizilişte otomatik yerleşim
      _picked = null;
      _dirty.add(_selected);
    });
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final teamColor = _selected == 0 ? _accent : const Color(0xFF3B82F6);
    final children = <Widget>[
      if (!widget.singleTeam) ...[
        _TeamSwitch(
          homeName: shortTeamName(widget.homeName),
          awayName: shortTeamName(widget.awayName),
          homeColor: widget.homeColor ?? _accent,
          awayColor: widget.awayColor ?? _accent,
          selected: _selected,
          onChanged: (v) => setState(() {
            _selected = v;
            _picked = null;
          }),
        ),
        const SizedBox(height: 10),
      ],
      MatchInsightsBuilder(
        match: widget.match,
        builder: (context, insights) => StreamBuilder<List<PlayerModel>>(
          key: ValueKey('players_$_teamId'),
          stream: ServiceLocator.teamService.watchPlayers(
            teamId: _teamId,
            tournamentId: widget.match.seasonId,
            matchId: widget.match.id,
          ),
          builder: (context, playerSnap) {
            final players = {
              for (final p in playerSnap.data ?? const <PlayerModel>[]) p.id: p,
            };
            return StreamBuilder<List<MatchRosterModel>>(
              key: ValueKey('roster_$_teamId'),
              stream: ServiceLocator.matchService.watchMatchRosters(
                widget.match.id,
                _teamId,
              ),
              builder: (context, rosterSnap) {
                if (!rosterSnap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final starterRosters = rosterSnap.data!
                    .where((r) => r.isStarting)
                    .toList();
                final layout = _computeLayout(
                  starterRosters,
                  players,
                  formation: _chosen[_selected] ?? _savedFormation,
                  order: _order[_selected],
                );
                if (layout == null) {
                  if (widget.embedded) return const SizedBox.shrink();
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'Henüz ilk 11 girilmemiş.\n'
                        'Kadrolar sekmesinden esame listesi girildiğinde '
                        'oyuncular burada sahaya yerleşir.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  );
                }
                final formation = layout.formation;
                final options = _optionsFor(
                  layout.outfieldCount,
                  layout.autoFormation,
                );
                final pitchLines = layout.lines;
                final currentIds = layout.ids;
                final dirty = _dirty.contains(_selected);
                _latest[_selected] = (formation, currentIds);

                final fold = widget.onToggleCollapsed;
                if (widget.embedded && fold != null && widget.collapsed) {
                  return LineupFoldHeader(open: false, onTap: fold);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.embedded && fold != null) ...[
                      LineupFoldHeader(open: true, onTap: fold),
                      const SizedBox(height: 6),
                    ],
                    Row(
                      children: [
                        if (!widget.embedded || fold == null) ...[
                          const Icon(
                            Icons.grid_view_rounded,
                            color: _midText,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Diziliş',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        _FormationPicker(
                          value: formation,
                          options: options,
                          enabled: _canEdit && options.length > 1,
                          onChanged: _changeFormation,
                        ),
                        const Spacer(),
                        // Gösterim tercihi diziliş afişine de uygulanır.
                        // Yalnız ikon: yazılarla dar ekranda taşıyordu.
                        PitchTokenStyleToggle(
                          compact: true,
                          showPhoto: insights != null,
                        ),
                        if (_canShare && widget.onShare != null)
                          IconButton(
                            tooltip: 'Diziliş afişini paylaş',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 34,
                              minHeight: 34,
                            ),
                            icon: const Icon(
                              Icons.ios_share_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: () async {
                              final teamId = _teamId;
                              await _flush();
                              if (!mounted) return;
                              widget.onShare!(teamId);
                            },
                          ),
                        if (_canEdit) ...[
                          const SizedBox(width: 8),
                          _SaveStatus(
                            dirty: dirty,
                            saving: _saving,
                            failed: _saveFailed,
                            onRetry: () {
                              setState(() => _saveFailed = false);
                              _autoSave(_selected);
                            },
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    AspectRatio(
                      // Kaleciye kadar tüm saha telefon ekranına sığar.
                      aspectRatio: 0.8,
                      child: ValueListenableBuilder<PitchTokenStyle>(
                        valueListenable: PitchTokenStylePref.notifier,
                        builder: (context, style, _) =>
                            ValueListenableBuilder<Map<String, String>>(
                              valueListenable: PhotoCutouts.map,
                              builder: (context, cutouts, _) => _Pitch(
                                lines: pitchLines,
                                cutouts: PhotoCutouts.visible(context)
                                    ? cutouts
                                    : const {},
                                teamColor: teamColor,
                                // Profil yalnız yeni özellik açıkken.
                                style:
                                    style == PitchTokenStyle.photo &&
                                        insights == null
                                    ? PitchTokenStyle.shirt
                                    : style,
                                insights: insights,
                                onSwap: _canEdit
                                    ? (from, to) => _swap(currentIds, from, to)
                                    : null,
                                picked: _picked,
                                onPick: _canEdit
                                    ? (id) => _pick(currentIds, id)
                                    : null,
                                onTapPlayer: widget.onPlayerTap == null
                                    ? null
                                    : (p) => widget.onPlayerTap!(
                                        _teamId,
                                        p.id,
                                        p.name,
                                        p.number,
                                      ),
                              ),
                            ),
                      ),
                    ),
                    if (_canEdit)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          widget.onPlayerTap != null
                              ? 'Yer değiştirmek için oyuncuyu basılı tutup '
                                    'diğerinin üzerine bırakın.'
                              : 'Yer değiştirmek için iki oyuncuya sırayla '
                                    'dokunun (ya da basılı tutup diğerinin '
                                    'üzerine bırakın).',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _midText, fontSize: 11),
                        ),
                      ),
                    if (insights != null)
                      _SubsInRow(
                        insights: insights,
                        bench: rosterSnap.data!
                            .where((r) => !r.isStarting)
                            .toList(),
                        players: players,
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    ];
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return ListView(
      // Üst sekmelere yakın başlar; takım seçimi + gösterim seçimi bir arada.
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: children,
    );
  }
}

/// Dizilişin altında oyuna sonradan girenler: ↑ dakika, numara ve ad.
class _SubsInRow extends StatelessWidget {
  const _SubsInRow({
    required this.insights,
    required this.bench,
    required this.players,
  });

  final MatchInsights insights;
  final List<MatchRosterModel> bench;
  final Map<String, PlayerModel> players;

  @override
  Widget build(BuildContext context) {
    final came =
        [
          for (final r in bench)
            if (insights.of(r.playerId).subbedIn) r,
        ]..sort(
          (a, b) => (insights.of(a.playerId).subIn ?? 0).compareTo(
            insights.of(b.playerId).subIn ?? 0,
          ),
        );
    if (came.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OYUNA GİRENLER',
            style: TextStyle(
              color: _midText,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final r in came) _chip(r)],
          ),
        ],
      ),
    );
  }

  Widget _chip(MatchRosterModel r) {
    final m = insights.of(r.playerId);
    final p = players[r.playerId];
    final no = (r.jerseyNumber ?? p?.number ?? '').trim();
    final goals = m.goals.length + m.penGoals.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.arrow_upward_rounded,
            size: 14,
            color: Color(0xFF22C55E),
          ),
          if (m.subIn != null)
            Text(
              "${m.subIn}' ",
              style: const TextStyle(
                color: Color(0xFF86EFAC),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          Text(
            '${no.isEmpty ? '' : '$no '}${shortPlayerName(p?.name ?? '-')}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (goals > 0) ...[
            const SizedBox(width: 5),
            const Icon(Icons.sports_soccer, size: 13, color: Colors.white),
            if (goals > 1)
              Text(
                '×$goals',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
          ],
          if (m.assists.isNotEmpty) ...[
            const SizedBox(width: 5),
            Text(
              'A×${m.assists.length}',
              style: const TextStyle(
                color: Color(0xFF6EE7B7),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Otomatik kaydın durumu: küçük ikon (kaydediliyor / kaydedildi).
class _SaveStatus extends StatelessWidget {
  const _SaveStatus({
    required this.dirty,
    required this.saving,
    required this.failed,
    required this.onRetry,
  });

  final bool dirty;
  final bool saving;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (failed && !saving) {
      return IconButton(
        tooltip: 'Kaydedilemedi, yeniden dene',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        onPressed: onRetry,
        icon: const Icon(
          Icons.cloud_off_rounded,
          color: Colors.redAccent,
          size: 20,
        ),
      );
    }
    final busy = dirty || saving;
    return Tooltip(
      message: busy ? 'Kaydediliyor' : 'Kaydedildi',
      child: SizedBox(
        width: 22,
        height: 22,
        child: Center(
          child: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _midText,
                  ),
                )
              : const Icon(
                  Icons.cloud_done_outlined,
                  color: _midText,
                  size: 18,
                ),
        ),
      ),
    );
  }
}

class _FormationPicker extends StatelessWidget {
  const _FormationPicker({
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final List<String> options;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: _accent,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          if (enabled)
            const Icon(Icons.arrow_drop_down, color: _accent, size: 20)
          else
            const SizedBox(width: 4),
        ],
      ),
    );
    if (!enabled) return chip;
    return PopupMenuButton<String>(
      initialValue: value,
      color: const Color(0xFF1E293B),
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final f in options)
          PopupMenuItem(
            value: f,
            child: Text(
              f,
              style: TextStyle(
                color: f == value ? _accent : Colors.white,
                fontWeight: f == value ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
      ],
      child: chip,
    );
  }
}

class _TeamSwitch extends StatelessWidget {
  const _TeamSwitch({
    required this.homeName,
    required this.awayName,
    required this.homeColor,
    required this.awayColor,
    required this.selected,
    required this.onChanged,
  });

  final String homeName;
  final String awayName;
  final Color homeColor;
  final Color awayColor;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget item(int i, String label) {
      final on = selected == i;
      final color = i == 0 ? homeColor : awayColor;
      // Açık renkli formada yazı koyu olsun.
      final light = color.computeLuminance() > 0.6;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            // Kadrolar sekmesindeki takım başlıklarıyla aynı yükseklik.
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(
              color: on ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Seçili değilken takım rengi küçük noktada.
                if (!on) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                // Uzun ad "…" ile kesilmez; sığmazsa küçülür.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: on
                            ? (light ? const Color(0xFF0F172A) : Colors.white)
                            : Colors.white60,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(children: [item(0, homeName), item(1, awayName)]),
    );
  }
}

/// Dekupe + ad soyad, aynı dikeyde (yatayda iç içe) duran en yakın iki saha
/// oyuncusu arasına sığmalı: dekupe boyu buna göre küçülür, yer çok darsa
/// yazı da küçülür. [outfield]: kaleci hariç oyuncuların piksel konumu.
({double cutH, bool compact}) _fitTokens(List<Offset> outfield) {
  var gap = double.infinity;
  for (final a in outfield) {
    for (final b in outfield) {
      final dy = b.dy - a.dy;
      if (dy > 4 && (b.dx - a.dx).abs() < 56 && dy < gap) gap = dy;
    }
  }
  if (gap == double.infinity) return (cutH: 52, compact: false);
  const nameH = 30.0, compactH = 26.0;
  final compact = gap - nameH - 6 < 44;
  final cutH = (gap - (compact ? compactH : nameH) - 6).clamp(32.0, 52.0);
  return (cutH: cutH, compact: compact);
}

class _Pitch extends StatelessWidget {
  const _Pitch({
    required this.lines,
    required this.teamColor,
    this.style = PitchTokenStyle.circle,
    this.onSwap,
    this.picked,
    this.onPick,
    this.insights,
    this.cutouts = const {},
    this.onTapPlayer,
  });

  /// Profil görünümünde dekupe fotoğraflar (asıl adres → dekupe adresi).
  final Map<String, String> cutouts;

  /// Verilirse oyuncuya dokunmak bunu çağırır (canlıda olay, değilse oyuncu
  /// kartı); yer değiştirme o zaman yalnız basılı tutup sürükleyerek.
  final void Function(_PitchPlayer p)? onTapPlayer;

  /// lines[0]: kaleci, sonrakiler defanstan hücuma dizilişin hatları.
  final List<List<_PitchPlayer>> lines;
  final Color teamColor;
  final PitchTokenStyle style;

  /// Verilirse işaretlerin köşelerinde gol/asist/çıkış/kart ikonları.
  final MatchInsights? insights;

  /// null değilse oyuncular sürükle-bırakla yer değiştirebilir.
  final void Function(String fromId, String toId)? onSwap;

  /// Dokunarak yer değiştirme: seçili oyuncu ve dokunma. Sürükleme bazı
  /// cihazlarda (iOS tarayıcı, alt pencere) kaydırmayla çakışıyor.
  final String? picked;
  final void Function(String id)? onPick;

  @override
  Widget build(BuildContext context) {
    final n = lines.length - 1; // saha oyuncusu hat sayısı

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: LayoutBuilder(
        builder: (context, c) {
          const tokenW = 78.0;
          final children = <Widget>[
            Positioned.fill(child: CustomPaint(painter: _FullPitchPainter())),
          ];
          final fit = _fitTokens([
            for (var li = 1; li < lines.length; li++)
              for (var i = 0; i < lines[li].length; i++)
                () {
                  final o = pitchSlot(
                    li: li,
                    i: i,
                    n: lines[li].length,
                    outfieldLines: n,
                  );
                  return Offset(o.dx * c.maxWidth, o.dy * c.maxHeight);
                }(),
          ]);
          for (var li = 0; li < lines.length; li++) {
            final line = lines[li];
            for (var i = 0; i < line.length; i++) {
              final pos = pitchSlot(
                li: li,
                i: i,
                n: line.length,
                outfieldLines: n,
              );
              children.add(
                Positioned(
                  left: (pos.dx * c.maxWidth - tokenW / 2).clamp(
                    0.0,
                    c.maxWidth - tokenW,
                  ),
                  top: pos.dy * c.maxHeight - 26,
                  width: tokenW,
                  child: _slot(
                    line[i],
                    li == 0 ? const Color(0xFFF59E0B) : teamColor,
                    fit,
                  ),
                ),
              );
            }
          }
          return Stack(children: children);
        },
      ),
    );
  }

  Widget _slot(_PitchPlayer p, Color color, ({double cutH, bool compact}) fit) {
    final swap = onSwap;
    final selected = picked == p.id;
    final token = _PlayerToken(
      player: p,
      color: selected ? const Color(0xFFFACC15) : color,
      style: style,
      marks: insights?.of(p.id),
      cutoutUrl: style == PitchTokenStyle.photo
          ? cutouts[(p.photoUrl ?? '').trim()]
          : null,
      cutoutH: fit.cutH,
      compact: fit.compact,
    );
    final tap = onTapPlayer;
    if (swap == null) {
      if (tap == null) return token;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => tap(p),
        child: token,
      );
    }
    final pick = tap == null ? onPick : (String _) => tap(p);
    final body = DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != p.id,
      onAcceptWithDetails: (d) => swap(d.data, p.id),
      builder: (context, candidates, _) {
        return LongPressDraggable<String>(
          data: p.id,
          delay: const Duration(milliseconds: 200),
          feedback: Material(
            type: MaterialType.transparency,
            child: SizedBox(
              width: 78,
              child: Transform.scale(scale: 1.12, child: token),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: token),
          child: AnimatedScale(
            scale: candidates.isNotEmpty || selected ? 1.15 : 1,
            duration: const Duration(milliseconds: 120),
            child: token,
          ),
        );
      },
    );
    if (pick == null) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => pick(p.id),
      child: body,
    );
  }
}

class _PlayerToken extends StatelessWidget {
  const _PlayerToken({
    required this.player,
    required this.color,
    this.style = PitchTokenStyle.circle,
    this.marks,
    this.cutoutUrl,
    this.cutoutH = 52,
    this.compact = false,
  });

  final _PitchPlayer player;

  /// Dekupe boyu: hatlar sıkışınca küçülür (bkz. [_fitTokens]).
  final double cutoutH;

  /// Sıkışık yerleşim: ad soyad daha küçük yazılır.
  final bool compact;

  /// Varsa oyuncu daire yerine dekupe görünür: ayağının altında takım
  /// renginde zemin halkası, kenarda ince beyaz kontur.
  final String? cutoutUrl;
  final Color color;
  final PitchTokenStyle style;

  /// Maçtaki olayları (köşe ikonları); null ise ikon yok.
  final PlayerMarks? marks;

  /// Profil görünümünde fotoğrafı olmayan oyuncu forma ile görünür.
  bool get _hasPhoto => (player.photoUrl ?? '').trim().isNotEmpty;

  Widget _photo() {
    final url = (player.photoUrl ?? '').trim();
    final initials = player.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .take(2)
        .map((e) => e.characters.first)
        .join()
        .toUpperCase();
    final fallback = Container(
      alignment: Alignment.center,
      color: const Color(0xFFCBD5E1),
      child: Text(
        initials,
        style: const TextStyle(
          color: Color(0xFF334155),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: ClipOval(
        child: url.isEmpty
            ? fallback
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }

  Widget _cutout(String url) {
    Widget img({Color? tint}) => Image.network(
      url,
      width: 42 * cutoutH / 52,
      height: cutoutH,
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      color: tint,
      colorBlendMode: tint == null ? null : BlendMode.srcIn,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        Positioned(
          bottom: 0,
          child: Container(
            width: 38,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: const BorderRadius.all(Radius.elliptical(19, 5)),
              border: Border.all(color: color, width: 2),
            ),
          ),
        ),
        Positioned(
          bottom: 4,
          child: Stack(
            children: [
              // Gölge ve beyaz kontur aynı görselin bulanık kopyaları.
              Transform.translate(
                offset: const Offset(0, 2),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                  child: img(tint: Colors.black54),
                ),
              ),
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 0.9, sigmaY: 0.9),
                child: img(tint: Colors.white),
              ),
              img(),
            ],
          ),
        ),
      ],
    );
  }

  /// Köşe ikonu: koyu daire içinde ikon, gerekirse sayı rozeti.
  Widget _corner(Widget icon, {int count = 1}) => Stack(
    clipBehavior: Clip.none,
    children: [
      Container(
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          shape: BoxShape.circle,
        ),
        child: icon,
      ),
      if (count > 1)
        Positioned(
          right: -5,
          top: -5,
          child: Container(
            width: 12,
            height: 12,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
        ),
    ],
  );

  static const _shadow = [
    Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(0, 1)),
  ];

  static String _trUpper(String v) =>
      v.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

  TextStyle get _firstStyle => TextStyle(
    color: Colors.white,
    fontSize: compact ? 10 : 12,
    fontWeight: FontWeight.w800,
    height: 1.1,
    shadows: _shadow,
  );

  TextStyle get _lastStyle => TextStyle(
    color: Colors.white.withValues(alpha: 0.92),
    fontSize: compact ? 10.5 : 12.5,
    fontWeight: FontWeight.w400,
    height: 1.1,
    letterSpacing: 0.2,
    shadows: _shadow,
  );

  /// Ad kalın, soyad ince (büyük harf). Tek kelimelik ad kalın yazılır.
  (String, String) get _split {
    final parts = player.name.trim().split(RegExp(r'\s+'));
    final last = parts.length > 1 ? parts.removeLast() : '';
    return (parts.join(' '), last);
  }

  /// Ad soyad ortalı durur; fotoğraflı gösterimde forma numarası yazının
  /// solunda küçük yuvarlakta, ortalamayı kaydırmadan (yazı genişliği
  /// ölçülüp yanına konur).
  Widget _names(bool withNumber) {
    final (first, last) = _split;
    Widget line(String t, TextStyle st) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(t, maxLines: 1, style: st),
    );
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (first.isNotEmpty) line(first, _firstStyle),
        if (last.isNotEmpty) line(_trUpper(last), _lastStyle),
      ],
    );
    if (!withNumber || player.number.isEmpty) return column;
    double width(String t, TextStyle st) {
      if (t.isEmpty) return 0;
      final tp = TextPainter(
        text: TextSpan(text: t, style: st),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      return tp.width;
    }

    final textW = [
      width(first, _firstStyle),
      width(_trUpper(last), _lastStyle),
    ].reduce((a, b) => a > b ? a : b);
    final d = compact ? 14.0 : 16.0;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : textW + 2 * d;
        final left = ((w - textW) / 2 - d - 2).clamp(0.0, w);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: w,
              child: Center(child: column),
            ),
            Positioned(
              left: left,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  width: d,
                  height: d,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white70, width: 0.8),
                  ),
                  child: FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.all(1.5),
                      child: Text(
                        player.number,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 9,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _eventCorners() {
    final m = marks;
    if (m == null) return const [];
    final goals = m.goals.length + m.penGoals.length;
    final card = m.yellows.isNotEmpty || m.reds.isNotEmpty;
    // Asist: oyuncu kartındaki tepside top ikonu.
    final assist = _corner(
      Image.asset('assets/images/assist.png', width: 14, height: 14),
      count: m.assists.length,
    );
    final assistLeft = card && goals > 0 && m.assists.isNotEmpty;
    final right = <Widget>[
      if (card)
        SizedBox(
          width: 16,
          height: 16,
          child: Center(child: CardIcon(red: m.reds.isNotEmpty, size: 12)),
        ),
      if (goals > 0)
        _corner(
          const Icon(Icons.sports_soccer, size: 13, color: Colors.white),
          count: goals,
        ),
      if (m.assists.isNotEmpty && !assistLeft) assist,
    ];
    return [
      // Çıkış: işaretin solunda, dikeyde ortada (üstteki oyuncunun adıyla
      // karışmasın).
      if (m.subbedOut)
        Positioned(
          right: 44,
          top: 0,
          bottom: 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (m.subOut != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xE60F172A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "${m.subOut}'",
                    style: const TextStyle(
                      color: Color(0xFFFCA5A5),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              const Icon(
                Icons.arrow_downward_rounded,
                size: 14,
                color: Color(0xFFEF4444),
              ),
            ],
          ),
        ),
      // Sağ sütun alt alta: kart, gol, asist. Üçü birden varsa asist sola,
      // çıkış okunun altına geçer (sütun formadan taşmasın).
      if (right.isNotEmpty)
        Positioned(
          right: -12,
          top: 9,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < right.length; i++) ...[
                if (i > 0) const SizedBox(height: 2),
                right[i],
              ],
            ],
          ),
        ),
      if (assistLeft) Positioned(left: -10, bottom: 0, child: assist),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cutout = cutoutUrl;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 44,
          height: cutout != null ? cutoutH + 4 : 36,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (cutout != null)
                Positioned.fill(child: _cutout(cutout))
              else if (style == PitchTokenStyle.photo && _hasPhoto)
                _photo()
              else if (style != PitchTokenStyle.circle)
                JerseyShape(
                  width: 38,
                  color: color,
                  borderColor: Colors.white,
                  child: Text(
                    player.number.isEmpty ? '-' : player.number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                )
              else
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    player.number.isEmpty ? '-' : player.number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              if (player.isCaptain)
                const Positioned(
                  right: 0,
                  top: -2,
                  child: CaptainBadge(size: 15),
                ),
              ..._eventCorners(),
            ],
          ),
        ),
        const SizedBox(height: 2),
        // Numara dairede/formada yazmıyorsa (fotoğraf, dekupe) yazının
        // yanında.
        _names(cutout != null || (style == PitchTokenStyle.photo && _hasPhoto)),
      ],
    );
    // Dekupe daha uzun: ayak hizası dairenin altıyla aynı kalsın diye yukarı.
    return cutout == null
        ? column
        : Transform.translate(
            offset: Offset(0, -(cutoutH + 4 - 36)),
            child: column,
          );
  }
}

class _FullPitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Koyu yeşil çim şeritleri
    const dark = Color(0xFF0B3D20);
    const light = Color(0xFF0F4A28);
    const stripes = 10;
    final h = size.height / stripes;
    for (var i = 0; i < stripes; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * h, size.width, h),
        Paint()..color = i.isEven ? dark : light,
      );
    }

    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final r = Rect.fromLTWH(10, 10, size.width - 20, size.height - 20);
    canvas.drawRect(r, line);
    canvas.drawLine(
      Offset(r.left, r.center.dy),
      Offset(r.right, r.center.dy),
      line,
    );
    canvas.drawCircle(r.center, r.width * 0.14, line);
    canvas.drawCircle(
      r.center,
      2.5,
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );

    void box(bool top, double wFactor, double hFactor) {
      final w = r.width * wFactor;
      final hh = r.height * hFactor;
      canvas.drawRect(
        Rect.fromLTWH(r.center.dx - w / 2, top ? r.top : r.bottom - hh, w, hh),
        line,
      );
    }

    for (final top in [true, false]) {
      box(top, 0.56, 0.15); // ceza sahası
      box(top, 0.26, 0.06); // kale alanı
    }
  }

  @override
  bool shouldRepaint(covariant _FullPitchPainter oldDelegate) => false;
}

/// Kadro sekmesinin VS görünümü: tam saha, ev sahibi üstte (kalesi
/// yukarıda), deplasman altta. Salt görüntü; oyuncuya dokunma [onPlayerTap].
/// İki takımın da ilk 11'i yoksa hiçbir şey çizilmez.
class VsFormationPitch extends StatelessWidget {
  const VsFormationPitch({
    super.key,
    required this.match,
    this.homeColor,
    this.awayColor,
    this.onPlayerTap,
    this.collapsed = false,
    this.onToggleCollapsed,
  });

  final MatchModel match;
  final Color? homeColor;
  final Color? awayColor;

  /// Gizle/göster: kapalıyken yalnız başlık çubuğu.
  final bool collapsed;
  final VoidCallback? onToggleCollapsed;
  final void Function(
    String teamId,
    String playerId,
    String name,
    String number,
  )?
  onPlayerTap;

  Widget _team(String teamId, Widget Function(_Layout? layout) builder) {
    return StreamBuilder<List<PlayerModel>>(
      stream: ServiceLocator.teamService.watchPlayers(
        teamId: teamId,
        tournamentId: match.seasonId,
        matchId: match.id,
      ),
      builder: (context, playerSnap) => StreamBuilder<List<MatchRosterModel>>(
        stream: ServiceLocator.matchService.watchMatchRosters(match.id, teamId),
        builder: (context, rosterSnap) {
          final players = {
            for (final p in playerSnap.data ?? const <PlayerModel>[]) p.id: p,
          };
          final starters = (rosterSnap.data ?? const <MatchRosterModel>[])
              .where((r) => r.isStarting)
              .toList();
          final formation = teamId == match.homeTeamId
              ? match.homeFormation
              : match.awayFormation;
          return builder(
            _computeLayout(starters, players, formation: formation),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    PitchTokenStylePref.load();
    PhotoCutouts.ensureLoaded();
    return MatchInsightsBuilder(
      match: match,
      builder: (context, insights) => _team(
        match.homeTeamId,
        (home) => _team(match.awayTeamId, (away) {
          if (home == null && away == null) return const SizedBox.shrink();
          final fold = onToggleCollapsed;
          if (fold != null && collapsed) {
            return LineupFoldHeader(open: false, onTap: fold);
          }
          final pitch = AspectRatio(
            aspectRatio: 0.55,
            child: ValueListenableBuilder<PitchTokenStyle>(
              valueListenable: PitchTokenStylePref.notifier,
              builder: (context, style, _) =>
                  ValueListenableBuilder<Map<String, String>>(
                    valueListenable: PhotoCutouts.map,
                    builder: (context, cutouts, _) => _pitch(
                      context,
                      home,
                      away,
                      insights,
                      style == PitchTokenStyle.photo && insights == null
                          ? PitchTokenStyle.shirt
                          : style,
                      PhotoCutouts.visible(context) ? cutouts : const {},
                    ),
                  ),
            ),
          );
          if (fold == null) return pitch;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LineupFoldHeader(open: true, onTap: fold),
              const SizedBox(height: 6),
              pitch,
            ],
          );
        }),
      ),
    );
  }

  Widget _pitch(
    BuildContext context,
    _Layout? home,
    _Layout? away,
    MatchInsights? insights,
    PitchTokenStyle style,
    Map<String, String> cutouts,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: LayoutBuilder(
        builder: (context, c) {
          const tokenW = 78.0;
          // Yarım sahadaki konum (0-1) tam sahaya: ev sahibi ters çevrilip
          // üst yarıya, deplasman alt yarıya.
          Offset place(Offset o, bool top) => top
              ? Offset(1 - o.dx, 0.03 + (1 - o.dy) * 0.45)
              : Offset(o.dx, 0.52 + o.dy * 0.45);
          final children = <Widget>[
            Positioned.fill(child: CustomPaint(painter: _FullPitchPainter())),
          ];
          for (final (layout, top) in [(home, true), (away, false)]) {
            if (layout == null) continue;
            final lines = layout.lines;
            final n = lines.length - 1;
            Offset slot(int li, int i) => place(
              pitchSlot(li: li, i: i, n: lines[li].length, outfieldLines: n),
              top,
            );
            // Dekupe boyu her yarı için ayrı sığdırılır.
            final fit = _fitTokens([
              for (var li = 1; li < lines.length; li++)
                for (var i = 0; i < lines[li].length; i++)
                  () {
                    final o = slot(li, i);
                    return Offset(o.dx * c.maxWidth, o.dy * c.maxHeight);
                  }(),
            ]);
            final teamId = top ? match.homeTeamId : match.awayTeamId;
            final color = top
                ? (homeColor ?? _accent)
                : (awayColor ?? const Color(0xFF3B82F6));
            for (var li = 0; li < lines.length; li++) {
              for (var i = 0; i < lines[li].length; i++) {
                final p = lines[li][i];
                final pos = slot(li, i);
                final token = _PlayerToken(
                  player: p,
                  color: li == 0 ? const Color(0xFFF59E0B) : color,
                  style: style,
                  marks: insights?.of(p.id),
                  cutoutUrl: style == PitchTokenStyle.photo
                      ? cutouts[(p.photoUrl ?? '').trim()]
                      : null,
                  cutoutH: fit.cutH,
                  compact: fit.compact,
                );
                final tap = onPlayerTap;
                children.add(
                  Positioned(
                    left: (pos.dx * c.maxWidth - tokenW / 2).clamp(
                      0.0,
                      c.maxWidth - tokenW,
                    ),
                    top: pos.dy * c.maxHeight - 26,
                    width: tokenW,
                    child: tap == null
                        ? token
                        : GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => tap(teamId, p.id, p.name, p.number),
                            child: token,
                          ),
                  ),
                );
              }
            }
          }
          return Stack(children: children);
        },
      ),
    );
  }
}

/// Kadro sekmesindeki dizilişin başlık çubuğu: solda "Diziliş", sağ üstte
/// kalın aşağı/yukarı ok ile gizle/göster.
class LineupFoldHeader extends StatelessWidget {
  const LineupFoldHeader({super.key, required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 0, 2),
        child: Row(
          children: [
            const Icon(Icons.grid_view_rounded, color: _midText, size: 16),
            const SizedBox(width: 6),
            const Text(
              'Diziliş',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Tooltip(
              message: open ? 'Dizilişi gizle' : 'Dizilişi göster',
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: CustomPaint(painter: _ChevronPainter(up: open)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kalın ok (ikon fontundaki ok ince kalıyordu).
class _ChevronPainter extends CustomPainter {
  _ChevronPainter({required this.up});

  final bool up;

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final dy = up ? 3.0 : -3.0;
    final path = Path()
      ..moveTo(c.dx - 7, c.dy + dy)
      ..lineTo(c.dx, c.dy - dy)
      ..lineTo(c.dx + 7, c.dy + dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter old) => old.up != up;
}
