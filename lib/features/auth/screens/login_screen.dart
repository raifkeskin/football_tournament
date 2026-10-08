import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, Supabase;

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

  /// Giriş yapıldı, ana sayfaya yönlendirme bekleniyor: profil sekmesi bu
  /// arada paneli/profili göstermez (bir an görünüp kaybolmasın).
  static final redirecting = ValueNotifier<bool>(false);

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
    // Profil sekmesindeki giriş formu, oturum açılınca ekrandan kalkar;
    // yönlendirme yine de yapılsın diye gezginler önceden alınır.
    final nav = Navigator.of(context);
    final rootNav = Navigator.of(context, rootNavigator: true);
    final rememberMe = _rememberMe;
    final staff = _staff;
    LoginScreen.redirecting.value = true;
    try {
      await session.signInWithPhonePassword(
        phoneInput: phone,
        password: password,
        rememberMe: rememberMe,
      );
      if (session.mustChangePassword) {
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => ResetPasswordScreen(rememberMe: rememberMe),
          ),
        );
        return;
      }
      // Ana sayfa kişinin turnuvası ve rolüyle tek seferde açılsın (bant ve
      // içerik arada değişmesin).
      final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
      await Future.wait([
        ActiveTournament.refresh(),
        if (uid.isNotEmpty) session.waitForProfile(uid),
      ]);
      // Girişten sonra ana sayfa (kişinin turnuvasıyla); Kulübe seçip
      // yönetim yetkisi olan doğrudan yönetim sayfasına (Profil) düşer.
      final toPanel = staff && session.value.hasManagementPanel;
      rootNav.pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => MainNavigator(
            initialTabIndex: toPanel ? MainNavigator.profileTab : 0,
          ),
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
      LoginScreen.redirecting.value = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Saha (futbolcu) mı Kulübe (sorumlu) mi seçili. Giriş yöntemi aynı;
  /// yalnız metinler ve girişten sonra açılan ilk sayfa değişir.
  bool _staff = false;

  static const _green = Color(0xFF10B981);

  Future<void> _continueAsGuest() async {
    await GuestMode.set(true);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const MainNavigator()),
      (Route<dynamic> route) => false,
    );
  }

  void _openRegistration() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const OnlineRegistrationScreen()),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? prefixText,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixText: prefixText,
      prefixIcon: Icon(icon, color: Colors.white70),
      hintText: hintText,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: const Color(0xFF1E293B),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _green),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context);
    const bgDark = Color(0xFF0F172A);
    const fieldText = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w800,
    );

    return Scaffold(
      backgroundColor: bgDark,
      // Başlık yok (üstte uygulama bandı var); kapı dışında yalnız menü.
      appBar: widget.gate
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 44,
              automaticallyImplyLeading: false,
              leading: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                  onPressed: () {
                    // En üstteki root Scaffold'un menüsü; yoksa ana sekme.
                    final scaffoldState = ctx
                        .findRootAncestorStateOfType<ScaffoldState>();
                    if (scaffoldState != null && scaffoldState.hasDrawer) {
                      scaffoldState.openDrawer();
                    } else {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    }
                  },
                ),
              ),
            ),
      body: SafeArea(
        top: !widget.gate,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Gizli admin girişi: soruya üç kez dokunmak.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _handleAdminTitleTap(session),
                    child: const Text(
                      'Bugün nerede olacaksın?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _RoleTile(
                            title: 'Saha',
                            subtitle: 'Futbolcuyum',
                            icon: Icons.sports_soccer_rounded,
                            colors: const [Color(0xFF22C55E), Color(0xFF0F6B35)],
                            selected: !_staff,
                            onTap: _loading
                                ? null
                                : () => setState(() => _staff = false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _RoleTile(
                            title: 'Kulübe',
                            subtitle: 'Takım / turnuva sorumlusuyum',
                            icon: Icons.assignment_ind_rounded,
                            colors: const [Color(0xFFF59E0B), Color(0xFF9A5B06)],
                            selected: _staff,
                            onTap: _loading
                                ? null
                                : () => setState(() => _staff = true),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _WideTile(
                    title: 'Tribün',
                    subtitle: 'Girişe gerek olmadan, tüm turnuvaları takip et',
                    icon: Icons.stadium_rounded,
                    colors: const [Color(0xFF1E3A8A), Color(0xFF172554)],
                    onTap: _loading ? null : _continueAsGuest,
                  ),
                  const SizedBox(height: 10),
                  _WideTile(
                    title: 'Kayıt Ol',
                    subtitle: 'Hesabın yok mu? Telefonunla hesap aç',
                    icon: Icons.person_add_alt_1_rounded,
                    colors: const [Color(0xFF475569), Color(0xFF1E293B)],
                    onTap: _loading ? null : _openRegistration,
                  ),
                  const SizedBox(height: 22),
                  Text(
                    _staff
                        ? 'Takım, bölge veya turnuva yönettiğin hesabınla gir; '
                              'yönetim sayfan açılır.'
                        : 'Takımına kayıtlı telefon numaranla gir; maçların ve '
                              'istatistiklerin seni bekliyor.',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13.5,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneController,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [PhoneMaskFormatter()],
                    decoration: _fieldDecoration(
                      label: 'Telefon Numarası',
                      icon: Icons.phone_outlined,
                      prefixText: '0 ',
                      hintText: '(5XX) XXX XX XX',
                    ),
                    style: fieldText,
                    enabled: !_loading,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    onSubmitted: _loading ? null : (_) => _login(session),
                    decoration: _fieldDecoration(
                      label: 'Şifre',
                      icon: Icons.lock_outline,
                    ),
                    style: fieldText,
                    enabled: !_loading,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: Checkbox(
                          value: _rememberMe,
                          activeColor: _green,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                          onChanged: _loading
                              ? null
                              : (v) => setState(() => _rememberMe = v ?? false),
                        ),
                      ),
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
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 54,
                    child: _loading
                        ? const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: _green,
                              ),
                            ),
                          )
                        : ElevatedButton(
                            onPressed: () => _login(session),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF16A34A),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              _staff ? 'KULÜBEYE GEÇ' : 'SAHAYA ÇIK',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton(
                      onPressed: _loading
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const ForgotPasswordScreen(),
                              ),
                            ),
                      child: const Text(
                        'Şifremi Unuttum',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                          decorationColor: Color(0xFF94A3B8),
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
    );
  }
}

