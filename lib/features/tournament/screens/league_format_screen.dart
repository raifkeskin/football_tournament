import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../models/league_format.dart';

/// Sezonun lig formatını açar (admin ve kurucu başkan). Takım sayısı
/// gruptaki en kalabalık takım sayısından okunur.
Future<void> openLeagueFormatScreen(
  BuildContext context,
  String seasonId,
) async {
  final sb = Supabase.instance.client;
  LeagueFormat? format;
  var teamCount = 0;
  try {
    final results = await Future.wait<dynamic>([
      sb
          .from('seasons')
          .select('league_format, teams_per_group')
          .eq('id', seasonId)
          .single(),
      sb.from('season_teams').select('group_id').eq('season_id', seasonId),
    ]);
    final row = results[0] as Map;
    format = LeagueFormat.fromJson(row['league_format']);
    final perGroup = <String, int>{};
    for (final r in results[1] as List) {
      final g = (r['group_id'] ?? '').toString();
      perGroup[g] = (perGroup[g] ?? 0) + 1;
    }
    teamCount = perGroup.values.fold(0, (a, b) => a > b ? a : b);
    if (teamCount < 2) {
      final tpg = row['teams_per_group'];
      teamCount = tpg is num && tpg >= 2 ? tpg.toInt() : 8;
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lig formatı okunamadı: $e')));
    }
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LeagueFormatScreen(
        seasonId: seasonId,
        teamCount: teamCount,
        initial: format,
      ),
    ),
  );
}

class LeagueFormatScreen extends StatefulWidget {
  const LeagueFormatScreen({
    super.key,
    required this.seasonId,
    required this.teamCount,
    this.initial,
  });

  final String seasonId;
  final int teamCount;
  final LeagueFormat? initial;

  @override
  State<LeagueFormatScreen> createState() => _LeagueFormatScreenState();
}

class _LeagueFormatScreenState extends State<LeagueFormatScreen> {
  late LeagueFormat _f =
      widget.initial ?? LeagueFormat.fromTemplate('top4', widget.teamCount);
  bool _saving = false;

  int get _n => widget.teamCount;

  void _set(LeagueFormat f) => setState(() => _f = f);

  void _setCup(int i, FormatCup c) {
    final cups = [..._f.cups]..[i] = c;
    _set(_f.copyWith(cups: cups, clearTemplate: true));
  }

  Future<void> _pickRank(int i, {required bool start}) async {
    final c = _f.cups[i];
    final v = await showAdminOptionPicker<int>(
      context: context,
      title: start ? 'İlk sıra' : 'Son sıra',
      items: [for (var r = 1; r <= _n; r++) r],
      selected: start ? c.from : c.to,
      labelBuilder: (r) => '$r. sıra',
    );
    if (v == null) return;
    _setCup(i, start ? c.copyWith(from: v) : c.copyWith(to: v));
  }

  Future<void> _rename(int i) async {
    final name = await showAdminTextInputDialog(
      context: context,
      title: 'Kupa Adı',
      icon: Icons.emoji_events_outlined,
      label: 'AD',
      fieldIcon: Icons.short_text_rounded,
      initialValue: _f.cups[i].name,
      validator: (v) => v.trim().isEmpty ? 'Ad boş olamaz.' : null,
    );
    if (name == null) return;
    _setCup(i, _f.cups[i].copyWith(name: name.trim()));
  }

  void _addCup() {
    final free = _f.restRanks(_n);
    final from = free.isNotEmpty ? free.first : (_n - 1).clamp(1, _n);
    final to = free.length >= 2
        ? free[free.length >= 4 ? 3 : free.length - 1]
        : _n;
    _set(
      _f.copyWith(
        cups: [
          ..._f.cups,
          FormatCup(name: 'Yeni Kupa', from: from, to: to < from ? from : to),
        ],
        clearTemplate: true,
      ),
    );
  }

  Future<void> _save({bool reset = false}) async {
    if (!reset && !_f.isValid(_n)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kırmızı kartlardaki hataları düzeltin.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('seasons')
          .update({'league_format': reset ? null : _f.toJson()})
          .eq('id', widget.seasonId);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reset ? 'Lig formatı kaldırıldı.' : 'Lig formatı kaydedildi.',
          ),
        ),
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

  String _info(FormatCup c) {
    final pairs = <String>[];
    for (final (a, b) in c.firstRound()) {
      if (a != null && b != null) pairs.add('$a–$b');
    }
    final lines = [
      '${c.size} takım · ${c.roundNames.join(' → ')}',
      'İlk tur: ${pairs.join(', ')}',
      if (c.byes > 0)
        '${[for (var k = 0; k < c.byes; k++) '${c.from + k}.'].join(' ve ')} '
            'bay geçer',
    ];
    return lines.join('\n');
  }

