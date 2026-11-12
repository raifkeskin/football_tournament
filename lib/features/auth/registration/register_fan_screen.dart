import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/app_settings.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../password_input.dart';
import '../widgets/phone_input.dart';
import 'fan_membership_terms.dart';
import 'fan_privacy_notice.dart';
import 'fan_registration_service.dart';
import 'registration_service.dart';

enum _FanRegistrationStep { details, code, password }

class RegisterFanScreen extends StatefulWidget {
  const RegisterFanScreen({super.key});

  @override
  State<RegisterFanScreen> createState() => _RegisterFanScreenState();
}

class _RegisterFanScreenState extends State<RegisterFanScreen> {
  static const _resendSeconds = 60;

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _passwordAgain = TextEditingController();
  final _passwordFocus = FocusNode();

  _FanRegistrationStep _step = _FanRegistrationStep.details;
  LocationOption? _province;
  LocationOption? _district;
  bool _termsAccepted = false;
  bool _busy = false;
  String? _error;
  String? _verifiedPhone;
  int _resendLeft = 0;
  Timer? _timer;

  String get _channel =>
      AppSettings.smsOtpTestMode.value ? 'test kodu WhatsApp ile' : 'SMS';

  @override
  void dispose() {
    _timer?.cancel();
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    _passwordAgain.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendLeft--);
      if (_resendLeft <= 0) timer.cancel();
    });
  }

  Future<void> _showDocument(String title, String text) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.86,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText(
                    text,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                      height: 1.55,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: AdminPrimaryButton(
                  label: 'KAPAT',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickLocation({required bool province}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final options = province
          ? await FanRegistrationService.provinces()
          : await FanRegistrationService.districts(_province!.id);
      if (!mounted) return;
      final selected = await showAdminOptionPicker<LocationOption>(
        context: context,
        title: province ? 'İl Seç' : 'İlçe Seç',
        items: options,
        selected: province ? _province : _district,
        labelBuilder: (option) => option.name,
        emptyText: province ? 'İl listesi bulunamadı.' : 'İlçe bulunamadı.',
      );
      if (!mounted || selected == null) return;
      setState(() {
        if (province) {
          _province = selected;
          _district = null;
        } else {
          _district = selected;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'İl/ilçe listesi yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    final phone = normalizePhoneToRaw10(_phone.text);
    if (first.length < 2 || last.length < 2) {
      setState(() => _error = 'Adınızı ve soyadınızı girin.');
      return;
    }
    if (phone.length != 10 || !phone.startsWith('5')) {
      setState(() => _error = 'Geçerli bir cep telefonu numarası girin.');
      return;
    }
    // İl/ilçe isteğe bağlı; il seçildiyse ilçe de seçilmeli.
    if (_province != null && _district == null) {
      setState(() => _error = 'İlçeyi de seçin ya da ili boş bırakın.');
      return;
    }
    if (!_termsAccepted) {
      setState(() => _error = 'Üyelik koşullarını kabul etmeniz gerekiyor.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FanRegistrationService.sendCode(
        phone: phone,
        fullName: '$first $last',
      );
      if (!mounted) return;
      if (result != 'sent') {
        setState(() => _error = FanRegistrationService.message(result));
        return;
      }
      setState(() {
        _verifiedPhone = phone;
        _code.clear();
        _step = _FanRegistrationStep.code;
      });
      _startResendTimer();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Kod gönderilemedi. Lütfen tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    final phone = _verifiedPhone;
    final code = _code.text.trim();
    if (phone == null || code.length != 6) {
      setState(() => _error = '6 haneli doğrulama kodunu girin.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FanRegistrationService.verifyCode(
        phone: phone,
        code: code,
      );
      if (!mounted) return;
      if (result != 'ok') {
        setState(() => _error = FanRegistrationService.message(result));
        return;
      }
      _timer?.cancel();
      setState(() => _step = _FanRegistrationStep.password);
      _passwordFocus.requestFocus();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Kod doğrulanamadı. Lütfen tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAccount() async {
    final phone = _verifiedPhone;
    final code = _code.text.trim();
    final password = _password.text;
    final passwordAgain = _passwordAgain.text;
    if (phone == null) {
      setState(() => _error = 'Kayıt bilgileri eksik. Lütfen tekrar başlayın.');
      return;
    }
    if (!PasswordRules.lengthOk(password) ||
        !PasswordRules.hasDigitOrSpecial(password) ||
        PasswordRules.isWeak(password, phone: phone)) {
      setState(() => _error = PasswordRules.weakMessage);
      return;
    }
    if (password != passwordAgain) {
      setState(() => _error = 'Şifreler eşleşmiyor.');
      return;
    }
    if (!_termsAccepted) {
      setState(() => _error = 'Üyelik koşullarını kabul etmeniz gerekiyor.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FanRegistrationService.register(
        phone: phone,
        code: code,
        password: password,
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        provinceId: _province?.id,
        districtId: _district?.id,
        termsAccepted: _termsAccepted,
      );
      if (!mounted) return;
      if (result != 'ok') {
        setState(() {
          _error = FanRegistrationService.message(result);
          if (result == 'expired' ||
              result == 'wrong_code' ||
              result == 'too_many_attempts') {
            _step = _FanRegistrationStep.code;
          }
        });
        return;
      }
      await RegistrationService.signInAndOpenHome(
        context,
        raw10: phone,
        password: password,
        message: 'Taraftar hesabınız oluşturuldu.',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Hesap oluşturulamadı. Lütfen tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _textField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    bool obscure = false,
    FocusNode? focus,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        focusNode: focus,
        enabled: !_busy,
        keyboardType: keyboardType,
        inputFormatters: formatters,
        obscureText: obscure,
        textCapitalization: keyboardType == TextInputType.phone
            ? TextCapitalization.none
            : TextCapitalization.words,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          prefixText: keyboardType == TextInputType.phone ? '0 ' : null,
          prefixStyle: const TextStyle(
            color: Colors.white70,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: const Color(0xFF1E293B),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2563EB)),
          ),
        ),
      ),
    );
  }

  Widget _locationButton({
    required String label,
    required String? value,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF94A3B8), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        value ?? 'Seçin',
                        style: TextStyle(
                          color: value == null ? Colors.white54 : Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.expand_more, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _termsCheckbox() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Checkbox(
        value: _termsAccepted,
        activeColor: const Color(0xFF2563EB),
        onChanged: _busy
            ? null
            : (value) => setState(() => _termsAccepted = value ?? false),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(
            children: [
              const Text(
                'Üyelik ve Kullanım Koşulları’nı kabul ediyorum. ',
                style: TextStyle(color: Colors.white70, height: 1.45),
              ),
              InkWell(
                onTap: () => _showDocument(
                  'Üyelik ve Kullanım Koşulları',
                  fanMembershipTerms,
                ),
                child: const Text(
                  'Metni görüntüle',
                  style: TextStyle(
                    color: Color(0xFF60A5FA),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const Text('  '),
              InkWell(
                onTap: () => _showDocument(
                  'Kişisel Verilerin İşlenmesi Hakkında',
                  fanPrivacyNotice,
                ),
                child: const Text(
                  'Aydınlatma Metni',
                  style: TextStyle(
                    color: Color(0xFF60A5FA),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _detailsStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Taraftar hesabı oluştur',
        style: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 6),
      const Text(
        'Ücretsiz hesabınla turnuva haberlerini, videoları, fikstürü ve puan durumunu takip et.',
        style: TextStyle(color: kAdminMuted, fontSize: 14, height: 1.4),
      ),
      const SizedBox(height: 18),
      _textField(label: 'Ad', controller: _firstName),
      _textField(label: 'Soyad', controller: _lastName),
      _locationButton(
        label: 'İl (isteğe bağlı)',
        value: _province?.name,
        icon: Icons.location_city_outlined,
        onTap: () => _pickLocation(province: true),
      ),
      _locationButton(
        label: 'İlçe (isteğe bağlı)',
        value: _district?.name,
        icon: Icons.place_outlined,
        onTap: _province == null
            ? () => setState(() => _error = 'Önce il seçin.')
            : () => _pickLocation(province: false),
      ),
      _textField(
        label: 'Cep Telefonu',
        controller: _phone,
        keyboardType: TextInputType.phone,
        formatters: [PhoneMaskFormatter()],
      ),
      Text(
        'Doğrulama kodu $_channel gönderilecektir.',
        style: const TextStyle(color: kAdminMuted, fontSize: 12.5),
      ),
      const SizedBox(height: 6),
      _termsCheckbox(),
      if (_error != null) _errorText(),
      const SizedBox(height: 12),
      AdminPrimaryButton(
        label: 'DOĞRULAMA KODU GÖNDER',
        icon: Icons.sms_outlined,
        busy: _busy,
        onPressed: _busy ? null : _sendCode,
      ),
    ],
  );

  Widget _codeStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Telefonunu doğrula',
        style: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '${formatPhoneRaw10(_verifiedPhone ?? '')} numarasına $_channel gönderildi.',
        style: const TextStyle(color: kAdminMuted, height: 1.4),
      ),
      const SizedBox(height: 18),
      _textField(
        label: '6 haneli doğrulama kodu',
        controller: _code,
        keyboardType: TextInputType.number,
        formatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
      ),
      if (_error != null) _errorText(),
      AdminPrimaryButton(
        label: 'KODU DOĞRULA',
        icon: Icons.verified_user_outlined,
        busy: _busy,
        onPressed: _busy ? null : _verifyCode,
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _step = _FanRegistrationStep.details;
                    _error = null;
                  }),
            child: const Text('Bilgileri düzenle'),
          ),
          TextButton(
            onPressed: _busy || _resendLeft > 0 ? null : _sendCode,
            child: Text(
              _resendLeft > 0
                  ? 'Tekrar gönder ($_resendLeft)'
                  : 'Kodu tekrar gönder',
            ),
          ),
        ],
      ),
    ],
  );

  Widget _passwordStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Şifreni belirle',
        style: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        '${formatPhoneRaw10(_verifiedPhone ?? '')} doğrulandı. Bu numara ve şifreyle giriş yapacaksın.',
        style: const TextStyle(color: kAdminMuted, height: 1.4),
      ),
      const SizedBox(height: 18),
      _textField(
        label: 'Şifre (6-10 karakter)',
        controller: _password,
        obscure: true,
        focus: _passwordFocus,
      ),
      _textField(
        label: 'Şifreyi tekrar gir',
        controller: _passwordAgain,
        obscure: true,
      ),
      const Text(
        'Şifrede en az bir rakam veya özel karakter bulunmalı.',
        style: TextStyle(color: kAdminMuted, fontSize: 12.5),
      ),
      if (_error != null) _errorText(),
      const SizedBox(height: 12),
      AdminPrimaryButton(
        label: 'TARAFTAR HESABIMI OLUŞTUR',
        icon: Icons.person_add_alt_1_rounded,
        busy: _busy,
        onPressed: _busy ? null : _createAccount,
      ),
    ],
  );

  Widget _errorText() => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(
      _error!,
      textAlign: TextAlign.center,
      style: const TextStyle(color: kAdminDanger, fontWeight: FontWeight.w700),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final stepContent = switch (_step) {
      _FanRegistrationStep.details => _detailsStep(),
      _FanRegistrationStep.code => _codeStep(),
      _FanRegistrationStep.password => _passwordStep(),
    };
    return AdminPageScaffold(
      title: 'Taraftar Kaydı',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: i <= _step.index
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          stepContent,
        ],
      ),
    );
  }
}
