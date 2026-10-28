import 'package:flutter/material.dart';

import 'referee_service.dart';
import 'referee_widgets.dart';

/// Hakem profili: görev sayıları, orta hakemken girilen kart / penaltı /
/// gol sayıları, turnuvalara göre tablo, sıradaki ve geçmiş maçlar.
class RefereeProfileView extends StatefulWidget {
  const RefereeProfileView({
    super.key,
    required this.refereeId,
    this.name,
    this.onSignOut,
  });

  final String refereeId;
  final String? name;
  final VoidCallback? onSignOut;

  @override
  State<RefereeProfileView> createState() => _RefereeProfileViewState();
}

class _RefereeProfileViewState extends State<RefereeProfileView> {
  static final Map<String, (List<RefereeLeagueStats>, List<RefereeMatch>)>
  _cache = {};

  List<RefereeLeagueStats>? _stats;
  List<RefereeMatch>? _matches;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = _cache[widget.refereeId];
    if (c != null) {
      _stats = c.$1;
      _matches = c.$2;
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        RefereeService.stats(widget.refereeId),
        RefereeService.matches(widget.refereeId),
        RefereeService.byIds([widget.refereeId]),
      ]);
      final stats = results[0] as List<RefereeLeagueStats>;
      final matches = results[1] as List<RefereeMatch>;
      _cache[widget.refereeId] = (stats, matches);
      if (mounted) {
        setState(() {
          _stats = stats;
          _matches = matches;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = RefereeService.message(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final matches = _matches;
    if (stats == null || matches == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Text(_error!, style: const TextStyle(color: kRefMuted)),
      );
    }
    final name =
        RefereeService.cached(widget.refereeId)?.name ?? widget.name ?? '';
    int sum(int Function(RefereeLeagueStats) f) =>
        stats.fold(0, (a, s) => a + f(s));
    final center = sum((s) => s.center);
    final yellow = sum((s) => s.yellow);
    final red = sum((s) => s.red);
    final upcoming = [
      for (final m in matches)
        if (m.isUpcoming) m,
    ];
    final past = [
      for (final m in matches.reversed)
        if (m.status == 'finished') m,
    ].take(10).toList();
    final leagues = {for (final m in matches) m.leagueName}.length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF3A2F0B), kRefCard],
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: kRefYellow,
                  child: CircleAvatar(
                    radius: 29,
                    backgroundColor: const Color(0xFF334155),
                    child: Text(
                      RefereeService.cached(widget.refereeId)?.initials ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.sports_rounded,
                            size: 15,
                            color: kRefYellow,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            leagues == 0 ? 'Hakem' : 'Hakem · $leagues turnuva',
                            style: const TextStyle(
                              color: kRefYellow,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _CountTile(value: center, label: 'Orta hakem'),
              const SizedBox(width: 8),
              _CountTile(value: sum((s) => s.assistant), label: 'Yardımcı'),
              const SizedBox(width: 8),
              _CountTile(value: upcoming.length, label: 'Sıradaki'),
            ],
          ),
          const RefereeSectionTitle('ORTA HAKEMLİKTE GÖSTERDİKLERİN'),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: kRefCard,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                _MarkStat(
                  mark: const _Card(color: kRefYellow),
                  value: yellow,
                  label: 'Sarı',
                ),
                _MarkStat(
                  mark: const _Card(color: Color(0xFFEF4444)),
                  value: red,
                  label: 'Kırmızı',
                ),
                _MarkStat(
                  mark: const _Letter('P'),
                  value: sum((s) => s.penalty),
                  label: 'Penaltı',
                ),
                _MarkStat(
                  mark: const _Letter('G', green: true),
                  value: sum((s) => s.goals),
                  label: 'Gol',
                ),
              ],
            ),
          ),
          if (center > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                'Maç başına ${(yellow / center).toStringAsFixed(1)} sarı · '
                '${(red / center).toStringAsFixed(1)} kırmızı',
                style: const TextStyle(color: kRefMuted, fontSize: 12),
              ),
            ),
          if (stats.isNotEmpty) ...[
            const RefereeSectionTitle('TURNUVALARA GÖRE'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: kRefCard,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const _StatsRow(
                    cells: ['TURNUVA', 'MAÇ', 'SK', 'KK', 'PEN'],
                    header: true,
                  ),
                  for (final s in stats)
                    _StatsRow(
                      cells: [
                        s.leagueName,
                        '${s.center + s.assistant}',
                        '${s.yellow}',
                        '${s.red}',
                        '${s.penalty}',
                      ],
                    ),
                ],
              ),
            ),
          ],
          if (upcoming.isNotEmpty) ...[
            const RefereeSectionTitle('SIRADAKİ MAÇLARIN'),
            _MatchList(matches: upcoming),
          ],
          if (past.isNotEmpty) ...[
            const RefereeSectionTitle('YÖNETTİĞİN MAÇLAR'),
            _MatchList(matches: past),
          ],
          if (upcoming.isEmpty && past.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Henüz atandığın maç yok.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kRefMuted),
              ),
            ),
          if (widget.onSignOut != null) ...[
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout_rounded, color: Color(0xFFF87171)),
              label: const Text(
                'Çıkış Yap',
                style: TextStyle(color: Color(0xFFF87171)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MatchList extends StatelessWidget {
  const _MatchList({required this.matches});

  final List<RefereeMatch> matches;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: kRefCard,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        for (var i = 0; i < matches.length; i++)
          RefereeMatchRow(match: matches[i], divider: i < matches.length - 1),
      ],
    ),
  );
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: kRefCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(label, style: const TextStyle(color: kRefMuted, fontSize: 11)),
        ],
      ),
    ),
  );
}

class _MarkStat extends StatelessWidget {
  const _MarkStat({
    required this.mark,
    required this.value,
    required this.label,
  });

  final Widget mark;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        SizedBox(height: 24, child: Center(child: mark)),
        const SizedBox(height: 6),
        Text(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(label, style: const TextStyle(color: kRefMuted, fontSize: 10.5)),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 17,
    height: 23,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(3),
    ),
  );
}

class _Letter extends StatelessWidget {
  const _Letter(this.letter, {this.green = false});

  final String letter;
  final bool green;

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: green ? const Color(0x3310B981) : null,
      border: green
          ? null
          : Border.all(color: const Color(0xFFE2E8F0), width: 2),
    ),
    child: Text(
      letter,
      style: TextStyle(
        color: green ? const Color(0xFF34D399) : Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.cells, this.header = false});

  final List<String> cells;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final style = header
        ? const TextStyle(
            color: kRefMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          )
        : const TextStyle(color: Colors.white, fontSize: 13);
    return Container(
      padding: EdgeInsets.symmetric(vertical: header ? 9 : 11),
      decoration: header
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              cells.first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: header
                  ? style
                  : style.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (final c in cells.skip(1))
            SizedBox(
              width: 38,
              child: Text(c, textAlign: TextAlign.center, style: style),
            ),
        ],
      ),
    );
  }
}
