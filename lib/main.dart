import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'firebase_options.dart';
import 'features/home/screens/main_navigator.dart';
import 'core/services/app_session.dart';
import 'core/services/database_service.dart';
import 'core/widgets/web_responsive_frame.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Uygulama giriş noktası.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );
  if (AppConfig.activeDatabase == DatabaseType.supabase) {
    try {
      final res = await Supabase.instance.client.from('pitches').select('id').limit(1);
      final n = (res is List) ? res.length : 0;
      debugPrint('Supabase bağlantı kontrolü OK (pitches örnek kayıt: $n)');
    } catch (e) {
      debugPrint('Supabase bağlantı kontrolü HATA: $e');
    }
  }

  runApp(const MyApp());
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
  }

  void _continueToApp() {
    if (_hasNavigated) return;
    _hasNavigated = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const MainNavigator(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _continueToApp,
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset('assets/acilis_2.png', fit: BoxFit.cover),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.touch_app,
                        color: Colors.white,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Sürdürmek için Dokunun',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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

  static const Color _headerForest = Color(0xFF064E3B);
  static const Color _bgDark = Color(0xFF0F172A);
  static const Color _cardDark = Color(0xFF1E293B);
  static const Color _accent = Color(0xFF10B981);
  static const Color _text = Color(0xFFF8FAFC);
  static const Color _muted = Color(0xFF94A3B8);

  @override
  void initState() {
    super.initState();
    if (AppConfig.activeDatabase == DatabaseType.firebase) {
      DatabaseService().migratePlayersDefaultRoleAndBirthDate();
      DatabaseService().migratePlayersPhoneRaw10();
    }
  }

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
        title: 'Futbol Turnuvası',
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
          scaffoldBackgroundColor: _bgDark,
          textTheme: (() {
            final base = GoogleFonts.interTextTheme().apply(
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
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
          ),
        ),
        builder: (context, child) {
          if (child == null) return const SizedBox.shrink();
          return WebResponsiveFrame(child: child);
        },
        home: const SplashScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _sessionController.dispose();
    super.dispose();
  }
}
