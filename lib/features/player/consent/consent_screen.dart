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

  /// Kutuya dokununca: işaretliyse kaldırır; değilse metni açar, sonuna
  /// kadar okunup onaylanınca işaretler.
  Future<void> _toggle(ConsentItem t) async {
    if (_saving) return;
    if (_granted.contains(t.key)) {
      setState(() => _granted.remove(t.key));
      return;
    }
    final ok = await showConsentReadDialog(context, t);
    if (ok == true && mounted) setState(() => _granted.add(t.key));
  }

  Widget _consentCard(ConsentItem t) {
    final checked = _granted.contains(t.key);
    return AdminFormSection(
      title: t.required ? t.title : '${t.title} (isteğe bağlı)',
      child: AdminFieldGroup(
        children: [
          InkWell(
            onTap: _saving ? null : () => _toggle(t),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 14, 6),
              child: Row(
                children: [
                  Checkbox(
                    value: checked,
                    activeColor: kAdminAccent,
                    onChanged: _saving ? null : (_) => _toggle(t),
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
