import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, Supabase;

import '../../../core/services/active_tournament.dart';
import '../../../core/services/app_session.dart';
import '../../../core/widgets/app_name_band.dart';
import 'forgot_password_screen.dart';
import '../../home/screens/main_navigator.dart';
import 'online_registration_screen.dart';
import 'reset_password_screen.dart';
import '../widgets/phone_input.dart';
import '../password_input.dart';
import '../../../core/widgets/admin_form.dart';
import '../../tournament_request/tournament_request.dart';
import '../../../core/services/app_settings.dart';
import '../registration/register_choice_screen.dart';

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
  // Telefon alanında klavyenin "ileri" tuşu doğrudan şifreye geçer; odak
  // sıralamasına bırakılırsa arkadaki sekmelere atlayabiliyor.
  final _passwordFocus = FocusNode();
  bool _rememberMe = false;
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
    // Bandın adına üç dokunuş: gizli admin girişi (görünen giriş formu).
    if (visible) {
      AppNameBand.onLoginTitleTap = _onBandTitleTap;
    } else if (AppNameBand.onLoginTitleTap == _onBandTitleTap) {
      AppNameBand.onLoginTitleTap = null;
    }
    // (Kurulum/kaldırma sırasında bant yeniden çizilemez; ertelenir.)
    Future.microtask(
      () => AppNameBand.genericScreens.value += visible ? 1 : -1,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadLastPhone();
  }

  /// Son girişin telefonu (çıkış yapılsa da) alana yazılır.
  Future<void> _loadLastPhone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(AppSessionController.lastLoginPhoneKey) ?? '';
      if (!mounted || raw.length != 10 || _phoneController.text.isNotEmpty) {
        return;
      }
      _phoneController.text = PhoneMaskFormatter.formatFromRaw(raw);
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBand(TickerMode.valuesOf(context).enabled);
  }

  @override
  void dispose() {
    _syncBand(false);
    _adminTapTimer?.cancel();
    _phoneController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _onBandTitleTap() {
    if (mounted) _handleAdminTitleTap(AppSession.of(context));
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
          settings: const RouteSettings(name: 'MainNavigator'),
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
            settings: const RouteSettings(name: 'ResetPasswordScreen'),
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
          settings: const RouteSettings(name: 'MainNavigator'),
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
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'MainNavigator'),
        builder: (_) => const MainNavigator(),
      ),
      (Route<dynamic> route) => false,
    );
  }

  void _openRegistration() {
    // Yeni akış açıksa kayıt türü seçimi, değilse eski kayıt talebi.
    final next = AppSettings.selfRegistrationEnabled.value;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          name: next ? 'RegisterChoiceScreen' : 'OnlineRegistrationScreen',
        ),
        builder: (_) => next
            ? const RegisterChoiceScreen()
            : const OnlineRegistrationScreen(),
      ),
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

    // Klavyenin açılması bu ekranı yeniden çizsin (gömülü formda iç
    // Scaffold'a gelen boşluklar kaldırılmış olabilir; asıl değer View'dan).
    MediaQuery.viewInsetsOf(context);
    return Scaffold(
      backgroundColor: bgDark,
      // Başlık ve menü yok (üstte uygulama bandı var): giriş ekranında
      // hiçbir durumda menü düğmesi gösterilmez.
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final keyboard = View.of(context).viewInsets.bottom > 0;
            final h = constraints.maxHeight;
            // Kaydırma çıkmasın: kartlar ve aralar ekran yüksekliğine göre
            // küçülür (~700 tam boy, ~560 en küçük); daha kısa ekranda kart
            // alt yazıları da gizlenir, yine sığmazsa kaydırılır. Telefon,
            // şifre ve giriş düğmesi küçülmez.
            final s = ((h - 560) / 140).clamp(0.0, 1.0);
            final subtitles = h >= 520;
            final gap = 6 + 4 * s;
            // Klavye açıkken: kartlar ince seçiciye döner, Tribün / Kayıt Ol
            // ve turnuva kartı gizlenir; açıklama yalnız yer varsa kalır.
            final showInfo = !keyboard || h >= 400;
            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  keyboard ? 8 : 10 + 8 * s,
                  16,
                  keyboard ? 12 : 16 + 8 * s,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _RoleTile(
                                title: 'Saha',
                                subtitle: 'Futbolcuyum',
                                icon: Icons.sports_soccer_rounded,
                                colors: const [
                                  Color(0xFF22C55E),
                                  Color(0xFF0F6B35),
                                ],
                                selected: !_staff,
                                compact: keyboard,
                                scale: s,
                                showSubtitle: subtitles,
                                onTap: _loading
                                    ? null
                                    : () => setState(() => _staff = false),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _RoleTile(
                                title: 'Kulübe',
                                subtitle: 'Turnuva / Takım Sorumlusuyum',
                                icon: Icons.assignment_ind_rounded,
                                colors: const [
                                  Color(0xFFF59E0B),
                                  Color(0xFF9A5B06),
                                ],
                                selected: _staff,
                                compact: keyboard,
                                scale: s,
                                showSubtitle: subtitles,
                                onTap: _loading
                                    ? null
                                    : () => setState(() => _staff = true),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _Collapse(
                        visible: !keyboard,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: gap),
                            _WideTile(
                              title: 'Tribün',
                              subtitle:
                                  'Girişe gerek olmadan, tüm turnuvaları takip et',
                              icon: Icons.stadium_rounded,
                              colors: const [
                                Color(0xFF1E3A8A),
                                Color(0xFF172554),
                              ],
                              scale: s,
                              showSubtitle: subtitles,
                              onTap: _loading ? null : _continueAsGuest,
                            ),
                            SizedBox(height: gap),
                            _WideTile(
                              title: 'Kayıt Ol',
                              subtitle: 'Hesabın yok mu? Telefonunla hesap aç',
                              icon: Icons.person_add_alt_1_rounded,
                              colors: const [
                                Color(0xFF475569),
                                Color(0xFF1E293B),
                              ],
                              scale: s,
                              showSubtitle: subtitles,
                              onTap: _loading ? null : _openRegistration,
                            ),
                          ],
                        ),
                      ),
                      _Collapse(
                        visible: showInfo,
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: keyboard ? 12 : 12 + 10 * s,
                          ),
                          child: Text(
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
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phoneController,
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.phone,
                        onEditingComplete: _passwordFocus.requestFocus,
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
                      ValueListenableBuilder<bool>(
                        valueListenable: PasswordKeyboard.numeric,
                        builder: (context, _, _) => TextField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          obscureText: true,
                          keyboardType: PasswordKeyboard.type,
                          onSubmitted: _loading ? null : (_) => _login(session),
                          decoration:
                              _fieldDecoration(
                                label: 'Şifre',
                                icon: Icons.lock_outline,
                              ).copyWith(
                                suffixIcon: PasswordKeyboardToggle(
                                  focus: _passwordFocus,
                                ),
                              ),
                          style: fieldText,
                          enabled: !_loading,
                        ),
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
                                  : (v) => setState(
                                      () => _rememberMe = v ?? false,
                                    ),
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
                          const Spacer(),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      settings: const RouteSettings(
                                        name: 'ForgotPasswordScreen',
                                      ),
                                      builder: (_) =>
                                          const ForgotPasswordScreen(),
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
                      _Collapse(
                        visible: !keyboard,
                        child: const TournamentRequestLoginCard(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Bölümü yumuşakça daraltıp gizler / geri açar (klavye açılınca).
class _Collapse extends StatelessWidget {
  const _Collapse({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      firstChild: child,
      secondChild: const SizedBox(width: double.infinity),
      crossFadeState: visible
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
      duration: const Duration(milliseconds: 250),
      sizeCurve: Curves.easeOut,
    );
  }
}

/// Saha / Kulübe kutusu: seçilince beyaz çerçeve. [compact]: klavye açıkken
/// ince seçici (simge + ad). [scale] 0..1: ekran yüksekliğine göre boy.
class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.selected,
    required this.onTap,
    this.compact = false,
    this.scale = 1,
    this.showSubtitle = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final bool selected;
  final VoidCallback? onTap;
  final bool compact;
  final double scale;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final full = ConstrainedBox(
      constraints: BoxConstraints(minHeight: 76 + 36 * scale),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            top: -10,
            child: Icon(
              icon,
              size: 48 + 16 * scale,
              color: Colors.white.withValues(alpha: 0.25),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(14, 28 + 12 * scale, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _TileTitle(title, size: 22 + 4 * scale),
                if (showSubtitle) ...[
                  const SizedBox(height: 2),
                  _TileSubtitle(subtitle),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    final slim = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 8),
          _TileTitle(title, size: 20),
        ],
      ),
    );
    return _TileFrame(
      colors: colors,
      selected: selected,
      onTap: onTap,
      child: AnimatedCrossFade(
        firstChild: full,
        secondChild: slim,
        crossFadeState: compact
            ? CrossFadeState.showSecond
            : CrossFadeState.showFirst,
        duration: const Duration(milliseconds: 250),
        sizeCurve: Curves.easeOut,
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
    this.scale = 1,
    this.showSubtitle = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback? onTap;
  final double scale;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final v = 6 + 4 * scale;
    return _TileFrame(
      colors: colors,
      selected: false,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, v, 10, v),
        child: Row(
          children: [
            Icon(
              icon,
              color: Colors.white.withValues(alpha: 0.85),
              size: 24 + 4 * scale,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TileTitle(title, size: 18 + 4 * scale),
                  if (showSubtitle) ...[
                    const SizedBox(height: 2),
                    _TileSubtitle(subtitle),
                  ],
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
