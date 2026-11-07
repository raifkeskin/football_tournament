import 'package:flutter/material.dart';

import '../../../core/widgets/admin_page.dart';
import '../models/match.dart';
import 'match_insights.dart';

const _muted = Color(0xFF94A3B8);
const _green = Color(0xFF22C55E);
const _red = Color(0xFFEF4444);
const _yellow = Color(0xFFFACC15);

String _mins(List<int?> list) {
  final known = [
    for (final m in list)
      if (m != null) "$m'",
  ];
  if (known.isEmpty) return list.length > 1 ? '×${list.length}' : '';
  return known.join(' ');
}

/// Penaltı golü: top ve köşesinde kırmızı P.
class PenaltyBallIcon extends StatelessWidget {
  const PenaltyBallIcon({super.key, this.size = 14});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 3,
      height: size + 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.sports_soccer, size: size, color: Colors.white),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.62,
              height: size * 0.62,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: _red,
                shape: BoxShape.circle,
              ),
              child: Text(
                'P',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kart ikonu.
class CardIcon extends StatelessWidget {
  const CardIcon({
    super.key,
    required this.red,
    this.secondYellow = false,
    this.size = 13,
  });

  final bool red;

  /// Çift sarıdan ihraç: sarı kartın üstüne kayık kırmızı.
  final bool secondYellow;
  final double size;

  Widget _card(Color c) => Container(
    width: size * 0.7,
    height: size,
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
  );

  @override
  Widget build(BuildContext context) {
    if (!secondYellow) return _card(red ? _red : _yellow);
    return SizedBox(
      width: size * 1.05,
      height: size * 1.1,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Transform.rotate(angle: -0.2, child: _card(_yellow)),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Transform.rotate(angle: 0.15, child: _card(_red)),
          ),
        ],
      ),
    );
  }
}

/// Kadro satırında oyuncunun olayları: gol, penaltı golü, kendi kalesine,
/// giren/çıkan ve kartlar dakikalarıyla. Asist gösterilmez.
class PlayerEventLine extends StatelessWidget {
  const PlayerEventLine({super.key, required this.marks});

