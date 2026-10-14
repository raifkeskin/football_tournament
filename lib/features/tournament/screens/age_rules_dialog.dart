import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../models/age_rules.dart';

const _amber = Color(0xFFFBBF24);

/// Sezonun yaş ve kontenjan kurallarını düzenler; kaydedince
/// `seasons.age_rules` güncellenir. Yalnız admin ve kurucu başkan.
Future<void> showAgeRulesDialog(BuildContext context, String seasonId) async {
  final sb = Supabase.instance.client;
  AgeRules rules;
  try {
    final row = await sb
        .from('seasons')
        .select('age_rules')
        .eq('id', seasonId)
        .single();
    rules = AgeRules.fromJson(row['age_rules']);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kurallar okunamadı: $e')));
    }
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _AgeRulesDialog(seasonId: seasonId, initial: rules),
  );
}

/// Yıl seçenekleri: 20–75 yaş aralığı.
List<int> _years() {
  final now = DateTime.now().year;
  return [for (var y = now - 20; y >= now - 75; y--) y];
}

class _AgeRulesDialog extends StatefulWidget {
  const _AgeRulesDialog({required this.seasonId, required this.initial});

  final String seasonId;
  final AgeRules initial;

  @override
  State<_AgeRulesDialog> createState() => _AgeRulesDialogState();
}

class _AgeRulesDialogState extends State<_AgeRulesDialog> {
  late int? _player = widget.initial.playerMaxYear;
  late int? _gk = widget.initial.gkMaxYear;
  late final List<AgeQuota> _quotas = [...widget.initial.quotas];
  late int? _matchMax = widget.initial.matchMax;
  late int? _matchFieldMax = widget.initial.matchFieldMax;
  bool _saving = false;

