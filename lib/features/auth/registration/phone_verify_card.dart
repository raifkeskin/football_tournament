import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/app_settings.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../password_input.dart';
import '../widgets/phone_input.dart';
import 'registration_service.dart';

/// Telefon doğrulama kartının durumu; üst ekran şifre ve kodu buradan okur.
class PhoneVerifyController extends ChangeNotifier {
  /// Kod gönderilen numara (null: telefon adımı).
  String? raw10;
  String code = '';

  /// Kod doğrulandı: şifre adımı.
  bool verified = false;
  String password = '';
  String password2 = '';

  /// Şifre kuralları tutuyor ve iki şifre aynı.
  bool get passwordOk =>
      PasswordRules.lengthOk(password) &&
      PasswordRules.hasDigitOrSpecial(password) &&
      !PasswordRules.isWeak(password, phone: raw10) &&
      password == password2;

  bool get ready => verified && passwordOk;

  /// Sunucu kodu kabul etmediyse (süresi doldu vb.) telefon adımına dönülür.
  void restart() {
    raw10 = null;
    code = '';
    verified = false;
    notifyListeners();
  }

  void _changed() => notifyListeners();
}

/// Kayıt ekranlarındaki telefon doğrulama kartı: telefon → kod → şifre,
/// üç adım aynı kartta sırayla açılır.
class PhoneVerifyCard extends StatefulWidget {
  const PhoneVerifyCard({
    super.key,
    required this.controller,
    required this.kind,
    this.name,
    this.enabled = true,
  });

  final PhoneVerifyController controller;

  /// 'player' ya da 'organizer'.
  final String kind;

  /// Adminin bildiriminde görünen ad (test modunda).
  final String Function()? name;
  final bool enabled;

  @override
  State<PhoneVerifyCard> createState() => _PhoneVerifyCardState();
}

class _PhoneVerifyCardState extends State<PhoneVerifyCard> {
  static const _resendSeconds = 60;

  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _pass1 = TextEditingController();
  final _pass2 = TextEditingController();
  final _pass1Focus = FocusNode();
  final _pass2Focus = FocusNode();
  bool _busy = false;
  String? _error;
  int _resendLeft = 0;
  Timer? _timer;