/// Saha / Kulübe kutusu: seçilince beyaz çerçeve.
class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _TileFrame(
      colors: colors,
      selected: selected,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 112),
        child: Stack(
          children: [
            Positioned(
              right: -10,
              top: -10,
              child: Icon(
                icon,
                size: 64,
                color: Colors.white.withValues(alpha: 0.25),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 40, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _TileTitle(title, size: 26),
                  const SizedBox(height: 2),
                  _TileSubtitle(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tribün / Kayıt Ol: tam genişlik, dokununca doğrudan ilgili yere gider.
class _WideTile extends StatelessWidget {
  const _WideTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _TileFrame(
      colors: colors,
      selected: false,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TileTitle(title, size: 22),
                  const SizedBox(height: 2),
                  _TileSubtitle(subtitle),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _TileFrame extends StatelessWidget {
  const _TileFrame({
    required this.colors,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final List<Color> colors;
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        border: Border.all(
          color: selected ? Colors.white : Colors.transparent,
          width: 2.5,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ClipRRect(borderRadius: radius, child: child),
        ),
      ),
    );
  }
}

class _TileTitle extends StatelessWidget {
  const _TileTitle(this.text, {required this.size});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase(),
      style: TextStyle(
        fontFamily: 'BarlowCondensed',
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w800,
        fontSize: size,
        height: 1,
        color: Colors.white,
      ),
    );
  }
}

class _TileSubtitle extends StatelessWidget {
  const _TileSubtitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.88),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
    );
  }
}
