import 'package:flutter/material.dart';

import '../../features/notifications/notifications_screen.dart';
import '../app_navigator.dart';
import '../services/notification_center.dart';

/// Banttaki zil: okunmamış bildirim varsa kırmızı sayı (9+). Misafirde
/// çizilmez.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, this.color = Colors.white});

  // Zil artık altın renkli; renk eski çağıranlar için tutuluyor.
  final Color color;

  static var _opening = false;

  static Future<void> open() async {
    final nav = appNavigatorKey.currentState;
    if (nav == null || _opening) return;
    _opening = true;
    try {
      await nav.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'NotificationsScreen'),
          builder: (_) => const NotificationsScreen(),
        ),
      );
    } finally {
      _opening = false;
      NotificationCenter.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: NotificationCenter.enabled,
      builder: (context, enabled, _) {
        if (!enabled) return const SizedBox.shrink();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: open,
          child: SizedBox(
            width: 42,
            height: 42,
            child: ValueListenableBuilder<int>(
              valueListenable: NotificationCenter.unread,
              builder: (context, n, _) => Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // Altın renkli dolu zil (🔔 gibi): gölgeli, üstten
                  // alta açık sarıdan koyu altına.
                  ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (r) => const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFFE89A),
                        Color(0xFFFBC02D),
                        Color(0xFFD08A00),
                      ],
                    ).createShader(r),
                    child: Icon(
                      Icons.notifications_rounded,
                      size: 27,
                      shadows: const [
                        Shadow(color: Color(0x66000000), blurRadius: 4),
                      ],
                      semanticLabel: n > 0
                          ? 'Bildirimler, $n okunmamış'
                          : 'Bildirimler',
                    ),
                  ),
                  if (n > 0)
                    Positioned(
                      top: 5,
                      right: 4,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: const Color(0xFF0F172A),
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          n > 9 ? '9+' : '$n',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            height: 1,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
