import 'package:flutter/material.dart';

import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/admin_form.dart';
import 'phone_verify_card.dart';
import 'registration_service.dart';

/// Kayıt akışının son adımı: telefon doğrulama ve şifre; [submit] hesabı
/// açar (sunucu sonuç kodu döner), başarılıysa giriş yapılır.
class RegisterPhoneScreen extends StatefulWidget {
  const RegisterPhoneScreen({
    super.key,
    required this.kind,
    required this.name,
    required this.buttonLabel,
    required this.successMessage,
    required this.submit,
    this.then,
  });

  /// 'player' ya da 'organizer'.
  final String kind;
  final String name;
  final String buttonLabel;
  final String successMessage;
  final Future<String> Function(String raw10, String code, String password)
  submit;

  /// Giriş yapıldıktan sonra ana sayfanın üstünde açılacak ekran.
  final void Function(BuildContext context)? then;

  @override
  State<RegisterPhoneScreen> createState() => _RegisterPhoneScreenState();
}

class _RegisterPhoneScreenState extends State<RegisterPhoneScreen> {
  final _phone = PhoneVerifyController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _phone.addListener(_refresh);
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() => _error = null);
  }

  Future<void> _submit() async {
    if (!_phone.ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final raw10 = _phone.raw10!;
    final password = _phone.password;
    try {
      final r = await widget.submit(raw10, _phone.code, password);
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
        message: widget.successMessage,
        then: widget.then,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'İşlem tamamlanamadı. Lütfen tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Telefon Doğrulama',
      body: AutofillGroup(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 18),
              child: Text(
                'Numaranı doğrula ve şifreni belirle. Giriş yaparken bu '
                'numara ve şifreyi kullanacaksın.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
            PhoneVerifyCard(
              controller: _phone,
              kind: widget.kind,
              name: () => widget.name,
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
              label: widget.buttonLabel,
              icon: Icons.check_rounded,
              busy: _busy,
              onPressed: _phone.ready ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }
}
