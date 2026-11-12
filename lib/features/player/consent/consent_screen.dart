import 'package:flutter/material.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import 'consent_service.dart';
import 'consent_texts.dart';
import 'consent_widgets.dart';

/// Oyuncunun KVKK / sağlık onaylarını verdiği ya da geri aldığı ekran.
/// Kaydedilirse `true` döner.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({
    super.key,
    required this.playerId,
    required this.consents,
  });

  final String playerId;

  /// Yürürlükteki metinler ve başlangıçta işaretli kutular.
  final MyConsents consents;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  final _service = ConsentService();
  late final ConsentDoc _doc = widget.consents.doc;
  late final Set<String> _granted = {...widget.consents.granted};
  final Set<String> _expanded = {};
  bool _saving = false;

  bool get _requiredOk => _doc.items
      .where((t) => t.required)
      .every((t) => _granted.contains(t.key));

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.save(widget.playerId, _doc, _granted);
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
                    'Turnuvada oynayabilmek için zorunlu onaylar gerekir; '
                    '"isteğe bağlı" yazanlar senin tercihin. Onaylarını '
                    'istediğin zaman buradan geri alabilirsin.',
                    style: TextStyle(color: kAdminMuted, fontSize: 13),
                  ),
                ),
                for (final t in _doc.items) _consentCard(t),
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

  Widget _consentCard(ConsentItem t) {
    final open = _expanded.contains(t.key);
    final checked = _granted.contains(t.key);
    return AdminFormSection(
      title: t.required ? t.title : '${t.title} (isteğe bağlı)',
      child: AdminFieldGroup(
        children: [
          InkWell(
            onTap: () => setState(
              () => open ? _expanded.remove(t.key) : _expanded.add(t.key),
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
                    ConsentBodyText(t.body),
                  ],
                ],
              ),
            ),
          ),
          InkWell(
            onTap: _saving
                ? null
                : () => setState(
                    () =>
                        checked ? _granted.remove(t.key) : _granted.add(t.key),
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
                                ? _granted.add(t.key)
                                : _granted.remove(t.key),
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
