import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/services/active_tournament.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../home/screens/main_navigator.dart';
import '../models/auth_models.dart';
import '../widgets/phone_input.dart';

/// SMS doğrulama açıkken Kayıt Ol / Şifremi Unuttum: telefona gelen 6 haneli
/// kodla kişi kendi şifresini belirler ve doğrudan giriş yapar (admin onayı
/// yok). Sunucu SMS doğrulamanın kapandığını bildirirse ayar kapatılır ve
/// ekran eski talep akışına döner.
class SmsOtpForm extends StatefulWidget {
  const SmsOtpForm({super.key, required this.isReset, this.onNotRegistered});

  final bool isReset;

  /// Şifremi Unuttum'da hesabı olmayan numara için "Kayıt Ol"a geçiş.
  final VoidCallback? onNotRegistered;

  @override
  State<SmsOtpForm> createState() => _SmsOtpFormState();
}

class _SmsOtpFormState extends State<SmsOtpForm> {
  static const _resendSeconds = 60;

  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _pass1Controller = TextEditingController();
  final _pass2Controller = TextEditingController();

  bool _busy = false;
  String? _error;
  bool _showRegisterLink = false;

  /// Kod gönderildiyse numara (ikinci adım).
  String? _sentTo;
  int _resendLeft = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    _pass1Controller.dispose();
    _pass2Controller.dispose();
    super.dispose();
  }

  static bool _lengthOk(String v) => v.length >= 6 && v.length <= 10;
  static bool _hasDigitOrSpecial(String v) => RegExp(r'[^A-Za-z]').hasMatch(v);

  void _startResendTimer() {
    _timer?.cancel();
    _resendLeft = _resendSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendLeft--);
      if (_resendLeft <= 0) t.cancel();
    });
  }

  String _unknownPhoneText() => AppSettings.privateLeaguesEnabled.value
      ? 'Bu numara sistemde kayıtlı değil. Bir turnuvayı takip etmek için '
            'hesap gerekmez; turnuva sorumlusundan kodu alıp menüdeki '
            '"Turnuva Kodu Gir"e yazabilirsiniz. Futbolcuysanız takım '
            'sorumlunuza, turnuva yöneticisiyseniz bize ulaşın.'
      : 'Bu numara sistemde kayıtlı değil. Turnuvaları takip etmek için '
            'hesap gerekmez. Futbolcuysanız takım sorumlunuza, turnuva '
            'yöneticisiyseniz bize ulaşın.';

  Future<void> _send({String? phone}) async {
    final raw10 = phone ?? normalizePhoneToRaw10(_phoneController.text);
    if (raw10.length != 10 || !raw10.startsWith('5')) {
      setState(() => _error = 'Geçerli bir cep telefonu numarası girin.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _showRegisterLink = false;
    });
    try {
      final outcome = await ServiceLocator.authService.sendSmsOtp(
        phoneRaw10: raw10,
        isReset: widget.isReset,
      );
      if (!mounted) return;
      setState(() {
        switch (outcome) {
          case SmsOtpSendOutcome.sent:
          case SmsOtpSendOutcome.sentReset:
            _sentTo = raw10;
            _codeController.clear();
            _startResendTimer();
          case SmsOtpSendOutcome.tooSoon:
            _error = 'Yeni kod için biraz bekleyin.';
          case SmsOtpSendOutcome.tooMany:
            _error =
                'Bu numaraya çok fazla kod istendi. Lütfen bir saat sonra '
                'tekrar deneyin.';
          case SmsOtpSendOutcome.notRegistered:
            _error =
                'Bu numarayla kayıtlı hesap bulunamadı. Önce kayıt olmanız '
                'gerekiyor.';
            _showRegisterLink = widget.onNotRegistered != null;
          case SmsOtpSendOutcome.unknownPhone:
            _error = _unknownPhoneText();
          case SmsOtpSendOutcome.notConfigured:
            _error =
                'SMS gönderimi şu an yapılamıyor. Lütfen daha sonra tekrar '
                'deneyin.';
          case SmsOtpSendOutcome.disabled:
            // Ayar kapatılmış: üst form eski talep akışına döner.
            AppSettings.smsOtpEnabled.value = false;
          case SmsOtpSendOutcome.invalidPhone:
            _error = 'Geçerli bir cep telefonu numarası girin.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Kod gönderilemedi. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final raw10 = _sentTo!;
    final code = _codeController.text.trim();
    final p1 = _pass1Controller.text.trim();
    final p2 = _pass2Controller.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'SMS ile gelen 6 haneli kodu girin.');
      return;
    }
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
    final rootNav = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final outcome = await ServiceLocator.authService.verifySmsOtp(
        phoneRaw10: raw10,
        code: code,
        password: p1,
      );
      if (!mounted) return;
      switch (outcome) {
        case SmsOtpVerifyOutcome.ok:
          break;
        case SmsOtpVerifyOutcome.wrongCode:
          setState(() => _error = 'Kod hatalı. Lütfen kontrol edin.');
          return;
        case SmsOtpVerifyOutcome.expired:
          setState(
            () => _error =
                'Kodun süresi doldu. "Kodu tekrar gönder" ile yeni kod '
                'isteyin.',
          );
          return;
        case SmsOtpVerifyOutcome.tooManyAttempts:
          setState(
            () => _error =
                'Çok fazla hatalı deneme. "Kodu tekrar gönder" ile yeni kod '
                'isteyin.',
          );
          return;
        case SmsOtpVerifyOutcome.weakPassword:
          setState(
            () => _error =
                'Şifre 6-10 karakter olmalı ve en az bir rakam veya özel '
                'karakter içermeli.',
          );
          return;
        case SmsOtpVerifyOutcome.disabled:
          AppSettings.smsOtpEnabled.value = false;
          return;
        case SmsOtpVerifyOutcome.invalidPhone:
          setState(() => _error = 'Geçerli bir cep telefonu numarası girin.');
          return;
      }

      // Şifre belirlendi: doğrudan giriş (giriş ekranındaki gibi ana sayfa
      // kişinin turnuvası ve rolüyle tek seferde açılır).
      await session.signInWithPhonePassword(
        phoneInput: raw10,
        password: p1,
        rememberMe: true,
      );
      final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
      await Future.wait([
        ActiveTournament.refresh(),
        if (uid.isNotEmpty) session.waitForProfile(uid),
      ]);
      rootNav.pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const MainNavigator(initialTabIndex: 0),
        ),
        (Route<dynamic> route) => false,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.isReset ? 'Şifreniz yenilendi.' : 'Hesabınız oluşturuldu.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'İşlem tamamlanamadı. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required VoidCallback onSubmitted,
    TextInputType? keyboardType,
    String? prefixText,
    List<TextInputFormatter>? inputFormatters,
    Iterable<String>? autofillHints,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      enabled: !_busy,
      keyboardType: keyboardType,
      obscureText: obscure,
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => onSubmitted(),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      decoration: adminInlineInputDecoration(
        hint: hint,
        prefixText: prefixText,
      ),
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

  Widget _intro(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _errorView() {
    return Column(
      children: [
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: kAdminDanger,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (_showRegisterLink) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: widget.onNotRegistered,
            child: const Text(
              'Kayıt Ol',
              style: TextStyle(color: kAdminAmber, fontWeight: FontWeight.w800),
            ),
          ),
        ],
        const SizedBox(height: 14),
      ],
    );
  }

  List<Widget> _phoneStep() {
    return [
      _intro(
        widget.isReset
            ? 'Kayıtlı telefon numaranızı yazın. Numaranıza SMS ile bir '
                  'doğrulama kodu göndereceğiz.'
            : 'Telefon numaranızı yazın. Numaranıza SMS ile bir doğrulama '
                  'kodu göndereceğiz.',
      ),
      AdminFormSection(
        title: widget.isReset ? 'Hesap' : 'Bilgileriniz',
        child: AdminFieldGroup(
          children: [
            AdminFieldRow(
              icon: Icons.phone_iphone_rounded,
              label: 'Cep Telefonu',
              child: _field(
                controller: _phoneController,
                hint: '(5XX) XXX XX XX',
                keyboardType: TextInputType.phone,
                prefixText: '0 ',
                inputFormatters: [PhoneMaskFormatter()],
                autofillHints: const [AutofillHints.telephoneNumberNational],
                onSubmitted: _send,
              ),
            ),
          ],
        ),
      ),
      if (_error != null) _errorView(),
      AdminPrimaryButton(
        label: 'KOD GÖNDER',
        icon: Icons.sms_outlined,
        busy: _busy,
        onPressed: _send,
      ),
    ];
  }

  List<Widget> _codeStep() {
    final p1 = _pass1Controller.text.trim();
    return [
      _intro(
        '0 ${formatPhoneRaw10(_sentTo!)} numarasına gönderilen 6 haneli '
        'kodu girin ve ${widget.isReset ? 'yeni ' : ''}şifrenizi belirleyin.',
      ),
      AdminFormSection(
        title: 'Doğrulama',
        child: AdminFieldGroup(
          children: [
            AdminFieldRow(
              icon: Icons.pin_outlined,
              label: 'SMS Kodu',
              child: _field(
                controller: _codeController,
                hint: '6 haneli kod',
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                autofillHints: const [AutofillHints.oneTimeCode],
                onSubmitted: _verify,
              ),
            ),
          ],
        ),
      ),
      AdminFormSection(
        title: widget.isReset ? 'Yeni Şifre' : 'Şifre',
        child: AdminFieldGroup(
          children: [
            AdminFieldRow(
              icon: Icons.lock_outline_rounded,
              label: 'Şifre',
              child: _field(
                controller: _pass1Controller,
                hint: '6-10 karakter',
                obscure: true,
                autofillHints: const [AutofillHints.newPassword],
                onSubmitted: _verify,
              ),
            ),
            AdminFieldRow(
              icon: Icons.lock_reset_rounded,
              label: 'Şifre (Tekrar)',
              child: _field(
                controller: _pass2Controller,
                hint: 'Şifreyi tekrar yazın',
                obscure: true,
                autofillHints: const [AutofillHints.newPassword],
                onSubmitted: _verify,
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
        child: Column(
          children: [
            _rule('6-10 karakter', _lengthOk(p1)),
            _rule('En az 1 rakam veya özel karakter', _hasDigitOrSpecial(p1)),
          ],
        ),
      ),
      if (_error != null) _errorView(),
      AdminPrimaryButton(
        label: 'ŞİFREYİ KAYDET VE GİRİŞ YAP',
        icon: Icons.check_rounded,
        busy: _busy,
        onPressed: _verify,
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _timer?.cancel();
                    _sentTo = null;
                    _error = null;
                  }),
            child: const Text(
              'Numarayı değiştir',
              style: TextStyle(color: kAdminMuted, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: _busy || _resendLeft > 0
                ? null
                : () => _send(phone: _sentTo),
            child: Text(
              _resendLeft > 0
                  ? 'Kodu tekrar gönder ($_resendLeft)'
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
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: _sentTo == null ? _phoneStep() : _codeStep(),
      ),
    );
  }
}
