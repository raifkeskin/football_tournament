import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/interfaces/i_auth_service.dart';
import '../../../core/services/service_locator.dart';
import '../services/sms/sms_service_locator.dart';
import '../../../core/utils/otp_utils.dart';
import 'reset_password_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final IAuthService _authService = ServiceLocator.authService;
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _busy = false;
  int _step = 0;
  String _raw10 = '';

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  String _normalizePhoneToRaw10(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    var d = digits;
    if (d.startsWith('90') && d.length >= 12) d = d.substring(2);
    if (d.startsWith('0')) d = d.substring(1);
    if (d.length > 10) d = d.substring(d.length - 10);
    return d;
  }

  Future<void> _sendOtp() async {
    final raw10 = _normalizePhoneToRaw10(_phoneController.text);
    if (raw10.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Telefon numarası geçerli olmalı.')),
      );
      return;
    }

    setState(() {
      _busy = true;
      _raw10 = raw10;
    });
    try {
      final otp = generateOtp6();
      final expiresAt = DateTime.now().add(const Duration(minutes: 3));
      await _authService.createOtpRequest(
        phoneRaw10: raw10,
        code: otp,
        expiresAt: expiresAt,
      );
      await SmsServiceLocator.sms.sendOtp(raw10, otp);
      if (!mounted) return;
      setState(() => _step = 1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Doğrulama kodu gönderilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.replaceAll(RegExp(r'\D'), '').trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen 6 haneli kodu girin.')),
      );
      return;
    }
    final raw10 = _raw10;
    if (raw10.length != 10) return;

    setState(() => _busy = true);
    try {
      final req = await _authService.getOtpRequest(raw10);
      if (req == null) {
        throw Exception('Doğrulama kodu bulunamadı.');
      }
      if (DateTime.now().isAfter(req.expiresAt)) {
        throw Exception('Doğrulama kodunun süresi doldu.');
      }
      if (req.code != code) {
        throw Exception('Doğrulama kodu hatalı.');
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ResetPasswordScreen(phoneRaw10: raw10, otp: code),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kod doğrulanamadı: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Şifremi Unuttum'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_step == 0) ...[
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [_PhoneMaskFormatter()],
              decoration: const InputDecoration(
                labelText: 'Telefon Numarası',
                prefixText: '0 ',
                prefixIcon: Icon(Icons.phone_outlined),
                hintText: '(5XX) XXX XX XX',
              ),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
              enabled: !_busy,
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: cs.primary),
                onPressed: _busy ? null : _sendOtp,
                child: const Text(
                  'Doğrulama Kodu Gönder',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ] else ...[
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Doğrulama Kodu',
                prefixIcon: Icon(Icons.password_outlined),
                hintText: '6 haneli kod',
              ),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
              enabled: !_busy,
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: cs.primary),
                onPressed: _busy ? null : _verifyOtp,
                child: const Text(
                  'Kodu Doğrula',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PhoneMaskFormatter extends TextInputFormatter {
  static String _formatFromRaw10(String raw10) {
    final clipped = raw10.length > 10 ? raw10.substring(0, 10) : raw10;
    final a = clipped.length >= 3 ? clipped.substring(0, 3) : clipped;
    final b = clipped.length > 3
        ? clipped.substring(3, clipped.length >= 6 ? 6 : clipped.length)
        : '';
    final c = clipped.length > 6
        ? clipped.substring(6, clipped.length >= 8 ? 8 : clipped.length)
        : '';
    final d = clipped.length > 8 ? clipped.substring(8) : '';
    final sb = StringBuffer();
    if (a.isNotEmpty) {
      sb.write('(');
      sb.write(a);
      if (a.length == 3) sb.write(') ');
    }
    if (b.isNotEmpty) {
      sb.write(b);
      if (b.length == 3) sb.write(' ');
    }
    if (c.isNotEmpty) {
      sb.write(c);
      if (c.length == 2) sb.write(' ');
    }
    if (d.isNotEmpty) sb.write(d);
    return sb.toString().trimRight();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('90')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length > 10) digits = digits.substring(digits.length - 10);
    final formatted = _formatFromRaw10(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
