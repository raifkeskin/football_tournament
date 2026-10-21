import 'package:flutter/material.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../tournament_request/tournament_request.dart';
import 'register_phone_screen.dart';
import 'registration_service.dart';

/// Turnuva Kurucu / Sorumlusu kaydı: ad, soyad → telefon doğrulama, şifre.
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

  @override
  void initState() {
    super.initState();
    _first.addListener(_refresh);
    _last.addListener(_refresh);
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool get _namesOk =>
      _first.text.trim().length >= 2 && _last.text.trim().length >= 2;

  void _next() {
    if (!_namesOk) return;
    FocusScope.of(context).unfocus();
    final first = trTitleCase(_first.text);
    final last = trTitleCase(_last.text);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'RegisterPhoneScreen'),
        builder: (_) => RegisterPhoneScreen(
          kind: 'organizer',
          name: '$first $last',
          buttonLabel: 'HESABIMI OLUŞTUR',
          successMessage: 'Hesabınız oluşturuldu.',
          submit: (raw10, code, password) =>
              RegistrationService.registerOrganizer(
                raw10: raw10,
                code: code,
                password: password,
                firstName: first,
                lastName: last,
              ),
          then: (ctx) => TournamentRequestAccess.open(ctx),
        ),
      ),
    );
  }

  Widget _nameField(TextEditingController c, String hint) => TextField(
    controller: c,
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 18),
            child: Text(
              'Kimlik gerekmez. Hesabın açılınca turnuvanı kurmak için talep '
              'oluşturabilirsin.',
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
          AdminPrimaryButton(
            label: 'İLERİ',
            icon: Icons.arrow_forward_rounded,
            onPressed: _namesOk ? _next : null,
          ),
          const SizedBox(height: 10),
          const Text(
            'Sonraki adım: telefon doğrulama, ardından turnuva bilgileri ve '
            'teklif',
            textAlign: TextAlign.center,
            style: TextStyle(color: kAdminMuted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
