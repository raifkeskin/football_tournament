import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/app_session.dart';
import 'forgot_password_screen.dart';
import '../../home/screens/main_navigator.dart';
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
  int _adminTapCount = 0;
  Timer? _adminTapTimer;

  @override
  void dispose() {
    _adminTapTimer?.cancel();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<String?> _showBackdoorPasswordDialog() async {
    var password = '';
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Sistem Girişi',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Kullanıcı: masterclass',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.white70,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              obscureText: true,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Şifre',
                labelStyle: const TextStyle(color: Colors.white54),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.white24),
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFF10B981)),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => password = v,
              onSubmitted: (_) => Navigator.pop(context, password),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Vazgeç',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
            ),
            onPressed: () => Navigator.pop(context, password),
            child: const Text(
              'Giriş',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    final pwd = (result ?? '').trim();
    return pwd.isEmpty ? null : pwd;
  }

  Future<void> _handleAdminTitleTap(AppSessionController session) async {
    _adminTapTimer?.cancel();
    _adminTapCount += 1;
    _adminTapTimer = Timer(const Duration(seconds: 1), () {
      _adminTapCount = 0;
    });

    if (_adminTapCount != 3) return;
    _adminTapTimer?.cancel();
    _adminTapCount = 0;

    final pwd = await _showBackdoorPasswordDialog();
    if (!mounted || pwd == null) return;

    setState(() => _loading = true);
    try {
      final ok = await session.signInSuperAdminBackdoor(password: pwd);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Şifre hatalı.')));
        return;
      }
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const MainNavigator(
            initialTabIndex: 4,
          ), // Direkt Profil sekmesine yönlendiriyoruz
        ),
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Giriş başarısız: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final session = AppSession.of(context);
    const bgDark = Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: bgDark,
      extendBodyBehindAppBar:
          true, // Arka planın AppBar'ın altına yayılması için
      appBar: AppBar(
        backgroundColor: Colors.transparent, // Ortak şeffaf AppBar
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: GestureDetector(
          onTap: () => _handleAdminTitleTap(
            session,
          ), // Gizli admin girişi başlığa taşındı
          child: const Text(
            'Giriş Yap',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
        ),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(
              Icons.menu, // 3 çizgi (Hamburger) ikonumuz
              color: Colors.white,
              size: 28,
            ),
            onPressed: () {
              // YENİ YÖNTEM: En üstteki root Scaffold'u bulup Drawer'ı açmaya zorlar
              final scaffoldState = ctx
                  .findRootAncestorStateOfType<ScaffoldState>();

              if (scaffoldState != null && scaffoldState.hasDrawer) {
                scaffoldState.openDrawer();
              } else {
                // Eğer Drawer bulunamazsa (veya farklı bir root yapısı varsa) kullanıcıyı Ana Sayfa sekmesine döndür
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
          ),
        ),
      ),
      body: Stack(
        children: [
          // Fikstür/Gruplar/İstatistik ekranlarındaki ortak top görselli arka plan
          Positioned.fill(
            child: Opacity(
              opacity: 0.15,
              child: Image.asset(
                'assets/images/background_ball.jpg',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
          ),
          SafeArea(
            child: Center(
              // İçeriği ortalamak daha şık durur
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFF1E293B,
                    ).withOpacity(0.85), // Camımsı şık kart efekti
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 15,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Başlık İkonu (Opsiyonel, şıklık katar)
                      const Icon(
                        Icons.account_circle_rounded,
                        size: 64,
                        color: Color(0xFF10B981),
                      ),
                      const SizedBox(height: 24),

                      TextField(
                        controller: _phoneController,
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [_PhoneMaskFormatter()],
                        decoration: InputDecoration(
                          labelText: 'Telefon Numarası',
                          labelStyle: const TextStyle(color: Colors.white70),
                          prefixText: '0 ',
                          prefixIcon: const Icon(
                            Icons.phone_outlined,
                            color: Colors.white70,
                          ),
                          hintText: '(5XX) XXX XX XX',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.2),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.15),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                        enabled: !_loading,
                      ),
                      const SizedBox(height: 16),

                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        onSubmitted: _loading ? null : (_) => _login(session),
                        decoration: InputDecoration(
                          labelText: 'Şifre',
                          labelStyle: const TextStyle(color: Colors.white70),
                          prefixIcon: const Icon(
                            Icons.lock_outline,
                            color: Colors.white70,
                          ),
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.2),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.15),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                        enabled: !_loading,
                      ),
                      const SizedBox(height: 16),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: _rememberMe,
                                  activeColor: const Color(0xFF10B981),
                                  side: BorderSide(
                                    color: Colors.white.withOpacity(0.5),
                                  ),
                                  onChanged: _loading
                                      ? null
                                      : (v) => setState(
                                          () => _rememberMe = v ?? false,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Beni Hatırla',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
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
                                        builder: (_) =>
                                            const ForgotPasswordScreen(),
                                      ),
                                    );
                                  },
                            child: const Text(
                              'Şifremi Unuttum',
                              style: TextStyle(
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      SizedBox(
                        height: 54,
                        child: _loading
                            ? const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              )
                            : ElevatedButton(
                                onPressed: () => _login(session),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(
                                    0xFF064E3B,
                                  ), // Masterclass koyu yeşili
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'GİRİŞ YAP',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 16),

                      Center(
                        child: TextButton(
                          onPressed: _loading
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const OnlineRegistrationScreen(),
                                    ),
                                  );
                                },
                          child: const Text(
                            'Kayıt Hesabım Yok (Online Form)',
                            style: TextStyle(
                              color: Color(
                                0xFFF59E0B,
                              ), // Dikkat çekici turuncu/sarı ton
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
