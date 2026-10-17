import 'package:flutter/material.dart';

import '../../tournament/models/league_format.dart';

/// Maçın eleme ayarı: beraberlik kuralı (null → lig maçı), kupa ve tur.
class KnockoutValue {
  const KnockoutValue({this.tiebreak, this.cupName, this.cupRound});

  final String? tiebreak;
  final String? cupName;
  final String? cupRound;

  bool sameAs(KnockoutValue o) =>
      tiebreak == o.tiebreak && cupName == o.cupName && cupRound == o.cupRound;
}

/// Maçı Düzenle penceresinde "Eleme maçı" bölümü: açılınca beraberlik
/// kuralı, kupa (lig formatındaki kupalar) ve tur seçilir. Kupa seçilince
/// kural o kupanınkine ayarlanır.
class KnockoutFields extends StatelessWidget {
  const KnockoutFields({
    super.key,
    required this.value,
    required this.cups,
    required this.onChanged,
  });

  final KnockoutValue value;
  final List<FormatCup> cups;
  final ValueChanged<KnockoutValue> onChanged;

  static const _accent = Color(0xFF10B981);
  static const rounds = [
    'Son 16',
    'Çeyrek Final',
    'Yarı Final',
    '3.lük Maçı',
    'Final',
  ];

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    ),
  );

  Widget _chip(String label, bool on, VoidCallback onTap) => ChoiceChip(
    label: Text(label),
    selected: on,
    showCheckmark: false,
    onSelected: (_) => onTap(),
    labelStyle: TextStyle(
      color: on ? Colors.white : Colors.white70,
      fontWeight: on ? FontWeight.w800 : FontWeight.w600,
      fontSize: 12.5,
    ),
    backgroundColor: Colors.black.withValues(alpha: 0.3),
    selectedColor: _accent.withValues(alpha: 0.25),
    side: BorderSide(
      color: on ? _accent : Colors.white.withValues(alpha: 0.15),
    ),
    visualDensity: VisualDensity.compact,
  );

  @override
  Widget build(BuildContext context) {
    final on = value.tiebreak != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events_outlined,
                color: Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Eleme maçı',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                value: on,
                activeThumbColor: _accent,
                onChanged: (v) => onChanged(
                  v
                      ? KnockoutValue(
                          tiebreak: cups.isEmpty
                              ? 'et_pens'
                              : cups.first.tiebreak,
                          cupName: cups.isEmpty ? null : cups.first.name,
                        )
                      : const KnockoutValue(),
                ),
              ),
            ],
          ),
          if (!on)
            const Text(
              'Açılırsa maç berabere bitemez ve puan tablosuna sayılmaz.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          if (on) ...[
            _label('BERABERLİKTE'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip(
                  'Uzatma + penaltı',
                  value.tiebreak == 'et_pens',
                  () => onChanged(
                    KnockoutValue(
                      tiebreak: 'et_pens',
                      cupName: value.cupName,
                      cupRound: value.cupRound,
                    ),
                  ),
                ),
                _chip(
                  'Doğrudan penaltı',
                  value.tiebreak == 'pens',
                  () => onChanged(
                    KnockoutValue(
                      tiebreak: 'pens',
                      cupName: value.cupName,
                      cupRound: value.cupRound,
                    ),
                  ),
                ),
              ],
            ),
            if (cups.isNotEmpty) ...[
              _label('KUPA'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in cups)
                    _chip(
                      c.name,
                      value.cupName == c.name,
                      () => onChanged(
                        KnockoutValue(
                          tiebreak: c.tiebreak,
                          cupName: c.name,
                          cupRound: value.cupRound,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            _label('TUR'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in rounds)
                  _chip(
                    r,
                    value.cupRound == r,
                    () => onChanged(
                      KnockoutValue(
                        tiebreak: value.tiebreak,
                        cupName: value.cupName,
                        cupRound: value.cupRound == r ? null : r,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