  Future<int?> _pickYear(String title, int? current) async {
    const none = 0;
    final v = await showAdminOptionPicker<int>(
      context: context,
      title: title,
      items: [none, ..._years()],
      labelBuilder: (y) {
        if (y == none) return 'Sınır yok';
        final age = DateTime.now().year - y;
        return '$y ve öncesi ($age+)';
      },
      selected: current ?? none,
    );
    if (v == null) return current;
    return v == none ? null : v;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final rules = AgeRules(
      playerMaxYear: _player,
      gkMaxYear: _gk,
      quotas: _quotas,
      matchMax: _matchMax,
      matchFieldMax: _matchFieldMax,
    );
    try {
      await Supabase.instance.client
          .from('seasons')
          .update({'age_rules': rules.toJson()})
          .eq('id', widget.seasonId);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yaş ve kontenjan kuralları kaydedildi.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget value(String t) => Text(
      t,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
    String yearText(int? y) =>
        y == null ? 'Sınır yok' : '$y ve öncesi (${DateTime.now().year - y}+)';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: AdminDialogCloseOverlay(
        onClose: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
          decoration: adminDialogDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminDialogHeader(
                icon: Icons.rule_rounded,
                title: 'Yaş ve Kontenjan',
                subtitle: 'Sezon başında bir kez girilir',
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AdminFormSection(
                        title: 'Yaş Kuralı',
                        child: AdminFieldGroup(
                          children: [
                            AdminFieldRow(
                              icon: Icons.cake_outlined,
                              label: 'Oyuncular (en geç doğum yılı)',
                              onTap: () async {
                                final y = await _pickYear('Oyuncular', _player);
                                setState(() => _player = y);
                              },
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: kAdminMuted,
                              ),
                              child: value(yearText(_player)),
                            ),
                            AdminFieldRow(
                              icon: Icons.sports_handball_outlined,
                              label: 'Kaleci (en geç doğum yılı)',
                              onTap: () async {
                                final y = await _pickYear('Kaleci', _gk);
                                setState(() => _gk = y);
                              },
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: kAdminMuted,
                              ),
                              child: value(
                                _gk == null
                                    ? 'Oyuncu sınırı geçerli'
                                    : yearText(_gk),
                              ),
                            ),
                          ],
                        ),
                      ),
                      AdminFormSection(
                        title: 'Kadro Kontenjanları',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < _quotas.length; i++)
                              _QuotaTile(
                                quota: _quotas[i],
                                onTap: () async {
                                  final q = await showDialog<AgeQuota>(
                                    context: context,
                                    builder: (_) =>
                                        _QuotaDialog(initial: _quotas[i]),
                                  );
                                  if (q != null) setState(() => _quotas[i] = q);
                                },
                                onRemove: () =>
                                    setState(() => _quotas.removeAt(i)),
                              ),
                            const SizedBox(height: 4),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final q = await showDialog<AgeQuota>(
                                  context: context,
                                  builder: (_) => const _QuotaDialog(),
                                );
                                if (q != null) setState(() => _quotas.add(q));
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: kAdminAccent,
                                side: BorderSide(
                                  color: kAdminAccent.withValues(alpha: 0.5),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Kontenjan Ekle'),
                            ),
                          ],
                        ),
                      ),
                      AdminFormSection(
                        title: 'Maç Günü',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AdminFieldGroup(
                              children: [
                                _LimitRow(
                                  icon: Icons.assignment_outlined,
                                  label: 'Esamede en fazla',
                                  value: _matchMax,
                                  addValue: 3,
                                  onChanged: (v) =>
                                      setState(() => _matchMax = v),
                                ),
                                _LimitRow(
                                  icon: Icons.stadium_outlined,
                                  label: 'Sahada aynı anda en fazla',
                                  value: _matchFieldMax,
                                  addValue: 2,
                                  onChanged: (v) =>
                                      setState(() => _matchFieldMax = v),
                                ),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
                              child: Text(
                                'Kaleci dışındaki tüm kontenjanlı oyuncular '
                                'toplam sayılır. Sahadaki sınır doluyken yedekteki '
                                'kontenjanlı oyuncu ancak kontenjanlı bir oyuncunun '
                                'yerine girebilir.',
                                style: TextStyle(
                                  color: kAdminMuted,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AdminPrimaryButton(
                label: 'KAYDET',
                busy: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuotaTile extends StatelessWidget {
  const _QuotaTile({
    required this.quota,
    required this.onTap,
    required this.onRemove,
  });

  final AgeQuota quota;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final detail = [
      quota.gk ? 'Kaleci kontenjanı' : 'Kaleci hariç',
      'kadroda en fazla ${quota.max}',
      if (quota.fieldMax != null) 'sahada en fazla ${quota.fieldMax}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFF243247),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text(
                    '${quota.max}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _amber,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quota.yearsLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        detail,
                        style: const TextStyle(
                          color: kAdminMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Kaldır',
                  onPressed: onRemove,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFFF87171),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sınır satırı: sınır yoksa "Sınır yok" ve EKLE düğmesi; varsa sayaç.
/// Sayaç 0'a inince sınır kalkar.
class _LimitRow extends StatelessWidget {
  const _LimitRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.addValue,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final int? value;

  /// EKLE'ye basınca başlanacak değer.
  final int addValue;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return AdminFieldRow(
      icon: icon,
      label: label,
      trailing: v == null
          ? FilledButton(
              onPressed: () => onChanged(addValue),
              style: FilledButton.styleFrom(
                backgroundColor: kAdminAccent,
                foregroundColor: const Color(0xFF062A1C),
                minimumSize: const Size(72, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              child: const Text('EKLE'),
            )
          : _Stepper(
              value: v,
              min: 0,
              onChanged: (n) => onChanged(n == 0 ? null : n),
            ),
      child: Text(
        v == null ? 'Sınır yok' : 'Kişi',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.onChanged,
    this.min = 1,
  });

  final int value;
  final int min;
  final ValueChanged<int> onChanged;

  static const _max = 30;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Azalt',
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline, color: Colors.white70),
        ),
        Text(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        IconButton(
          tooltip: 'Artır',
          onPressed: value < _max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
        ),
      ],
    );
  }
}

/// Doğum yıllarını listeden çoklu seçtirir.
Future<Set<int>?> _pickYears(BuildContext context, Set<int> initial) {
  final now = DateTime.now().year;
  final options = [for (var y = now - 20; y >= now - 60; y--) y];
  final selected = {...initial};
  return showDialog<Set<int>>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: StatefulBuilder(
        builder: (ctx, setState) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.75,
          ),
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
          decoration: adminDialogDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  'Doğum Yılları',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (_, i) {
                    final y = options[i];
                    final on = selected.contains(y);
                    return CheckboxListTile(
                      value: on,
                      dense: true,
                      activeColor: _amber,
                      checkColor: const Color(0xFF1F1300),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        '$y',
                        style: TextStyle(
                          color: on ? _amber : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      secondary: Text(
                        '${now - y} yaş',
                        style: const TextStyle(color: kAdminMuted),
                      ),
                      onChanged: (v) => setState(
                        () => v == true ? selected.add(y) : selected.remove(y),
                      ),
                    );
                  },
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: AdminPrimaryButton(
                  label: selected.isEmpty
                      ? 'SEÇ'
                      : 'SEÇ (${selected.length})',
                  onPressed: () => Navigator.pop(ctx, selected),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Kontenjan ekle / düzenle: yıllar (çoklu), kadroda en fazla, kaleci
/// kontenjanı mı. Maç günü sınırları sezon genelinde girilir.
class _QuotaDialog extends StatefulWidget {
  const _QuotaDialog({this.initial});

  final AgeQuota? initial;

  @override
  State<_QuotaDialog> createState() => _QuotaDialogState();
}

class _QuotaDialogState extends State<_QuotaDialog> {
  late Set<int> _years = {...?widget.initial?.years};
  late int _max = widget.initial?.max ?? 3;
  late bool _gk = widget.initial?.gk ?? false;

  @override
  Widget build(BuildContext context) {
    final years = _years.toList()..sort();
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: AdminDialogCloseOverlay(
        onClose: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
          decoration: adminDialogDecoration(),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminDialogHeader(
                  icon: Icons.groups_2_outlined,
                  title: widget.initial == null
                      ? 'Kontenjan Ekle'
                      : 'Kontenjan',
                ),
                AdminFormSection(
                  title: 'Kontenjan',
                  child: AdminFieldGroup(
                    children: [
                      AdminFieldRow(
                        icon: Icons.cake_outlined,
                        label: 'Doğum yılları',
                        onTap: () async {
                          final v = await _pickYears(context, _years);
                          if (v != null) setState(() => _years = v);
                        },
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: kAdminMuted,
                        ),
                        child: Text(
                          years.isEmpty ? 'Seçilmedi' : years.join(', '),
                          style: TextStyle(
                            color: years.isEmpty ? kAdminMuted : Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      AdminFieldRow(
                        icon: Icons.groups_outlined,
                        label: 'Kadroda en fazla',
                        trailing: _Stepper(
                          value: _max,
                          onChanged: (v) => setState(() => _max = v),
                        ),
                        child: const Text(
                          'Kişi',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      AdminFieldRow(
                        icon: Icons.sports_handball_outlined,
                        label: 'Kimler için',
                        onTap: () => setState(() => _gk = !_gk),
                        trailing: Switch.adaptive(
                          value: _gk,
                          activeTrackColor: kAdminAccent,
                          onChanged: (v) => setState(() => _gk = v),
                        ),
                        child: Text(
                          _gk ? 'Yalnız kaleciler' : 'Kaleci dışındakiler',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                AdminPrimaryButton(
                  label: widget.initial == null ? 'EKLE' : 'TAMAM',
                  onPressed: _years.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          AgeQuota(
                            years: years,
                            max: _max,
                            fieldMax: widget.initial?.fieldMax,
                            gk: _gk,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