  Widget _rankChip(String label, VoidCallback onTap) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 12),
    ),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
  );

  Widget _cupCard(int i) {
    final c = _f.cups[i];
    final errs = _f.errorsOf(i, _n);
    final color = LeagueFormat.colors[i % LeagueFormat.colors.length];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: errs.isNotEmpty
              ? kAdminDanger
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => _rename(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            c.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.edit_rounded,
                          size: 15,
                          color: kAdminMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Kupayı sil',
                onPressed: () => _set(
                  _f.copyWith(
                    cups: [..._f.cups]..removeAt(i),
                    clearTemplate: true,
                  ),
                ),
                icon: const Icon(Icons.close_rounded, color: kAdminMuted),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'SIRALAR',
                style: TextStyle(
                  color: kAdminMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              _rankChip('${c.from}.', () => _pickRank(i, start: true)),
              const Text('→', style: TextStyle(color: kAdminMuted)),
              _rankChip('${c.to}.', () => _pickRank(i, start: false)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Colors.white70,
                  selectedForegroundColor: Colors.white,
                  selectedBackgroundColor: const Color(0xFF334155),
                ),
                segments: const [
                  ButtonSegment(value: 1, label: Text('Tek maç')),
                  ButtonSegment(value: 2, label: Text('Rövanşlı')),
                ],
                selected: {c.legs},
                onSelectionChanged: (s) =>
                    _setCup(i, c.copyWith(legs: s.first)),
              ),
              if (c.size >= 4)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: c.third,
                      activeThumbColor: kAdminAccent,
                      onChanged: (v) => _setCup(i, c.copyWith(third: v)),
                    ),
                    const Text(
                      '3.lük maçı',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            errs.isNotEmpty ? errs.join('\n') : _info(c),
            style: TextStyle(
              color: errs.isNotEmpty ? kAdminDanger : kAdminMuted,
              fontSize: 12.5,
              height: 1.45,
              fontWeight: errs.isNotEmpty ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rest = _f.restRanks(_n);
    final restLabel = rest.isEmpty
        ? ''
        : rest.length == 1
        ? '${rest.first}. sıra'
        : '${rest.first}–${rest.last}. sıralar';
    return AdminPageScaffold(
      title: 'Lig Formatı',
      bottomBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: AdminPrimaryButton(
          label: 'KAYDET',
          busy: _saving,
          onPressed: () => _save(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Ligde $_n takım (gruptaki en kalabalık sayı). Puan tablosunun '
            'bölgeleri ve play-off eşleşmeleri bu ayardan gelir.',
            style: const TextStyle(color: kAdminMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          AdminFormSection(
            title: 'Şablon',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (id, label) in LeagueFormat.templates)
                  ChoiceChip(
                    label: Text(label),
                    selected: _f.template == id,
                    showCheckmark: false,
                    selectedColor: kAdminAccent.withValues(alpha: 0.25),
                    side: BorderSide(
                      color: _f.template == id
                          ? kAdminAccent
                          : Colors.white.withValues(alpha: 0.12),
                    ),
                    labelStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                    backgroundColor: const Color(0xFF1E293B),
                    onSelected: (_) => _set(
                      LeagueFormat.fromTemplate(
                        id,
                        _n,
                      ).copyWith(showIfNow: _f.showIfNow),
                    ),
                  ),
              ],
            ),
          ),
          AdminFormSection(
            title: 'Kupalar',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_f.cups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Play-off yok; lig normal sezon sonunda biter.',
                      style: TextStyle(color: kAdminMuted, fontSize: 13),
                    ),
                  ),
                for (var i = 0; i < _f.cups.length; i++) _cupCard(i),
                OutlinedButton.icon(
                  onPressed: _f.cups.length >= LeagueFormat.colors.length
                      ? null
                      : _addCup,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kAdminAccent,
                    side: BorderSide(
                      color: kAdminAccent.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'Kupa ekle',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          AdminFormSection(
            title: rest.isEmpty
                ? 'Kalan sıralar'
                : 'Kalan sıralar · $restLabel',
            child: AdminFieldGroup(
              children: [
                if (rest.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'Her sıra bir kupada; kalan takım yok.',
                      style: TextStyle(color: kAdminMuted, fontSize: 13),
                    ),
                  )
                else
                  SwitchListTile(
                    value: _f.restOut,
                    activeThumbColor: kAdminDanger,
                    onChanged: (v) => _set(_f.copyWith(restOut: v)),
                    title: const Text(
                      'Lige veda (kırmızı)',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'Kapalıysa bu sıralar işaretsiz kalır.',
                      style: TextStyle(color: kAdminMuted, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          AdminFormSection(
            title: 'Puan durumu',
            child: AdminFieldGroup(
              children: [
                SwitchListTile(
                  value: _f.showIfNow,
                  activeThumbColor: kAdminAccent,
                  onChanged: (v) => _set(_f.copyWith(showIfNow: v)),
                  title: const Text(
                    '"Bugün bitse" kartı',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text(
                    'Play-off eşleşmeleri puan tablosunun altında; sezonun '
                    'yarısı oynandıktan sonra görünür.',
                    style: TextStyle(color: kAdminMuted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          if (widget.initial != null)
            TextButton(
              onPressed: _saving ? null : () => _save(reset: true),
              style: TextButton.styleFrom(foregroundColor: kAdminDanger),
              child: const Text('Formatı kaldır (eski görünüm)'),
            ),
        ],
      ),
    );
  }
}