  final PlayerMarks marks;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    void add(Widget icon, String text) {
      if (items.isNotEmpty) items.add(const SizedBox(width: 9));
      items
        ..add(icon)
        ..add(const SizedBox(width: 3))
        ..add(
          Text(
            text,
            style: const TextStyle(
              color: _muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
    }

    final m = marks;
    if (m.goals.isNotEmpty) {
      add(
        const Icon(Icons.sports_soccer, size: 13, color: Colors.white),
        _mins(m.goals),
      );
    }
    if (m.penGoals.isNotEmpty) {
      add(const PenaltyBallIcon(size: 13), _mins(m.penGoals));
    }
    if (m.ownGoals.isNotEmpty) {
      add(
        const Icon(Icons.sports_soccer, size: 13, color: _red),
        '${_mins(m.ownGoals)} (KK)',
      );
    }
    if (m.subbedIn) {
      add(
        const Icon(Icons.arrow_upward_rounded, size: 14, color: _green),
        m.subIn == null ? '' : "${m.subIn}'",
      );
    }
    if (m.subbedOut) {
      add(
        const Icon(Icons.arrow_downward_rounded, size: 14, color: _red),
        m.subOut == null ? '' : "${m.subOut}'",
      );
    }
    if (m.secondYellow) {
      add(const CardIcon(red: false), _mins(m.yellows));
      add(const CardIcon(red: true), _mins(m.reds));
    } else {
      if (m.yellows.isNotEmpty) {
        add(const CardIcon(red: false), _mins(m.yellows));
      }
      if (m.reds.isNotEmpty) add(const CardIcon(red: true), _mins(m.reds));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(mainAxisSize: MainAxisSize.min, children: items),
    );
  }
}

/// Puan rozeti; renk puana göre, maçın en iyisinde yıldız.
class RatingBadge extends StatelessWidget {
  const RatingBadge({super.key, required this.value, this.best = false});

  final double value;
  final bool best;

  static Color colorOf(double v) {
    if (v >= 8.5) return const Color(0xFF0EA5E9);
    if (v >= 7.5) return const Color(0xFF16A34A);
    if (v >= 7.0) return const Color(0xFF22C55E);
    if (v >= 6.0) return const Color(0xFFEAB308);
    return const Color(0xFFF97316);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 38),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colorOf(value),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (best) ...[
            const Icon(Icons.star_rounded, size: 12, color: Colors.white),
            const SizedBox(width: 2),
          ],
          Text(
            value.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Olay ekle

/// Kadrodan seçilebilecek oyuncu.
@immutable
class MomentPlayer {
  const MomentPlayer({
    required this.id,
    required this.name,
    required this.number,
    required this.teamId,
    required this.teamName,
    this.line = -1,
    this.onPitch = true,
    this.keeper = false,
  });

  final String id;
  final String name;
  final String number;
  final String teamId;
  final String teamName;

  /// Mevki hattı: 0 kaleci, 1 defans, 2 orta saha, 3 forvet, -1 bilinmiyor.
  final int line;

  /// O an sahada mı (kırmızı kart / çıkan oyuncu değil).
  final bool onPitch;

  /// Sahadaki kaleci (kaleci olayları doğrudan ona yazılır).
  final bool keeper;
}

/// Sekmenin mevki hattı (HERKES: -1).
int _groupLine(String g) => switch (g) {
  'KALECİ' => 0,
  'DEFANS' => 1,
  'ORTA SAHA' => 2,
  'FORVET' => 3,
  _ => -1,
};

const _groupColors = {
  'KALECİ': Color(0xFF3B82F6),
  'DEFANS': Color(0xFF10B981),
  'ORTA SAHA': Color(0xFFA855F7),
  'FORVET': Color(0xFFF97316),
  'HERKES': Color(0xFF64748B),
  'TÜMÜ': Color(0xFF0EA5E9),
};

/// Sekmeler: tüm olaylar + mevki grupları.
const _tabs = ['TÜMÜ', ...MomentKind.groups];

/// "Olay ekle": mevki sekmesinden olayı seç; kaleci olayı sahadaki kaleciye
/// hemen yazılır, diğerlerinde o mevkideki oyunculardan birine dokununca
/// kaydedilir. Dakika maç saatinden gelir. Altta girilen olaylar.
Future<void> showMomentSheet({
  required BuildContext context,
  required MatchModel match,
  required MatchInsights insights,
  required List<MomentPlayer> players,
  int? minute,
  String? teamId,
  String? playerId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E293B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _MomentSheet(
      match: match,
      insights: insights,
      players: players,
      minute: minute,
      teamId: teamId,
      playerId: playerId,
    ),
  );
}

class _MomentSheet extends StatefulWidget {
  const _MomentSheet({
    required this.match,
    required this.insights,
    required this.players,
    this.minute,
    this.teamId,
    this.playerId,
  });

  final MatchModel match;
  final MatchInsights insights;
  final List<MomentPlayer> players;
  final int? minute;

  /// Sahada dokunulan futbolcu: onun mevki sekmesi açılır, olaya dokununca
  /// doğrudan ona kaydedilir.
  final String? playerId;

  /// Verilirse futbolcu listesi yalnız bu takımdan (alttaki takım butonu).
  final String? teamId;

  @override
  State<_MomentSheet> createState() => _MomentSheetState();
}

class _MomentSheetState extends State<_MomentSheet> {
  MomentKind? _kind;
  late final MomentPlayer? _preset = widget.players
      .where((p) => p.id == widget.playerId)
      .firstOrNull;
  late String _tab = () {
    final p = _preset;
    if (p == null || p.line < 0 || p.line > 3) return _tabs.first;
    return MomentKind.groups[p.line];
  }();

  /// İkinci adımda mevkiye uymayanlar da listelensin mi.
  bool _showAll = false;
  bool _saving = false;
  late List<MatchMoment> _list = [...widget.insights.moments];

  List<MomentPlayer> get _teamPlayers {
    final team = widget.teamId;
    return team == null
        ? widget.players
        : widget.players.where((p) => p.teamId == team).toList();
  }

  /// Olay seçilince: kaleci olayında sahada tek kaleci varsa hemen kaydet;
  /// yoksa futbolcu listesi (ikinci adım).
  void _pickKind(MomentKind k) {
    if (_saving) return;
    final preset = _preset;
    if (preset != null) {
      _save(k, preset);
      return;
    }
    if (k.group == 'KALECİ') {
      final gks = _teamPlayers.where((p) => p.keeper && p.onPitch).toList();
      if (gks.length == 1) {
        _save(k, gks.first);
        return;
      }
    }
    setState(() {
      _kind = k;
      _showAll = false;
    });
  }

  String _pts(MomentKind k) {
    final v = widget.insights.rules.v('m_${k.key}');
    return '${v > 0
        ? '+'
        : v < 0
        ? '−'
        : ''}${v.abs().toStringAsFixed(1)}';
  }

  Future<void> _save(MomentKind k, MomentPlayer p) async {
    setState(() => _saving = true);
    try {
      await MatchMomentsRepo.add(
        matchId: widget.match.id,
        teamId: p.teamId,
        playerId: p.id,
        kind: k.key,
        minute: widget.minute,
      );
      final fresh = await MatchMomentsRepo.load(widget.match.id);
      if (!mounted) return;
      setState(() {
        _list = fresh;
        _kind = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${k.label} · ${p.name} kaydedildi.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(MatchMoment m) async {
    try {
      await MatchMomentsRepo.remove(m.id);
      final fresh = await MatchMomentsRepo.load(widget.match.id);
      if (mounted) setState(() => _list = fresh);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Silinemedi: $e')));
      }
    }
  }

  /// Genişliğe göre sütunlu, alçak kutular (yatay ekranda kaydırmadan
  /// hepsi görünsün).
  Widget _compactGrid(
    BuildContext context,
    List<Widget> children, {
    required double height,
  }) => LayoutBuilder(
    builder: (context, c) => GridView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: (c.maxWidth / 230).floor().clamp(2, 6),
        mainAxisExtent: height,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      children: children,
    ),
  );

  Widget _kindTile(MomentKind k, Color color) {
    final sel = _kind == k;
    final v = widget.insights.rules.v('m_${k.key}');
    return Material(
      color: color.withValues(alpha: sel ? 0.22 : 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: sel ? color : Colors.white.withValues(alpha: 0.1),
          width: sel ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _pickKind(k),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  k.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                _pts(k),
                style: TextStyle(
                  color: v >= 0
                      ? const Color(0xFF86EFAC)
                      : const Color(0xFFFCA5A5),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final names = {for (final p in widget.players) p.id: p.name};
    final team = widget.teamId;
    final pickable = team == null
        ? widget.players
        : widget.players.where((p) => p.teamId == team).toList();
    final teamName = pickable.isEmpty || team == null
        ? null
        : pickable.first.teamName;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          builder: (context, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _preset != null
                    ? 'Olay ekle · ${_preset.name}'
                    : teamName == null
                    ? 'Olay ekle'
                    : 'Olay ekle · $teamName',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _preset != null
                    ? 'Olaya dokununca bu futbolcuya kaydedilir.'
                    : 'Olayı seç, sonra futbolcuyu seç. Kartlar, goller ve '
                          'değişiklikler ayrı giriliyor; burada yalnız puana '
                          'etki eden anlar var.',
                style: TextStyle(color: _muted, fontSize: 12.5, height: 1.35),
              ),
              const SizedBox(height: 12),
              // Mevki sekmeleri; olaylar sekmenin altında.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final g in _tabs)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(g),
                          selected: _tab == g,
                          showCheckmark: false,
                          selectedColor: _groupColors[g]!.withValues(
                            alpha: 0.3,
                          ),
                          side: BorderSide(
                            color: _tab == g
                                ? _groupColors[g]!
                                : Colors.white.withValues(alpha: 0.12),
                          ),
                          labelStyle: TextStyle(
                            color: _tab == g ? Colors.white : _muted,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                          onSelected: (_) => setState(() {
                            _tab = g;
                            _kind = null;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (_kind == null)
                _compactGrid(context, height: 46, [
                  for (final k in MomentKind.all.where(
                    (k) => _tab == 'TÜMÜ' || k.group == _tab,
                  ))
                    _kindTile(k, _groupColors[k.group]!),
                ])
              else ...[
                // İkinci adım: seçilen olay üstte, o mevkideki oyuncular.
                Row(
                  children: [
                    IconButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _kind = null),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: 'Olaylara dön',
                    ),
                    Expanded(
                      child: Text(
                        '${_kind!.label} · ${_pts(_kind!)}',
                        style: TextStyle(
                          color: _groupColors[_kind!.group],
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const Text(
                  'Futbolcuya dokununca kaydedilir.',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                ...() {
                  final line = _groupLine(_kind!.group);
                  final onPitch = _teamPlayers.where((p) => p.onPitch);
                  final fit = line < 0
                      ? onPitch.toList()
                      : onPitch.where((p) => p.line == line).toList();
                  final list = _showAll || fit.isEmpty ? _teamPlayers : fit;
                  return [
                    _compactGrid(context, height: 44, [
                      for (final p in list)
                        Material(
                          color: Colors.white.withValues(alpha: 0.04),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: _saving ? null : () => _save(_kind!, p),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: Text(
                                      p.number,
                                      style: const TextStyle(
                                        color: kAdminAccent,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      p.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: p.onPitch
                                            ? Colors.white
                                            : Colors.white38,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ]),
                    if (!_showAll &&
                        fit.isNotEmpty &&
                        fit.length < _teamPlayers.length)
                      TextButton(
                        onPressed: () => setState(() => _showAll = true),
                        child: const Text('Tüm futbolcuları göster'),
                      ),
                  ];
                }(),
              ],
              if (_list.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text(
                  'GİRİLEN OLAYLAR',
                  style: TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 6),
                for (final m in _list)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${m.minute == null ? '' : "${m.minute}' · "}'
                      '${MomentKind.of(m.kind)?.label ?? m.kind}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      names[m.playerId] ?? '',
                      style: const TextStyle(color: _muted),
                    ),
                    trailing: IconButton(
                      tooltip: 'Sil',
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFFF87171),
                      ),
                      onPressed: () => _delete(m),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
