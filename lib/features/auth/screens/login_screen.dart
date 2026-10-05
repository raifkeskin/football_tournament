import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../../core/services/active_tournament.dart';
import '../../../core/services/app_session.dart';
import '../../../core/widgets/app_name_band.dart';
import 'forgot_password_screen.dart';
import '../../home/screens/main_navigator.dart';
import 'online_registration_screen.dart';
import 'reset_password_screen.dart';
import '../widgets/phone_input.dart';
import '../../../core/widgets/admin_form.dart';

/// Açılışta "Misafir olarak devam et" seçildi mi (cihazda saklanır).
class GuestMode {
  GuestMode._();

  static const _key = 'guest_mode_chosen';
  static bool chosen = false;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      chosen = prefs.getBool(_key) ?? false;
    } catch (_) {}
  }

  static Future<void> set(bool value) async {
    chosen = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {}
    // Misafir: son baktığı turnuvanın kimliği; kapıya dönüş: tema temizlenir.
    await ActiveTournament.refresh();
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.gate = false});

  /// Uygulama açılışındaki giriş kapısı: menü yok, girişten sonra ana
  /// sayfa, altta "Misafir olarak devam et".
  final bool gate;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = true;
  bool _loading = false;
  int _adminTapCount = 0;
  Timer? _adminTapTimer;

  /// Bu giriş formu bandı genel görünüme aldı mı. Yalnız form görünürken
  /// sayılır: Profil sekmesine gömülü form, sekme arkadayken (TickerMode
  /// kapalı) bandı etkilemez.
  bool _bandGeneric = false;

  void _syncBand(bool visible) {
    if (visible == _bandGeneric) return;
    _bandGeneric = visible;
    // (Kurulum/kaldırma sırasında bant yeniden çizilemez; ertelenir.)
    Future.microtask(
      () => AppNameBand.genericScreens.value += visible ? 1 : -1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBand(TickerMode.of(context));
  }

  @override
  void dispose() {
    _syncBand(false);
    _adminTapTimer?.cancel();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<String?> _showBackdoorPasswordDialog() async {
    final result = await showAdminTextInputDialog(
      context: context,
      title: 'Sistem Girişi',
      icon: Icons.admin_panel_settings_outlined,
      subtitle: 'Kullanıcı: masterclass',
      label: 'Şifre',
      fieldIcon: Icons.lock_outline_rounded,
      obscureText: true,
      confirmLabel: 'GİRİŞ',
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
            initialTabIndex: MainNavigator.profileTab,
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

  /// Supabase giriş hatasını kullanıcının anlayacağı bir mesaja çevirir.
  static String _loginErrorMessage(Object e) {
    if (e is AuthException) {
      final code = e.code ?? '';
      final msg = e.message.toLowerCase();
      if (code == 'invalid_credentials' || msg.contains('invalid login')) {
        return 'Telefon numarası veya şifre hatalı. Lütfen kontrol edip '
            'tekrar deneyin. Şifrenizi hatırlamıyorsanız "Şifremi '
            'Unuttum"a dokunun.';
      }
      if (code == 'phone_provider_disabled' || msg.contains('phone')) {
        return 'Lütfen geçerli bir cep telefonu numarası girin '
            '(5XX XXX XX XX).';
      }
      if (code == 'over_request_rate_limit' ||
          e.statusCode == '429' ||
          msg.contains('rate limit')) {
        return 'Çok fazla deneme yaptınız. Lütfen birkaç dakika sonra '
            'tekrar deneyin.';
      }
      if (code == 'user_banned') {
        return 'Hesabınız kullanıma kapatılmış. Lütfen bizimle iletişime '
            'geçin.';
      }
    }
    final text = e.toString().toLowerCase();
    if (text.contains('socket') ||
        text.contains('network') ||
        text.contains('clientexception') ||
        text.contains('failed host lookup')) {
      return 'İnternet bağlantısı kurulamadı. Bağlantınızı kontrol edip '
          'tekrar deneyin.';
    }
    if (e is ArgumentError) {
      return 'Lütfen telefon numaranızı girin.';
    }
    return 'Giriş yapılamadı. Lütfen bilgilerinizi kontrol edip tekrar '
        'deneyin.';
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
      if (session.mustChangePassword) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ResetPasswordScreen(rememberMe: _rememberMe),
          ),
        );
        return;
      }
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          // Girişten sonra her zaman ana sayfa (kişinin turnuvasıyla).
          builder: (_) => const MainNavigator(initialTabIndex: 0),
        ),
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      await showAdminInfoDialog(
        context: context,
        title: 'Giriş yapılamadı',
        message: _loginErrorMessage(e),
      );
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
        automaticallyImplyLeading: false,
        leading: widget.gate
            ? null
            : Builder(
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
                    ).withValues(alpha: 0.85), // Camımsı şık kart efekti
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
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
                        inputFormatters: [PhoneMaskFormatter()],
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
                          fillColor: Colors.black.withValues(alpha: 0.2),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.15),
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
                          fillColor: Colors.black.withValues(alpha: 0.2),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.15),
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
                                    color: Colors.white.withValues(alpha: 0.5),
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
                                  color: Colors.white.withValues(alpha: 0.8),
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
                            'Kayıt Ol',
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
                      // Açılış kapısı: hesabı olmayanlar uygulamayı misafir
                      // olarak gezer (tüm turnuvalar); menüden her zaman
                      // giriş yapılabilir.
                      if (widget.gate) ...[
                        const SizedBox(height: 4),
                        Divider(color: Colors.white.withValues(alpha: 0.12)),
                        const SizedBox(height: 4),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _loading
                              ? null
                              : () async {
                                  await GuestMode.set(true);
                                  if (!context.mounted) return;
                                  Navigator.of(
                                    context,
                                    rootNavigator: true,
                                  ).pushAndRemoveUntil(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const MainNavigator(),
                                    ),
                                    (Route<dynamic> route) => false,
                                  );
                                },
                          icon: const Icon(Icons.travel_explore_rounded),
                          label: const Text(
                            'Misafir olarak devam et',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
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
