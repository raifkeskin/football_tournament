import 'package:flutter/material.dart';
import '../../../core/utils/friendly_error.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import 'match_insights.dart';

/// Sezonun futbolcu puanlama ayarı: aç/kapa, otomatik kurallar, süre
/// kuralları ve "Olay ekle" olaylarının puanları (hepsi değiştirilebilir).
class RatingSettingsScreen extends StatefulWidget {
  const RatingSettingsScreen({
    super.key,
    required this.seasonId,
    required this.seasonName,
  });

  final String seasonId;
  final String seasonName;

  static Future<void> open(BuildContext context, String id, String name) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'RatingSettingsScreen'),
          builder: (_) => RatingSettingsScreen(seasonId: id, seasonName: name),
        ),
      );

  @override
  State<RatingSettingsScreen> createState() => _RatingSettingsScreenState();
}

class _RatingSettingsScreenState extends State<RatingSettingsScreen> {
  RatingRules? _rules;
  final Map<String, TextEditingController> _ctrl = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    RatingRulesRepo.load(widget.seasonId).then((r) {
      if (!mounted) return;
      setState(() {
        _rules = r.rules;
        for (final k in RatingRules.defaults.keys) {
          _ctrl[k] = TextEditingController(text: _fmt(r.rules.v(k)));
        }
      });
    });
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmt(double v) => v == v.roundToDouble() && v.abs() >= 10
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(1);

  void _reset() {
    setState(() {
      for (final e in RatingRules.defaults.entries) {
        _ctrl[e.key]?.text = _fmt(e.value);
      }
    });
  }

  Future<void> _save() async {
    final r = _rules;
    if (r == null) return;
    final vals = <String, double>{};
    for (final e in _ctrl.entries) {
      final v = double.tryParse(e.value.text.trim().replaceAll(',', '.'));
      if (v != null) vals[e.key] = v;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final next = r.copyWith(values: vals);
      await RatingRulesRepo.save(widget.seasonId, next);
      if (!mounted) return;
      setState(() => _rules = next);
      messenger.showSnackBar(
        const SnackBar(content: Text('Puanlama ayarları kaydedildi.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Kaydedilemedi: ${friendlyErrorText(e)}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _section(String title, {String? note}) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: kAdminMuted,
            fontWeight: FontWeight.w800,
            fontSize: 12,
            letterSpacing: 0.4,
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 3),
          Text(note, style: const TextStyle(color: kAdminMuted, fontSize: 12)),
        ],
      ],
    ),
  );

  Widget _row(String key, String label) {
    final def = RatingRules.defaults[key] ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          SizedBox(
            width: 76,
            child: TextField(
              controller: _ctrl[key],
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
              ],
              style: TextStyle(
                color:
                    key.startsWith('m_') ||
                        RatingRules.auto.any(
                          (r) => r.$1 == key && r.$1 != 'base',
                        )
                    ? (def >= 0
                          ? const Color(0xFF86EFAC)
                          : const Color(0xFFFCA5A5))
                    : Colors.white,
                fontWeight: FontWeight.w800,
              ),
              decoration: const InputDecoration(isDense: true),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _rules;
    return AdminPageScaffold(
      title: 'Futbolcu Puanlama',
      bottomBar: r == null
          ? null
          : AdminPrimaryButton(
              label: _saving ? 'KAYDEDİLİYOR…' : 'KAYDET',
              icon: Icons.check_rounded,
              onPressed: _saving ? null : _save,
            ),
      body: r == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.seasonName,
                        style: const TextStyle(
                          color: kAdminMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _reset,
                      child: const Text('Varsayılana dön'),
                    ),
                  ],
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  activeTrackColor: kAdminAccent,
                  value: r.enabled,
                  onChanged: (v) =>
                      setState(() => _rules = r.copyWith(enabled: v)),
                  title: const Text(
                    'Maç kadrosunda futbolcu puanı',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: const Text(
                    'Kapalıyken puan hiçbir ekranda görünmez.',
                    style: TextStyle(color: kAdminMuted),
                  ),
                ),
                _section(
                  'OTOMATİK KURALLAR',
                  note:
                      'Gol, kart ve sonuç maç olaylarından hesaplanır. '
                      'Puan 3.0 – 10.0 arasında tutulur.',
                ),
                for (final x in RatingRules.auto) _row(x.$1, x.$2),
                _section('SÜRE'),
                for (final x in RatingRules.duration) _row(x.$1, x.$2),
                _section(
                  'OLAY EKLE PUANLARI',
                  note: 'Maç ekranındaki "Olay ekle" ile girilen anlar.',
                ),
                for (final g in MomentKind.groups) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 2),
                    child: Text(
                      g,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  for (final k in MomentKind.all.where((k) => k.group == g))
                    _row('m_${k.key}', k.label),
                ],
              ],
            ),
    );
  }
}
