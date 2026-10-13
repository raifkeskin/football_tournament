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
                        title: 'Kontenjanlar',
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

/// Kontenjan ekle / düzenle: yıllar (çoklu), kadroda ve sahada en fazla,
/// kaleci kontenjanı mı.
class _QuotaDialog extends StatefulWidget {
  const _QuotaDialog({this.initial});

  final AgeQuota? initial;

  @override
  State<_QuotaDialog> createState() => _QuotaDialogState();
}

class _QuotaDialogState extends State<_QuotaDialog> {
  late final Set<int> _years = {...?widget.initial?.years};
  late int _max = widget.initial?.max ?? 3;
  late int? _field = widget.initial?.fieldMax;
  late bool _gk = widget.initial?.gk ?? false;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().year;
    final options = [for (var y = now - 45; y <= now - 25; y++) y];
    Widget stepper(int v, ValueChanged<int> set, {int min = 1}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: v > min ? () => set(v - 1) : null,
          icon: const Icon(Icons.remove_circle_outline, color: Colors.white70),
        ),
        Text(
          '$v',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        IconButton(
          onPressed: v < 11 ? () => set(v + 1) : null,
          icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
        ),
      ],
    );

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
                  title: 'Doğum Yılları',
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final y in options)
                        FilterChip(
                          label: Text('$y'),
                          selected: _years.contains(y),
                          showCheckmark: false,
                          selectedColor: _amber,
                          backgroundColor: const Color(0xFF334155),
                          labelStyle: TextStyle(
                            color: _years.contains(y)
                                ? const Color(0xFF1F1300)
                                : Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          side: BorderSide.none,
                          onSelected: (on) => setState(
                            () => on ? _years.add(y) : _years.remove(y),
                          ),
                        ),
                    ],
                  ),
                ),
                AdminFormSection(
                  title: 'Sınır',
                  child: AdminFieldGroup(
                    children: [
                      AdminFieldRow(
                        icon: Icons.groups_outlined,
                        label: 'Kadroda en fazla',
                        trailing: stepper(
                          _max,
                          (v) => setState(() => _max = v),
                        ),
                        child: const Text(
                          'Kişi',
                          style: TextStyle(color: Colors.white, fontSize: 15),
                        ),
                      ),
                      AdminFieldRow(
                        icon: Icons.stadium_outlined,
                        label: 'Sahada aynı anda en fazla',
                        trailing: _field == null
                            ? TextButton(
                                onPressed: () => setState(() => _field = 2),
                                child: const Text('Sınır koy'),
                              )
                            : stepper(
                                _field!,
                                (v) => setState(() => _field = v),
                              ),
                        child: Text(
                          _field == null ? 'Sınır yok' : 'Kişi',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
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
                if (_field != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() => _field = null),
                      child: const Text(
                        'Saha sınırını kaldır',
                        style: TextStyle(color: kAdminMuted),
                      ),
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
                            years: _years.toList()..sort(),
                            max: _max,
                            fieldMax: _field,
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
