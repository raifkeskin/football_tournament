import 'package:flutter/material.dart';

import '../../../core/services/app_session.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../home/screens/main_navigator.dart';

/// Geçici şifreyle giriş yapan kullanıcı burada kendi şifresini belirler.
/// Geri dönülürse oturum kapatılır (geçici şifreyle uygulamada kalınmaz).
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.rememberMe = false});

  /// Girişte "Beni Hatırla" seçildiyse şifre belirlendikten sonra uygulanır.
  final bool rememberMe;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _pass1Controller = TextEditingController();
  final _pass2Controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pass1Controller.dispose();
    _pass2Controller.dispose();
    super.dispose();
  }

  static bool _lengthOk(String v) => v.length >= 6 && v.length <= 10;
  static bool _hasDigitOrSpecial(String v) =>
      RegExp(r'[^A-Za-z]').hasMatch(v);

  Future<void> _save() async {
    final p1 = _pass1Controller.text.trim();
    final p2 = _pass2Controller.text.trim();
    if (!_lengthOk(p1) || !_hasDigitOrSpecial(p1)) {
      setState(
        () => _error =
            'Şifre 6-10 karakter olmalı ve en az bir rakam veya özel '
            'karakter içermeli.',
      );
      return;
    }
    if (p1 != p2) {
      setState(() => _error = 'Şifreler eşleşmiyor.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final session = AppSession.of(context);
    try {
      await ServiceLocator.authService.changeOwnPassword(p1);
      await AppSessionController.setRememberMe(widget.rememberMe);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) =>
              const MainNavigator(initialTabIndex: MainNavigator.profileTab),
        ),
        (Route<dynamic> route) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şifreniz kaydedildi.')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      setState(
        () => _error = msg.contains('different from the old')
            ? 'Yeni şifre geçici şifreden farklı olmalı.'
            : 'Şifre kaydedilemedi. Lütfen tekrar deneyin.',
      );
      // Oturum düşmüşse kullanıcı yeniden giriş yapmalı.
      if (session.value.user == null && mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _passwordField(TextEditingController c, String hint) {
    return TextField(
      controller: c,
      enabled: !_busy,
      obscureText: true,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _save(),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      decoration: adminInlineInputDecoration(hint: hint),
    );
  }

  Widget _rule(String text, bool ok) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: ok ? kAdminAccent : kAdminMuted,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: ok ? Colors.white70 : kAdminMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p1 = _pass1Controller.text.trim();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        await AppSession.of(context).signOut();
        nav.pop();
      },
      child: AdminPageScaffold(
        title: 'Yeni Şifre Belirle',
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 18),
              child: Text(
                'Geçici şifreyle giriş yaptınız. Devam etmek için kendi '
                'şifrenizi belirleyin.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
            AdminFormSection(
              title: 'Yeni Şifre',
              child: AdminFieldGroup(
                children: [
                  AdminFieldRow(
                    icon: Icons.lock_outline_rounded,
                    label: 'Şifre',
                    child: _passwordField(_pass1Controller, '6-10 karakter'),
                  ),
                  AdminFieldRow(
                    icon: Icons.lock_reset_rounded,
                    label: 'Şifre (Tekrar)',
                    child: _passwordField(_pass2Controller, 'Aynı şifre'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _rule('6-10 karakter', _lengthOk(p1)),
                  _rule(
                    'En az 1 rakam veya özel karakter',
                    _hasDigitOrSpecial(p1),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kAdminDanger,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
            ],
            AdminPrimaryButton(label: 'KAYDET', busy: _busy, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
