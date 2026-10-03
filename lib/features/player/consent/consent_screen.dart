import 'package:flutter/material.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import 'consent_service.dart';
import 'consent_texts.dart';

/// Oyuncunun KVKK / sağlık onaylarını verdiği ya da geri aldığı ekran.
/// Kaydedilirse `true` döner.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({
    super.key,
    required this.playerId,
    required this.initial,
  });

  final String playerId;
  final Set<ConsentType> initial;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  final _service = ConsentService();
  late final Set<ConsentType> _granted = {...widget.initial};
  final Set<ConsentType> _expanded = {};
  bool _saving = false;

  bool get _requiredOk => kConsentTexts
      .where((t) => t.required)
      .every((t) => _granted.contains(t.type));

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.save(widget.playerId, _granted);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _requiredOk
                ? 'Onayların kaydedildi.'
                : 'Kaydedildi. Zorunlu onaylar eksik olduğu için uyarı '
                      'görünmeye devam edecek.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
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
    return AdminPageScaffold(
      title: 'İzinler ve Beyanlar',
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 16),
                  child: Text(
                    'Turnuvada oynayabilmek için ilk üç onay zorunludur; '
                    'fotoğraf izni isteğe bağlıdır. Onaylarını istediğin '
                    'zaman buradan geri alabilirsin.',
                    style: TextStyle(color: kAdminMuted, fontSize: 13),
                  ),
                ),
                for (final t in kConsentTexts) _consentCard(t),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: AdminPrimaryButton(
                label: 'KAYDET',
                icon: Icons.check_rounded,
                busy: _saving,
                onPressed: _save,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _consentCard(ConsentText t) {
    final open = _expanded.contains(t.type);
    final checked = _granted.contains(t.type);
    return AdminFormSection(
      title: t.required ? t.title : '${t.title} (isteğe bağlı)',
      child: AdminFieldGroup(
        children: [
          InkWell(
            onTap: () => setState(
              () => open ? _expanded.remove(t.type) : _expanded.add(t.type),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          open ? 'Metni gizle' : 'Metni oku',
                          style: const TextStyle(
                            color: kAdminAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        open
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: kAdminAccent,
                      ),
                    ],
                  ),
                  if (open) ...[
                    const SizedBox(height: 8),
                    Text(
                      t.body.trim(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          InkWell(
            onTap: _saving
                ? null
                : () => setState(
                    () => checked
                        ? _granted.remove(t.type)
                        : _granted.add(t.type),
                  ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 14, 6),
              child: Row(
                children: [
                  Checkbox(
                    value: checked,
                    activeColor: kAdminAccent,
                    onChanged: _saving
                        ? null
                        : (v) => setState(
                            () => v == true
                                ? _granted.add(t.type)
                                : _granted.remove(t.type),
                          ),
                  ),
                  Expanded(
                    child: Text(
                      t.checkbox,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
