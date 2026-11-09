import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import 'biometric_login.dart';
import 'registration/registration_service.dart' show RegistrationService;

/// Kayıtlı kullanıcının şifre değiştirmesi: önce telefona kod gider
/// (sms_otp_provider ayarına göre SMS ya da yönetici iletir), sonra yeni
/// şifre belirlenir. Diğer cihazlardaki oturumlar kapanır.
Future<void> showPasswordChangePopup(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showAdminPopup<bool>(
    context: context,
    builder: (ctx) => const _PasswordChangeBody(),
  );
  if (ok == true) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Şifren değiştirildi.')),
    );
  }
}

class _PasswordChangeBody extends StatefulWidget {
  const _PasswordChangeBody();

  @override
  State<_PasswordChangeBody> createState() => _PasswordChangeBodyState();
}

class _PasswordChangeBodyState extends State<_PasswordChangeBody> {
  SupabaseClient get _sb => Supabase.instance.client;

  final _code = TextEditingController();
  final _pass1 = TextEditingController();
  final _pass2 = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _pass1.dispose();
    _pass2.dispose();
    super.dispose();
  }

  String _message(String code) => switch (code) {
    'disabled' => 'Şifre değiştirme şu an kapalı.',
    'no_phone' => 'Bu hesapta telefon numarası bulunamadı.',
    _ =>
      RegistrationService.message(code) ??
          'İşlem tamamlanamadı. Lütfen tekrar deneyin.',
  };

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = (await _sb.rpc('password_change_otp_send') ?? '').toString();
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (r == 'sent') {
          _sent = true;
        } else {
          _error = _message(r);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Bağlantı hatası. Lütfen tekrar deneyin.';
        });
      }
    }
  }

  Future<void> _save() async {
    final p1 = _pass1.text;
    if (_code.text.replaceAll(RegExp(r'\D'), '').length < 4) {
      setState(() => _error = 'Doğrulama kodunu yaz.');
      return;
    }
    if (p1 != _pass2.text) {
      setState(() => _error = 'Şifreler aynı değil.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r =
          (await _sb.rpc(
                    'password_change_with_otp',
                    params: {'p_code': _code.text.trim(), 'p_new': p1},
                  ) ??
                  '')
              .toString();
      if (!mounted) return;
      if (r == 'ok') {
        await BiometricLogin.passwordChanged(p1);
        if (mounted) Navigator.pop(context, true);
        return;
      }
      setState(() {
        _busy = false;
        _error = _message(r);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Bağlantı hatası. Lütfen tekrar deneyin.';
        });
      }
    }
  }

  Widget _field(
    IconData icon,
    String label,
    TextEditingController c, {
    bool secret = false,
    TextInputType? type,
    List<TextInputFormatter>? formatters,
  }) => AdminFieldRow(
    icon: icon,
    label: label,
    child: TextField(
      controller: c,
      enabled: !_busy,
      obscureText: secret,
      keyboardType: type,
      inputFormatters: formatters,
      onChanged: (_) => setState(() => _error = null),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      decoration: adminInlineInputDecoration(hint: label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AdminDialogCloseOverlay(
      onClose: _busy ? null : () => Navigator.pop(context, false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: AdminDialogHeader(
              icon: Icons.vpn_key_outlined,
              title: 'Şifre Değiştir',
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_sent)
                    const Text(
                      'Güvenliğin için önce hesabındaki telefon numarasına bir '
                      'doğrulama kodu göndereceğiz.',
                      style: TextStyle(
                        color: kAdminMuted,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    )
                  else ...[
                    AdminFormSection(
                      title: 'Doğrulama',
                      child: AdminFieldGroup(
                        children: [
                          _field(
                            Icons.sms_outlined,
                            'Doğrulama kodu',
                            _code,
                            type: TextInputType.number,
                            formatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AdminFormSection(
                      title: 'Yeni şifre',
                      child: AdminFieldGroup(
                        children: [
                          _field(
                            Icons.lock_outline_rounded,
                            'Yeni şifre',
                            _pass1,
                            secret: true,
                          ),
                          _field(
                            Icons.lock_outline_rounded,
                            'Yeni şifre (tekrar)',
                            _pass2,
                            secret: true,
                          ),
                        ],
                      ),
                    ),
                    const Text(
                      'Şifre 6-10 karakter olmalı ve en az bir rakam veya '
                      'özel karakter içermeli. Diğer cihazlardaki oturumların '
                      'kapanır.',
                      style: TextStyle(color: kAdminMuted, fontSize: 12.5),
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: kAdminDanger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminPrimaryButton(
                  label: _sent ? 'ŞİFREYİ KAYDET' : 'KOD GÖNDER',
                  busy: _busy,
                  onPressed: _busy ? null : (_sent ? _save : _send),
                ),
                if (_sent)
                  TextButton(
                    onPressed: _busy ? null : _send,
                    style: TextButton.styleFrom(foregroundColor: kAdminAccent),
                    child: const Text('Kodu tekrar gönder'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
