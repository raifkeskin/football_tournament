import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/app_session.dart';
import '../../referees/referee_service.dart';
import '../../referees/referee_widgets.dart';

/// Hakem hesabının ana sayfasında en üstte: sıradaki yöneteceği maç (büyük
/// kart) ve sonraki maçları. Hakem olmayanda hiçbir şey çizilmez.
class RefereeHomeCard extends StatefulWidget {
  const RefereeHomeCard({super.key});

  static final refresh = ValueNotifier<int>(0);

  @override
  State<RefereeHomeCard> createState() => _RefereeHomeCardState();
}

class _RefereeHomeCardState extends State<RefereeHomeCard> {
  static final Map<String, List<RefereeMatch>> _cache = {};

  String? _refereeId;
  List<RefereeMatch>? _matches;

  @override
  void initState() {
    super.initState();
    RefereeHomeCard.refresh.addListener(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppSession.of(context).value;
    final id = RefereeService.enabledFor(isAdmin: s.isAdmin)
        ? s.refereeId
        : null;
    if (id != _refereeId) {
      _refereeId = id;
      _matches = id == null ? null : _cache[id];
      _load();
    }
  }

  @override
  void dispose() {
    RefereeHomeCard.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final id = _refereeId;
    if (id == null) return;
    try {
      final list = await RefereeService.matches(id);
      _cache[id] = list;
      if (mounted && id == _refereeId) setState(() => _matches = list);
    } catch (_) {
      // Kart gösterilemezse ana sayfa etkilenmez.
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _matches;
    if (_refereeId == null || all == null) return const SizedBox.shrink();
    final cutoff = DateTime.now().subtract(const Duration(hours: 2));
    final upcoming = [
      for (final m in all)
        if (m.isUpcoming && (m.start == null || m.start!.isAfter(cutoff))) m,
    ];
    if (upcoming.isEmpty) return const SizedBox.shrink();
    final next = upcoming.first;
    final rest = upcoming.skip(1).take(3).toList();
    final d = next.start;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => openRefereeMatch(context, next.id),
              child: Ink(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E3A2F), kRefCard],
                  ),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'SIRADAKİ MAÇIN',
                            style: TextStyle(
                              color: Color(0xFF34D399),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.9,
                            ),
                          ),
                        ),
                        RefereeRoleChip(center: next.isCenter),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            next.home,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            children: [
                              Text(
                                next.timeLabel ?? '--:--',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                d == null
                                    ? 'Tarih belirsiz'
                                    : DateFormat(
                                        'EEEE, d MMMM',
                                        'tr_TR',
                                      ).format(d),
                                style: const TextStyle(
                                  color: Color(0xFFCBD5E1),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Text(
                            next.away,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _Tile(value: refereeCountdown(d), label: 'kaldı'),
                        const SizedBox(width: 8),
                        _Tile(
                          value: next.week == null
                              ? '–'
                              : '${next.week}. Hafta',
                          label: next.leagueName,
                        ),
                      ],
                    ),
                    if (next.pitch != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: Color(0xFF34D399),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              next.pitch!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Text(
                            'Maç detayı ›',
                            style: TextStyle(
                              color: Color(0xFF34D399),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (rest.isNotEmpty) ...[
            const RefereeSectionTitle('SONRAKİ MAÇLARIN'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: kRefCard,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < rest.length; i++)
                    RefereeMatchRow(
                      match: rest[i],
                      divider: i < rest.length - 1,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: kRefMuted, fontSize: 10.5),
          ),
        ],
      ),
    ),
  );
}
