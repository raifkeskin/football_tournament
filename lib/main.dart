import 'core/app_navigator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/home/screens/main_navigator.dart';
import 'core/services/app_session.dart';
import 'core/services/active_tournament.dart';
import 'core/services/app_settings.dart';
import 'core/widgets/app_name_band.dart';
import 'core/widgets/app_logo.dart';
import 'core/widgets/web_safe_image.dart';
import 'core/widgets/web_responsive_frame.dart';
import 'core/utils/app_activity.dart';
import 'core/services/error_reporter.dart';
import 'core/services/notification_center.dart';

bool _showLoginGate() {
  final user = Supabase.instance.client.auth.currentUser;
  final signedIn = user != null && !user.isAnonymous;
  return !signedIn && !GuestMode.chosen;
}

/// Uygulama giriş noktası.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Hatalar kaydedilir; ekran yerleşemezse "Bir sorun oluştu" kartı.
  ErrorReporter.init();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  // Arka planda canlı bağlantılar kapansın (eşzamanlı bağlantı sınırı).
  AppActivity.start();
  // Zildeki okunmamış bildirim sayısı.
  NotificationCenter.start();

  // "Beni Hatırla" işaretlenmediyse önceki oturumu kapat: uygulama giriş
  // ekranıyla açılır.
  await AppSessionController.enforceRememberMe();
  await AppSettings.load();
  await GuestMode.load();
  // Son turnuva teması hemen; kişiye göre güncel tema arkadan.
  await ActiveTournament.init(guestChosen: GuestMode.chosen);

  runApp(const MyApp());
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _hasNavigated = false;

  // Öğeler hafifçe yukarı kayarak belirir.
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _continueToApp() {
    if (_hasNavigated) return;
    _hasNavigated = true;

    // Oturum yoksa ve misafir seçimi yapılmadıysa önce giriş kapısı:
    // giriş yapan kişi uygulamayı kendi turnuvasıyla görür.
    final user = Supabase.instance.client.auth.currentUser;
    final signedIn = user != null && !user.isAnonymous;
    final showGate = !signedIn && !GuestMode.chosen;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            showGate ? const LoginScreen(gate: true) : const MainNavigator(),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  Widget _reveal({required double start, required Widget child}) {
    final curve = CurvedAnimation(
      parent: _anim,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.15),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ActiveTournament.theme.value;
    const bgDark = Color(0xFF0F172A);
    const accent = Color(0xFF10B981);

    return Scaffold(
      backgroundColor: bgDark,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _continueToApp,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xCC0F172A),
                    Color(0x660F172A),
                    Color(0xF20F172A),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  // Kişinin turnuvası temalıysa açılış o turnuvanın logosu
                  // ve adıyla; altında küçük uygulama adı.
                  _reveal(
                    start: 0,
                    child: theme == null
                        ? const AppLogo(size: 150, tile: false)
                        : WebSafeImage(
                            url: theme.logoUrl,
                            width: 170,
                            height: 170,
                            fit: BoxFit.contain,
                          ),
                  ),
                  const SizedBox(height: 28),
                  if (theme != null || kShowAppName)
                    _reveal(
                      start: 0.15,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          theme?.name ?? kAppName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  _reveal(
                    start: 0.3,
                    child: Container(
                      width: 40,
                      height: 3,
                      decoration: BoxDecoration(
                        color: theme?.secondary ?? accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (theme == null || kShowAppName)
                    _reveal(
                      start: 0.4,
                      child: Text(
                        theme == null ? 'Hoş Geldiniz' : kAppName,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  const Spacer(flex: 4),
                  _reveal(
                    start: 0.6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.touch_app_outlined,
                          color: Colors.white.withValues(alpha: 0.55),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Devam etmek için dokunun',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ana tema ve başlangıç rotası — alt gezinme [MainNavigator] ile açılır.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppSessionController _sessionController = AppSessionController();

  @override
  void initState() {
    super.initState();
    ErrorReporter.roleProvider = () {
      final s = _sessionController.value;
      if (s.user == null || s.user!.isAnonymous) return null;
      final roles = [
        if (s.isAdmin) 'admin',
        if (s.isLeagueOwner) 'owner',
        if (s.isRegionOwner) 'region',
        if (s.isManager || s.managedTeams.isNotEmpty) 'manager',
        if (s.playerId != null) 'player',
      ];
      return roles.isEmpty ? s.role : roles.join('+');
    };
    // Yenile: başlangıç ekranı (giriş kapısı / açılış) güncel oturuma göre.
    ErrorReporter.epoch.addListener(_onRestart);
  }

  void _onRestart() {
    if (mounted) setState(() {});
  }

  static const Color _headerForest = Color(0xFF064E3B);
  static const Color _bgDark = Color(0xFF0F172A);
  static const Color _cardDark = Color(0xFF1E293B);
  static const Color _accent = Color(0xFF10B981);
  static const Color _text = Color(0xFFF8FAFC);
  static const Color _muted = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    const colorScheme = ColorScheme.dark(
      primary: _headerForest,
      onPrimary: _text,
      secondary: _accent,
      onSecondary: Colors.white,
      surface: _cardDark,
      onSurface: _text,
      surfaceContainerHighest: _cardDark,
      onSurfaceVariant: _muted,
      outlineVariant: Color(0xFF334155),
      error: Color(0xFFEF4444),
      onError: Colors.white,
    );

    return AppSession(
      controller: _sessionController,
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        title: kAppName,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
        locale: const Locale('tr', 'TR'),
        theme: ThemeData(
          colorScheme: colorScheme,
          useMaterial3: true,
          brightness: Brightness.dark,
          // iPhone gibi: detay sayfalarında sol kenardan sağa çekince geri.
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: CupertinoPageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
              TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
              TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
              TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
            },
          ),
          scaffoldBackgroundColor: _bgDark,
          textTheme: (() {
            // Barlow uygulamaya gömülü (pubspec fonts): açılışta internetten
            // yazı tipi inmez, metinler ilk karede doğru yazı tipiyle çizilir.
            final base = ThemeData.dark().textTheme.apply(
              fontFamily: 'Barlow',
              bodyColor: _text,
              displayColor: _text,
            );
            TextStyle? asBatangas(TextStyle? s) {
              if (s == null) return null;
              return s.copyWith(
                fontFamily: 'Batangas',
                fontWeight: FontWeight.w900,
              );
            }

            return base.copyWith(
              displayLarge: asBatangas(base.displayLarge),
              displayMedium: asBatangas(base.displayMedium),
              displaySmall: asBatangas(base.displaySmall),
              headlineLarge: asBatangas(base.headlineLarge),
              headlineMedium: asBatangas(base.headlineMedium),
              headlineSmall: asBatangas(base.headlineSmall),
              titleLarge: asBatangas(base.titleLarge),
              titleMedium: asBatangas(base.titleMedium),
            );
          })(),
          appBarTheme: AppBarTheme(
            backgroundColor: _headerForest,
            foregroundColor: _text,
            titleTextStyle: const TextStyle(
              color: _text,
              fontFamily: 'Batangas',
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          tabBarTheme: const TabBarThemeData(
            labelStyle: TextStyle(
              fontFamily: 'Batangas',
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            unselectedLabelStyle: TextStyle(
              fontFamily: 'Batangas',
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          cardTheme: CardThemeData(
            color: _cardDark,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          dividerTheme: DividerThemeData(
            color: _muted.withValues(alpha: 0.18),
            thickness: 1,
            space: 1,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            labelStyle: TextStyle(
              color: _text.withValues(alpha: 0.90),
              fontWeight: FontWeight.w700,
            ),
            floatingLabelStyle: TextStyle(
              color: _text.withValues(alpha: 0.95),
              fontWeight: FontWeight.w800,
            ),
            hintStyle: TextStyle(
              color: _text.withValues(alpha: 0.65),
              fontWeight: FontWeight.w600,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.white54, width: 1),
            ),
          ),
          // Çerçeveli butonlar (ör. VAZGEÇ) koyu zeminde okunur olsun;
          // varsayılan koyu yeşil yazı neredeyse görünmüyordu.
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
          ),
        ),
        builder: (context, child) {
          if (child == null) return const SizedBox.shrink();
          return WebResponsiveFrame(
            child: AppNameBand(child: ErrorRecoveryOverlay(child: child)),
          );
        },
        // Oturum yoksa ve misafir seçimi yapılmadıysa uygulama doğrudan giriş
        // ekranıyla açılır; aksi halde (kişinin turnuvasıyla) açılış ekranı.
        home: _showLoginGate()
            ? const LoginScreen(gate: true)
            : const SplashScreen(),
      ),
    );
  }

  @override
  void dispose() {
    ErrorReporter.epoch.removeListener(_onRestart);
    _sessionController.dispose();
    super.dispose();
  }
}