  PhoneVerifyController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onController);
  }

  @override
  void dispose() {
    _c.removeListener(_onController);
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    _pass1.dispose();
    _pass2.dispose();
    _pass1Focus.dispose();
    _pass2Focus.dispose();
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    if (_c.raw10 == null) {
      _code.clear();
      _pass1.clear();
      _pass2.clear();
    }
    setState(() {});
  }

  void _startTimer() {
    _timer?.cancel();
    _resendLeft = _resendSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendLeft--);
      if (_resendLeft <= 0) t.cancel();
    });
  }

  Future<void> _send({String? phone}) async {
    final raw10 = phone ?? normalizePhoneToRaw10(_phone.text);
    if (raw10.length != 10 || !raw10.startsWith('5')) {
      setState(() => _error = 'Geçerli bir cep telefonu numarası girin.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await RegistrationService.sendCode(
        raw10: raw10,
        kind: widget.kind,
        name: widget.name?.call(),
      );
      if (!mounted) return;
      if (r == 'sent') {
        _c
          ..raw10 = raw10
          ..code = ''
          ..verified = false;
        _code.clear();
        _startTimer();
        _c._changed();
      } else {
        setState(() => _error = RegistrationService.message(r));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Kod gönderilemedi. Lütfen tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Size gelen 6 haneli kodu girin.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await RegistrationService.checkCode(
        raw10: _c.raw10!,
        code: code,
      );
      if (!mounted) return;
      if (r == 'ok') {
        _c
          ..code = code
          ..verified = true;
        _timer?.cancel();
        _c._changed();
        _pass1Focus.requestFocus();
      } else {
        setState(() => _error = RegistrationService.message(r));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Kod denetlenemedi. Lütfen tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw10 = _c.raw10;
    final step = raw10 == null
        ? 1
        : _c.verified
        ? 3
        : 2;
    return AdminFormSection(
      title: 'Telefon Doğrulama',
      trailing: Text(
        '$step / 3',
        style: const TextStyle(
          color: kAdminMuted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (step == 1) ..._phoneStep(),
          if (step == 2) ..._codeStep(raw10!),
          if (step == 3) ..._passwordStep(raw10!),
        ],
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String hint,
    required VoidCallback onSubmitted,
    TextInputType? keyboardType,
    String? prefixText,
    List<TextInputFormatter>? formatters,
    Iterable<String>? autofill,
    FocusNode? passwordFocus,
    ValueChanged<String>? onChanged,
  }) {
    TextField field({TextInputType? type, Widget? suffix}) => TextField(
      controller: controller,
      focusNode: passwordFocus,
      enabled: widget.enabled && !_busy,
      keyboardType: type ?? keyboardType,
      obscureText: passwordFocus != null,
      inputFormatters: formatters,
      autofillHints: autofill,
      onChanged: (v) {
        if (_error != null) setState(() => _error = null);
        onChanged?.call(v);
      },
      onSubmitted: (_) => onSubmitted(),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      decoration: adminInlineInputDecoration(hint: hint, prefixText: prefixText)
          .copyWith(
            suffixIcon: suffix,
            suffixIconConstraints: const BoxConstraints(),
          ),
    );
    final focus = passwordFocus;
    if (focus == null) return field();
    return ValueListenableBuilder<bool>(
      valueListenable: PasswordKeyboard.numeric,
      builder: (context, _, _) => field(
        type: PasswordKeyboard.type,
        suffix: PasswordKeyboardToggle(focus: focus),
      ),
    );
  }

  Widget _errorText() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
    child: Text(
      _error!,
      style: const TextStyle(
        color: kAdminDanger,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    ),
  );

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
    child: Text(
      text,
      style: const TextStyle(color: kAdminMuted, fontSize: 12.5, height: 1.4),
    ),
  );

  /// Test modunda kod WhatsApp'tan, açıkken SMS ile gelir.
  String get _channel =>
      AppSettings.smsOtpTestMode.value ? "WhatsApp'tan" : 'SMS ile';

  List<Widget> _phoneStep() => [
    AdminFieldGroup(
      children: [
        AdminFieldRow(
          icon: Icons.phone_iphone_rounded,
          label: 'Cep Telefonu',
          child: _input(
            controller: _phone,
            hint: '(5XX) XXX XX XX',
            keyboardType: TextInputType.phone,
            prefixText: '0 ',
            formatters: [PhoneMaskFormatter()],
            autofill: const [AutofillHints.telephoneNumberNational],
            onSubmitted: _send,
          ),
        ),
      ],
    ),
    if (_error != null) _errorText(),
    _hint('Numaranıza $_channel 6 haneli bir doğrulama kodu göndereceğiz.'),
    const SizedBox(height: 12),
    AdminPrimaryButton(
      label: 'KOD GÖNDER',
      icon: Icons.sms_outlined,
      busy: _busy,
      onPressed: widget.enabled ? _send : null,
    ),
  ];

  List<Widget> _codeStep(String raw10) => [
    _hint(
      '0 ${formatPhoneRaw10(raw10)} numarasına $_channel doğrulama kodu '
      'gönderdik.',
    ),
    const SizedBox(height: 10),
    AdminFieldGroup(
      children: [
        AdminFieldRow(
          icon: Icons.pin_outlined,
          label: 'Doğrulama Kodu',
          child: _input(
            controller: _code,
            hint: '6 haneli kod',
            keyboardType: TextInputType.number,
            formatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            autofill: const [AutofillHints.oneTimeCode],
            onSubmitted: _check,
          ),
        ),
      ],
    ),
    if (_error != null) _errorText(),
    const SizedBox(height: 12),
    AdminPrimaryButton(
      label: 'DOĞRULA',
      icon: Icons.verified_user_outlined,
      busy: _busy,
      onPressed: _check,
    ),
    const SizedBox(height: 4),
    Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  _timer?.cancel();
                  setState(() => _error = null);
                  _c.restart();
                },
          child: const Text(
            'Numarayı değiştir',
            style: TextStyle(color: kAdminMuted, fontWeight: FontWeight.w700),
          ),
        ),
        TextButton(
          onPressed: _busy || _resendLeft > 0
              ? null
              : () => _send(phone: raw10),
          child: Text(
            _resendLeft > 0
                ? 'Tekrar gönder ($_resendLeft)'
                : 'Kodu tekrar gönder',
            style: TextStyle(
              color: _resendLeft > 0 ? kAdminMuted : kAdminAccent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  ];

  List<Widget> _passwordStep(String raw10) {
    final p1 = _pass1.text.trim();
    Widget rule(String text, bool ok) => Padding(
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
    void sync() {
      _c
        ..password = _pass1.text.trim()
        ..password2 = _pass2.text.trim();
      _c._changed();
    }

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: kAdminAccent, size: 18),
            const SizedBox(width: 8),
            Text(
              '0 ${formatPhoneRaw10(raw10)} doğrulandı',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
      AdminFieldGroup(
        children: [
          AdminFieldRow(
            icon: Icons.lock_outline_rounded,
            label: 'Şifre Belirle',
            child: _input(
              controller: _pass1,
              hint: '6-10 karakter',
              passwordFocus: _pass1Focus,
              autofill: const [AutofillHints.newPassword],
              onSubmitted: _pass2Focus.requestFocus,
              onChanged: (_) => sync(),
            ),
          ),
          AdminFieldRow(
            icon: Icons.lock_reset_rounded,
            label: 'Şifre (Tekrar)',
            child: _input(
              controller: _pass2,
              hint: 'Şifreyi tekrar yazın',
              passwordFocus: _pass2Focus,
              autofill: const [AutofillHints.newPassword],
              onSubmitted: () {},
              onChanged: (_) => sync(),
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: Column(
          children: [
            rule('6-10 karakter', PasswordRules.lengthOk(p1)),
            rule(
              'En az 1 rakam veya özel karakter',
              PasswordRules.hasDigitOrSpecial(p1),
            ),
            rule(
              'Kolay tahmin edilemez (123456, 111111 değil)',
              p1.isNotEmpty && !PasswordRules.isWeak(p1, phone: raw10),
            ),
            rule('İki şifre aynı', p1.isNotEmpty && p1 == _pass2.text.trim()),
          ],
        ),
      ),
    ];
  }
}
