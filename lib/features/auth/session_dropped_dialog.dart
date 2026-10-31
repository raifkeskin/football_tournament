import 'package:flutter/material.dart';

import '../../core/app_navigator.dart';
import '../../core/widgets/admin_page.dart';
import 'screens/login_screen.dart';

/// Oturum kullanıcı çıkmadan kapandı ve geri getirilemedi: kullanıcı
/// sessizce misafire düşmesin, tekrar giriş yapması istensin.
Future<void> showSessionDroppedDialog() async {
  final context = appNavigatorKey.currentContext;
  if (context == null || _open) return;
  _open = true;
  try {
    final login = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        icon: const Icon(Icons.wifi_off_rounded, color: Color(0xFFFBBF24)),
        title: const Text(
          'Bağlantın kesildi',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Oturumun sona erdi. Kaldığın yerden devam etmek için lütfen tekrar '
          'giriş yap.',
          style: TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Misafir devam et',
              style: TextStyle(color: Colors.white60),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kAdminAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Giriş yap',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (login == true) {
      await appNavigatorKey.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      );
    }
  } finally {
    _open = false;
  }
}

bool _open = false;
