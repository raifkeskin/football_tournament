import 'package:flutter/material.dart';

import '../../../core/utils/team_name.dart';
import '../models/match.dart';
import 'penalty_badge.dart';

/// Atış sayısı: ilk 5'er atış, sonra ani ölüm.
const _regularKicks = 5;

/// Penaltı atışları sonuçlandı mı: ilk 5'er atışta rakibin kalan atışlarıyla
/// yetişemeyeceği fark; sonrasında eşit sayıda atışta farklı skor.
bool shootoutDecided(List<ShootoutKick> kicks) {
  var h = 0, a = 0, hg = 0, ag = 0;
  for (final k in kicks) {
    if (k.home) {
      h++;
      if (k.scored) hg++;
    } else {
      a++;
      if (k.scored) ag++;
    }
  }
  if (h <= _regularKicks && a <= _regularKicks) {
    return hg > ag + (_regularKicks - a) || ag > hg + (_regularKicks - h);
  }
  return h == a && hg != ag;
}

/// Sıradaki atışı kullanacak taraf (true: ev sahibi); ilk atış yoksa null.
bool? _nextKicker(List<ShootoutKick> kicks) {
  if (kicks.isEmpty) return null;
  final h = kicks.where((k) => k.home).length;
  final a = kicks.length - h;
  if (h == a) return kicks.first.home;
  return h < a;
}

/// Penaltı atışları: her takım için atış noktaları (gol yeşil ✓, kaçan
/// kırmızı ✕). Yetkiliye her takımın satırında "Gol / Kaçtı" düğmeleri ve
/// son atışı geri alma çıkar.
class ShootoutBoard extends StatefulWidget {
  const ShootoutBoard({
    super.key,
    required this.match,
    required this.homeName,
    required this.awayName,
    required this.canEdit,
    required this.onKick,
  });

  final MatchModel match;
  final String homeName;
  final String awayName;
  final bool canEdit;

  /// [home] null → son atışı geri al.
  final Future<void> Function(bool? home, bool scored) onKick;

  @override
  State<ShootoutBoard> createState() => _ShootoutBoardState();
}

class _ShootoutBoardState extends State<ShootoutBoard> {
  static const _gold = PenaltyBadge.color;
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFF87171);

  bool _busy = false;

  Future<void> _run(bool? home, bool scored) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onKick(home, scored);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kicks = widget.match.shootout ?? const <ShootoutKick>[];
    final decided = shootoutDecided(kicks);
    final next = decided ? null : _nextKicker(kicks);
    final editing = widget.canEdit && !decided;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_soccer_rounded, color: _gold, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'PENALTI ATIŞLARI',
                  style: TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (widget.canEdit && kicks.isNotEmpty)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _busy ? null : () => _run(null, false),
                  icon: const Icon(Icons.undo_rounded, size: 16),
                  label: const Text(
                    'Son atışı geri al',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _row(kicks, home: true, next: next, editing: editing),
          const SizedBox(height: 8),
          _row(kicks, home: false, next: next, editing: editing),
          if (editing && kicks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'İlk atışı kullanan takımın satırından başlayın.',
                style: TextStyle(color: Colors.white54, fontSize: 11.5),
              ),
            ),
          if (decided && widget.canEdit)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Kazanan belli oldu. Maçı bitirebilirsiniz.',
                style: TextStyle(
                  color: _green,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(
    List<ShootoutKick> all, {
    required bool home,
    required bool? next,
    required bool editing,
  }) {
    final kicks = all.where((k) => k.home == home).toList();
    final goals = kicks.where((k) => k.scored).length;
    final slots = kicks.length < _regularKicks ? _regularKicks : kicks.length;
    final isNext = next == home;

    Widget dot(ShootoutKick? k) {
      final color = k == null ? Colors.white24 : (k.scored ? _green : _red);
      return Container(
        width: 18,
        height: 18,
        margin: const EdgeInsets.only(right: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: k != null && k.scored ? _green : Colors.transparent,
          border: Border.all(color: color, width: 2),
        ),
        child: k == null
            ? null
            : Icon(
                k.scored ? Icons.check_rounded : Icons.close_rounded,
                size: 12,
                color: k.scored ? const Color(0xFF04120C) : _red,
              ),
      );
    }

    Widget kickButton(String label, bool scored) => SizedBox(
      height: 30,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: scored ? _green : _red,
          side: BorderSide(
            color: (scored ? _green : _red).withValues(alpha: 0.6),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        onPressed: _busy ? null : () => _run(home, scored),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                compactTeamName(home ? widget.homeName : widget.awayName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: isNext ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            PenaltyBadge(goals, size: 12),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: kicks.length > _regularKicks,
                child: Row(
                  children: [
                    for (var i = 0; i < slots; i++)
                      dot(i < kicks.length ? kicks[i] : null),
                  ],
                ),
              ),
            ),
            if (editing) ...[
              const SizedBox(width: 6),
              kickButton('Gol', true),
              const SizedBox(width: 6),
              kickButton('Kaçtı', false),
            ],
          ],
        ),
      ],
    );
  }
}
