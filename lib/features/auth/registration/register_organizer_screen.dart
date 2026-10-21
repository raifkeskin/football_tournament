import 'package:flutter/material.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../tournament_request/tournament_request.dart';
import 'phone_verify_card.dart';
import 'registration_service.dart';

/// Turnuva Kurucu / Sorumlusu kaydı: ad, soyad, telefon doğrulama, şifre.
/// Hesap açılınca turnuva talebi ekranı açılır.
class RegisterOrganizerScreen extends StatefulWidget {
  const RegisterOrganizerScreen({super.key});

  @override
  State<RegisterOrganizerScreen> createState() =>
      _RegisterOrganizerScreenState();
}

class _RegisterOrganizerScreenState extends State<RegisterOrganizerScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = PhoneVerifyController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _phone.addListener(_refresh);
    _first.addListener(_refresh);
    _last.addListener(_refresh);
  }

  @override
  void dispose() {
    _phone.dispose();
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() => _error = null);
  }

  bool get _namesOk =>
      _first.text.trim().length >= 2 && _last.text.trim().length >= 2;

  Future<void> _submit() async {
    if (!_namesOk) {
      setState(() => _error = 'Adınızı ve soyadınızı yazın.');
      return;
    }
    if (!_phone.ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final raw10 = _phone.raw10!;
    final password = _phone.password;
    try {
      final r = await RegistrationService.registerOrganizer(
        raw10: raw10,
        code: _phone.code,
        password: password,
        firstName: trTitleCase(_first.text),
        lastName: trTitleCase(_last.text),
      );
      if (!mounted) return;
      if (r != 'ok') {
        if (r == 'expired' || r == 'too_many_attempts' || r == 'wrong_code') {
          _phone.restart();
        }
        setState(() => _error = RegistrationService.message(r));
        return;
      }
      await RegistrationService.signInAndOpenHome(
        context,
        raw10: raw10,
        password: password,
        message: 'Hesabınız oluşturuldu.',
        then: (ctx) => TournamentRequestAccess.open(ctx),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'İşlem tamamlanamadı. Lütfen tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _nameField(TextEditingController c, String hint) => TextField(
    controller: c,
    enabled: !_busy,
    textCapitalization: TextCapitalization.words,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    ),
    decoration: adminInlineInputDecoration(hint: hint),
  );

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Turnuva Kurucu / Sorumlusu',
      bandBack: false,
      body: AutofillGroup(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 18),
              child: Text(
                'Kimlik gerekmez. Hesabın açılınca turnuvanı kurmak için '
                'talep oluşturabilirsin.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
            AdminFormSection(
              title: 'Bilgileriniz',
              child: AdminFieldGroup(
                children: [
                  AdminFieldRow(
                    icon: Icons.person_outline_rounded,
                    label: 'Ad',
                    child: _nameField(_first, 'Adınız'),
                  ),
                  AdminFieldRow(
                    icon: Icons.badge_outlined,
                    label: 'Soyad',
                    child: _nameField(_last, 'Soyadınız'),
                  ),
                ],
              ),
            ),
            PhoneVerifyCard(
              controller: _phone,
              kind: 'organizer',
              name: () => '${_first.text.trim()} ${_last.text.trim()}'.trim(),
              enabled: !_busy,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: kAdminDanger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            AdminPrimaryButton(
              label: 'HESABIMI OLUŞTUR',
              icon: Icons.check_rounded,
              busy: _busy,
              onPressed: _phone.ready && _namesOk ? _submit : null,
            ),
            const SizedBox(height: 10),
            const Text(
              'Sonraki adım: turnuva bilgileri ve teklif',
              textAlign: TextAlign.center,
              style: TextStyle(color: kAdminMuted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
