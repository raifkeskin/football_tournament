import 'package:flutter/material.dart';
import 'package:football_tournament/features/tournament/utils/pitch_layout.dart';
import 'package:football_tournament/core/widgets/pitch_token_style.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../match/models/match.dart';
import '../../../core/services/service_locator.dart';

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
          fontWeight: FontWeight.w900,
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
  });

  final String id;
  final String name;
  final String number;
  final int line;
  final bool wide;
  final bool isCaptain;
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
  final autoFormation = natural
      .skip(1)
      .map((l) => l.length)
      .where((c) => c > 0)
      .join('-');
  final outfieldCount = starters.length - 1;

  var f = (formation ?? '').trim().isEmpty ? autoFormation : formation!.trim();
  var counts = _parseFormation(f);
  if (counts.fold<int>(0, (a, b) => a + b) != outfieldCount) {
    f = autoFormation; // kadro değiştiyse kayıtlı diziliş geçersiz
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
    this.initialTeam = 0,
    this.onShare,
  });

  /// Diziliş afişini paylaşır (takım kimliğiyle); düzenleme yetkisi olana
  /// görünür.
  final ValueChanged<String>? onShare;

  final MatchModel match;
  final String homeName;
  final String awayName;

  /// Takım başına düzenleme yetkisi: sorumlu yalnızca kendi takımını,
  /// yöneticiler ikisini de düzenler.
  final bool canEditHome;
  final bool canEditAway;

  /// Açılışta seçili takım (0: ev sahibi, 1: deplasman); sorumlu kendi
  /// takımıyla açar.
  final int initialTeam;

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

  /// Kullanıcının bu oturumda seçtiği dizilişler (teamIndex -> "4-4-2").
  final Map<int, String> _chosen = {};

  /// Sürükle-bırak sonrası saha sırası (teamIndex -> slot sırasıyla oyuncu id).
  final Map<int, List<String>> _order = {};

  /// Kaydedilmemiş değişikliği olan takımlar (teamIndex).
  final Set<int> _dirty = {};
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
  }

  /// Dizilişi (matches) ve saha sırasını (match_rosters.pos_x) kaydeder.
  /// Güncelleme hiçbir satırı etkilemezse (ör. yetki) hata verilir.
  Future<void> _saveLayout(String formation, List<String> ids) async {
    final sb = Supabase.instance.client;
    final team = _selected;
    setState(() => _saving = true);
    try {
      // Yetki kontrolü sunucuda: sorumlu yalnızca kendi takımını yazar.
      await sb.rpc(
        'set_match_formation',
        params: {
          'p_match_id': widget.match.id,
          'p_team_id': _teamId,
          'p_formation': formation,
        },
      );
      for (var i = 0; i < ids.length; i++) {
        final r = await sb
            .from('match_rosters')
            .update({'pos_x': i})
            .eq('match_id', widget.match.id)
            .eq('team_id', _teamId)
            .eq('player_id', ids[i])
            .select('id');
        if (r.isEmpty) {
          throw Exception('Oyuncu yerleşimi kaydedilemedi (yetki yok).');
        }
      }
      if (!mounted) return;
      setState(() {
        _chosen[team] = formation;
        _order[team] = ids;
        _dirty.remove(team);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Diziliş kaydedildi.')));
    } catch (e) {
      if (!mounted) return;
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

  static const _classic10 = [
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

  /// Saha oyuncusu sayısına uygun diziliş seçenekleri.
  static List<String> _optionsFor(int outfield, String auto) {
    final out = <String>[];
    if (outfield == 10) {
      out.addAll(_classic10);
    } else if (outfield >= 3) {
      for (var d = 1; d <= outfield - 2; d++) {
        for (var m = 1; m <= outfield - d - 1; m++) {
          out.add('$d-$m-${outfield - d - m}');
        }
      }
    }
    if (auto.isNotEmpty && !out.contains(auto)) out.insert(0, auto);
    return out;
  }

  void _changeFormation(String value) {
    setState(() {
      _chosen[_selected] = value;
      _order.remove(_selected); // yeni dizilişte otomatik yerleşim
      _dirty.add(_selected);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final teamColor = _selected == 0 ? _accent : const Color(0xFF3B82F6);
    return ListView(
      // Üst sekmelere yakın başlar; takım seçimi + gösterim seçimi bir arada.
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _TeamSwitch(
          homeName: widget.homeName,
          awayName: widget.awayName,
          selected: _selected,
          onChanged: (v) => setState(() => _selected = v),
        ),
        const SizedBox(height: 10),
        StreamBuilder<List<PlayerModel>>(
          key: ValueKey('players_$_teamId'),
          stream: ServiceLocator.teamService.watchPlayers(
            teamId: _teamId,
            tournamentId: widget.match.seasonId,
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

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
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
                        _FormationPicker(
                          value: formation,
                          options: options,
                          enabled: _canEdit && options.length > 1,
                          onChanged: _changeFormation,
                        ),
                        const Spacer(),
                        // Gösterim tercihi diziliş afişine de uygulanır.
                        // Kaydet butonu da varsa yer açmak için yalnız ikon.
                        PitchTokenStyleToggle(compact: _canEdit),
                        if (_canEdit && widget.onShare != null)
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
                            onPressed: () {
                              if (dirty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Önce dizilişi kaydedin, sonra paylaşın.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              widget.onShare!(_teamId);
                            },
                          ),
                        if (_canEdit) ...[
                          const SizedBox(width: 8),
                          _SaveLayoutButton(
                            dirty: dirty,
                            saving: _saving,
                            onPressed: () => _saveLayout(formation, currentIds),
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
                        builder: (context, style, _) => _Pitch(
                          lines: pitchLines,
                          teamColor: teamColor,
                          style: style,
                          onSwap: _canEdit
                              ? (from, to) => _swap(currentIds, from, to)
                              : null,
                        ),
                      ),
                    ),
                    if (_canEdit)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Yer değiştirmek için oyuncuya basılı tutup başka '
                          'bir oyuncunun üzerine bırakın.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _midText, fontSize: 11),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

/// "Kaydet" butonu: kaydedilmemiş değişiklik varsa yeşil ve etkin,
/// yoksa soluk "Kaydedildi" durumu.
class _SaveLayoutButton extends StatelessWidget {
  const _SaveLayoutButton({
    required this.dirty,
    required this.saving,
    required this.onPressed,
  });

  final bool dirty;
  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (!dirty && !saving) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, color: _midText, size: 16),
          SizedBox(width: 4),
          Text('Kaydedildi', style: TextStyle(color: _midText, fontSize: 12)),
        ],
      );
    }
    return ElevatedButton.icon(
      onPressed: saving ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _accent.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: const Size(0, 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: saving
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.save_rounded, size: 18),
      label: const Text(
        'Kaydet',
        style: TextStyle(fontWeight: FontWeight.w800),
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
              fontWeight: FontWeight.w900,
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
                fontWeight: f == value ? FontWeight.w900 : FontWeight.w600,
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
    required this.selected,
    required this.onChanged,
  });

  final String homeName;
  final String awayName;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget item(int i, String label) {
      final on = selected == i;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            // Kadrolar sekmesindeki takım başlıklarıyla aynı yükseklik.
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: on ? _accent : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: on ? Colors.white : Colors.white60,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
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

class _Pitch extends StatelessWidget {
  const _Pitch({
    required this.lines,
    required this.teamColor,
    this.style = PitchTokenStyle.circle,
    this.onSwap,
  });

  /// lines[0]: kaleci, sonrakiler defanstan hücuma dizilişin hatları.
  final List<List<_PitchPlayer>> lines;
  final Color teamColor;
  final PitchTokenStyle style;

  /// null değilse oyuncular sürükle-bırakla yer değiştirebilir.
  final void Function(String fromId, String toId)? onSwap;

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

  Widget _slot(_PitchPlayer p, Color color) {
    final token = _PlayerToken(player: p, color: color, style: style);
    final swap = onSwap;
    if (swap == null) return token;
    return DragTarget<String>(
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
            scale: candidates.isNotEmpty ? 1.15 : 1,
            duration: const Duration(milliseconds: 120),
            child: token,
          ),
        );
      },
    );
  }
}

class _PlayerToken extends StatelessWidget {
  const _PlayerToken({
    required this.player,
    required this.color,
    this.style = PitchTokenStyle.circle,
  });

  final _PitchPlayer player;
  final Color color;
  final PitchTokenStyle style;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 44,
          height: 36,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (style == PitchTokenStyle.shirt)
                JerseyShape(
                  width: 38,
                  color: color,
                  borderColor: Colors.white,
                  child: Text(
                    player.number.isEmpty ? '-' : player.number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
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
                      fontWeight: FontWeight.w900,
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
            ],
          ),
        ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            shortPlayerName(player.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
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
