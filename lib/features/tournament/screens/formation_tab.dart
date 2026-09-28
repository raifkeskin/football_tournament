import 'package:flutter/material.dart';
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

/// Kaptan pazubandı: sarı zemin üzerinde "C".
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
        color: const Color(0xFFFACC15),
        borderRadius: BorderRadius.circular(size * 0.25),
        border: Border.all(color: Colors.black26, width: 0.8),
      ),
      child: Text(
        'C',
        style: TextStyle(
          color: Colors.black,
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

/// Maç detayı "Diziliş" sekmesi: esamedeki ilk 11 sahaya yerleşir.
/// Diziliş seçilmemişse oyuncuların mevkilerinden otomatik hesaplanır;
/// yetkili kullanıcı dizilişi değiştirebilir (matches.home/away_formation).
class FormationTab extends StatefulWidget {
  const FormationTab({
    super.key,
    required this.match,
    required this.homeName,
    required this.awayName,
    required this.canEdit,
  });

  factory FormationTab.fromMatch({
    Key? key,
    required MatchModel match,
    required bool isTeamManager,
    required String homeName,
    required String awayName,
  }) {
    return FormationTab(
      key: key,
      match: match,
      homeName: homeName,
      awayName: awayName,
      canEdit: isTeamManager,
    );
  }

  final MatchModel match;
  final String homeName;
  final String awayName;
  final bool canEdit;

  @override
  State<FormationTab> createState() => _FormationTabState();
}

class _FormationTabState extends State<FormationTab> {
  int _selected = 0; // 0: ev sahibi, 1: deplasman

  /// Kullanıcının bu oturumda seçtiği dizilişler (teamIndex -> "4-4-2").
  final Map<int, String> _chosen = {};

  /// Sürükle-bırak sonrası saha sırası (teamIndex -> slot sırasıyla oyuncu id).
  final Map<int, List<String>> _order = {};

  /// Saha sırasını match_rosters.pos_x'e yazar (null: sırayı sıfırla).
  Future<void> _persistOrder(List<String>? ids) async {
    final sb = Supabase.instance.client;
    try {
      if (ids == null) {
        await sb
            .from('match_rosters')
            .update({'pos_x': null})
            .eq('match_id', widget.match.id)
            .eq('team_id', _teamId);
        return;
      }
      for (var i = 0; i < ids.length; i++) {
        await sb
            .from('match_rosters')
            .update({'pos_x': i})
            .eq('match_id', widget.match.id)
            .eq('team_id', _teamId)
            .eq('player_id', ids[i]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Yerleşim kaydedilemedi: $e')));
    }
  }

  void _swap(List<String> current, String fromId, String toId) {
    if (fromId == toId) return;
    final next = [...current];
    final a = next.indexOf(fromId);
    final b = next.indexOf(toId);
    if (a < 0 || b < 0) return;
    next[a] = toId;
    next[b] = fromId;
    setState(() => _order[_selected] = next);
    _persistOrder(next);
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

  static List<int> _parse(String f) => f
      .split('-')
      .map((e) => int.tryParse(e.trim()) ?? 0)
      .where((e) => e > 0)
      .toList();

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

  /// Hattı kenar oyuncular iki uca, merkezdekiler ortaya gelecek şekilde dizer.
  static List<_PitchPlayer> _arrange(List<_PitchPlayer> line) {
    final sorted = [...line]
      ..sort((a, b) => _jersey(a.number).compareTo(_jersey(b.number)));
    final wide = sorted.where((e) => e.wide).toList();
    final center = sorted.where((e) => !e.wide).toList();
    final half = (wide.length / 2).ceil();
    return [...wide.take(half), ...center, ...wide.skip(half)];
  }

  Future<void> _changeFormation(String value) async {
    setState(() {
      _chosen[_selected] = value;
      _order.remove(_selected); // yeni dizilişte otomatik yerleşim
    });
    _persistOrder(null);
    try {
      await ServiceLocator.matchService.updateMatchFormationState(
        matchId: widget.match.id,
        homeFormation: _selected == 0 ? value : null,
        awayFormation: _selected == 1 ? value : null,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Diziliş bu ekranda uygulandı ancak kaydedilemedi '
            '(matches tablosunda home_formation/away_formation kolonu yok).',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamColor = _selected == 0 ? _accent : const Color(0xFF3B82F6);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _TeamSwitch(
          homeName: widget.homeName,
          awayName: widget.awayName,
          selected: _selected,
          onChanged: (v) => setState(() => _selected = v),
        ),
        const SizedBox(height: 14),
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
                final starters = starterRosters.map((r) {
                  final p = players[r.playerId];
                  return _PitchPlayer(
                    id: r.playerId,
                    name: (p?.name ?? '').trim().isEmpty ? '-' : p!.name,
                    number: (r.jerseyNumber ?? p?.number ?? '').trim(),
                    line: positionLineOf(p?.mainPosition, p?.position),
                    wide: _isWide(p?.mainPosition, p?.position),
                    isCaptain: r.isCaptain,
                  );
                }).toList();
                if (starters.isEmpty) {
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

                // Mevkiye göre doğal hatlar (kaleci birden fazlaysa fazlası
                // defansa).
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
                    ..sort(
                      (a, b) => _jersey(a.number).compareTo(_jersey(b.number)),
                    );
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
                final options = _optionsFor(outfieldCount, autoFormation);

                var formation =
                    _chosen[_selected] ?? _savedFormation ?? autoFormation;
                var counts = _parse(formation);
                if (counts.fold<int>(0, (a, b) => a + b) != outfieldCount) {
                  formation = autoFormation; // kadro değiştiyse geçersiz
                  counts = _parse(formation);
                }

                // Saha oyuncularını defanstan hücuma sırayla dizilişin
                // hatlarına dağıt; her hat kendi içinde kenar/merkez dizilir.
                final outfield = [
                  for (var li = 1; li < 4; li++) ..._arrange(natural[li]),
                ];
                final baseLines = <List<_PitchPlayer>>[natural[0]];
                var idx = 0;
                for (final c in counts) {
                  baseLines.add(_arrange(outfield.sublist(idx, idx + c)));
                  idx += c;
                }

                // Elle yapılmış yerleşim: önce bu oturumdaki, yoksa
                // kaydedilmiş (pos_x) sıra; oyuncu kümesi aynı değilse yok sayılır.
                final baseIds = [
                  for (final l in baseLines) ...l.map((e) => e.id),
                ];
                bool sameSet(List<String> ids) =>
                    ids.length == baseIds.length &&
                    ids.toSet().containsAll(baseIds);
                List<String> currentIds = baseIds;
                final local = _order[_selected];
                final slotted =
                    starterRosters.every((r) => r.slot != null) &&
                        starterRosters.map((r) => r.slot).toSet().length ==
                            starterRosters.length
                    ? ([...starterRosters]
                            ..sort((a, b) => a.slot!.compareTo(b.slot!)))
                          .map((r) => r.playerId)
                          .toList()
                    : null;
                if (local != null && sameSet(local)) {
                  currentIds = local;
                } else if (slotted != null && sameSet(slotted)) {
                  currentIds = slotted;
                }
                final byId = {for (final p in starters) p.id: p};
                final pitchLines = <List<_PitchPlayer>>[];
                var k = 0;
                for (final l in baseLines) {
                  pitchLines.add([
                    for (var i = 0; i < l.length; i++) byId[currentIds[k++]]!,
                  ]);
                }

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
                          enabled: widget.canEdit && options.length > 1,
                          onChanged: _changeFormation,
                        ),
                        const Spacer(),
                        Text(
                          '${starters.length} oyuncu',
                          style: const TextStyle(color: _midText, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AspectRatio(
                      aspectRatio: 0.72,
                      child: _Pitch(
                        lines: pitchLines,
                        teamColor: teamColor,
                        onSwap: widget.canEdit
                            ? (from, to) => _swap(currentIds, from, to)
                            : null,
                      ),
                    ),
                    if (widget.canEdit)
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
            padding: const EdgeInsets.symmetric(vertical: 11),
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
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(children: [item(0, homeName), item(1, awayName)]),
    );
  }
}

class _Pitch extends StatelessWidget {
  const _Pitch({required this.lines, required this.teamColor, this.onSwap});

  /// lines[0]: kaleci, sonrakiler defanstan hücuma dizilişin hatları.
  final List<List<_PitchPlayer>> lines;
  final Color teamColor;

  /// null değilse oyuncular sürükle-bırakla yer değiştirebilir.
  final void Function(String fromId, String toId)? onSwap;

  @override
  Widget build(BuildContext context) {
    final n = lines.length - 1; // saha oyuncusu hat sayısı
    double yOf(int li) {
      if (li == 0) return 0.90;
      // Hatlar defanstan (0.70) hücuma (0.18) eşit aralıklı.
      if (n <= 1) return 0.44;
      return 0.70 - (li - 1) * (0.52 / (n - 1));
    }

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
              final x = (i + 1) / (line.length + 1);
              children.add(
                Positioned(
                  left: (x * c.maxWidth - tokenW / 2).clamp(
                    0.0,
                    c.maxWidth - tokenW,
                  ),
                  top: yOf(li) * c.maxHeight - 26,
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
    final token = _PlayerToken(player: p, color: color);
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
  const _PlayerToken({required this.player, required this.color});

  final _PitchPlayer player;
  final Color color;

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
