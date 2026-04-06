import 'package:flutter/material.dart';

import 'screens/main_navigator.dart';

/// Uygulama giriş noktası.
void main() {
  runApp(const MyApp());
}

/// Ana tema ve başlangıç rotası — alt gezinme [MainNavigator] ile açılır.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  /// Koyu yeşil tonları (varsayılan mavi yerine).
  static const Color _anaYesil = Color(0xFF1B5E20);
  static const Color _ikincilYesil = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _anaYesil,
      primary: _anaYesil,
      secondary: _ikincilYesil,
    );

    return MaterialApp(
      title: 'Futbol Turnuvası',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: colorScheme.surface,
          selectedItemColor: colorScheme.primary,
          unselectedItemColor: colorScheme.onSurfaceVariant,
          type: BottomNavigationBarType.fixed,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
        ),
      ),
      home: const MainNavigator(),
    );
  }
}
