import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_session.dart';
import 'forgot_password_screen.dart';
import 'main_navigator.dart';
import 'online_registration_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _loading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login(AppSessionController session) async {
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;
    if (phone.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen telefon ve şifre girin.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await session.signInWithPhonePassword(
        phoneInput: phone,
        password: password,
        rememberMe: _rememberMe,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const MainNavigator(initialTabIndex: 4),
        ),
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Giriş başarısız: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final session = AppSession.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Giriş Yap'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          TextField(
            controller: _phoneController,
            textInputAction: TextInputAction.next,
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
            enabled: !_loading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            onSubmitted: _loading ? null : (_) => _login(session),
            decoration: const InputDecoration(
              labelText: 'Şifre',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
            enabled: !_loading,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: _rememberMe,
                    onChanged: _loading
                        ? null
                        : (v) => setState(() => _rememberMe = v ?? false),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Beni Hatırla',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: _loading
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ForgotPasswordScreen(),
                          ),
                        );
                      },
                child: Text(
                  'Şifremi Unuttum',
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : FilledButton(
                    onPressed: () => _login(session),
                    child: const Text(
                      'Giriş Yap',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _loading
                  ? null
                  : () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const OnlineRegistrationScreen(),
                        ),
                      );
                    },
              child: Text(
                'Online Kayıt Formu',
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
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

