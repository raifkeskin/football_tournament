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
  const CardIcon({super.key, required this.red, this.size = 13});

  final bool red;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size * 0.7,
    height: size,
    decoration: BoxDecoration(
      color: red ? _red : _yellow,
      borderRadius: BorderRadius.circular(2),
    ),
  );
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
  });

  final String id;
  final String name;
  final String number;
  final String teamId;
  final String teamName;
}

const _groupColors = {
  'KALECİ': Color(0xFF3B82F6),
  'DEFANS': Color(0xFF10B981),
  'ORTA SAHA': Color(0xFFA855F7),
  'FORVET': Color(0xFFF97316),
  'HERKES': Color(0xFF64748B),
};

/// "Olay ekle": olayı, sonra futbolcuyu seç; dakika ve kaydet. Altta maçın
/// girilmiş olayları (silinebilir).
Future<void> showMomentSheet({
  required BuildContext context,
  required MatchModel match,
  required MatchInsights insights,
  required List<MomentPlayer> players,
  int? minute,
  String? teamId,
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
  });

  final MatchModel match;
  final MatchInsights insights;
  final List<MomentPlayer> players;
  final int? minute;

  /// Verilirse futbolcu listesi yalnız bu takımdan (alttaki takım butonu).
  final String? teamId;

  @override
  State<_MomentSheet> createState() => _MomentSheetState();
}

class _MomentSheetState extends State<_MomentSheet> {
  MomentKind? _kind;
  MomentPlayer? _player;
  late final _minute = TextEditingController(
    text: widget.minute?.toString() ?? '',
  );
  bool _saving = false;
  late List<MatchMoment> _list = [...widget.insights.moments];

  @override
  void dispose() {
    _minute.dispose();
    super.dispose();
  }

  String _pts(MomentKind k) {
    final v = widget.insights.rules.v('m_${k.key}');
    return '${v > 0
        ? '+'
        : v < 0
        ? '−'
        : ''}${v.abs().toStringAsFixed(1)}';
  }

  Future<void> _save() async {
    final k = _kind, p = _player;
    if (k == null || p == null) return;
    setState(() => _saving = true);
    try {
      await MatchMomentsRepo.add(
        matchId: widget.match.id,
        teamId: p.teamId,
        playerId: p.id,
        kind: k.key,
        minute: int.tryParse(_minute.text.trim()),
      );
      final fresh = await MatchMomentsRepo.load(widget.match.id);
      if (!mounted) return;
      setState(() {
        _list = fresh;
        _kind = null;
        _player = null;
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
        onTap: () => setState(() => _kind = k),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
                teamName == null ? 'Olay ekle' : 'Olay ekle · $teamName',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Olayı seç, sonra futbolcuyu seç. Kartlar, goller ve '
                'değişiklikler zaten ayrı giriliyor; burada yalnız puana etki '
                'eden anlar var.',
                style: TextStyle(color: _muted, fontSize: 12.5, height: 1.35),
              ),
              for (final g in MomentKind.groups) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 3,
                      height: 14,
                      decoration: BoxDecoration(
                        color: _groupColors[g],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      g,
                      style: TextStyle(
                        color: _groupColors[g],
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 3.4,
                  children: [
                    for (final k in MomentKind.all.where((k) => k.group == g))
                      _kindTile(k, _groupColors[g]!),
                  ],
                ),
              ],
              if (_kind != null) ...[
                const SizedBox(height: 16),
                Text(
                  '${_kind!.label.toUpperCase()} · FUTBOLCU SEÇ',
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 8),
                for (final p in pickable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color: _player == p
                          ? kAdminAccent.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.04),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: _player == p
                              ? kAdminAccent
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _player = p),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 9,
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
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                p.teamName,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: TextField(
                        controller: _minute,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Dakika',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: kAdminAccent,
                          minimumSize: const Size.fromHeight(44),
                        ),
                        onPressed: _player == null || _saving ? null : _save,
                        child: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
                      ),
                    ),
                  ],
                ),
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
