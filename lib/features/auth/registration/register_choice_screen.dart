import 'package:flutter/material.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../identity/verified_badge.dart';
import '../../tournament_request/tournament_request.dart';
import 'register_player_screen.dart';

/// Kayıt Ol: Futbolcu Profili (kimlikle) ya da Turnuva Kurucu / Sorumlusu.
class RegisterChoiceScreen extends StatelessWidget {
  const RegisterChoiceScreen({super.key});

  void _open(BuildContext context, String name, Widget screen) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: name),
          builder: (_) => screen,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Kayıt Ol',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: [
          const Text(
            'Hangi hesabı açıyorsun?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Seçimine göre birkaç adımda hesabın hazır olur.',
            style: TextStyle(color: kAdminMuted, fontSize: 14),
          ),
          const SizedBox(height: 22),
          _ChoiceCard(
            title: 'Futbolcu Profili',
            text:
                'Kimliğini telefonuna okut; adın, soyadın ve doğum tarihin '
                'kimlikten otomatik gelir. TC Kimlik No geri dönülemez '
                'şekilde şifrelenir, bunlar dışındaki hiçbir bilgi sisteme '
                'kaydedilmez.',
            icon: Icons.person_rounded,
            colors: const [Color(0xFF16A34A), Color(0xFF0F6B35)],
            badge: true,
            tags: const ['Kimlik kartı gerekli', "NFC'li telefon"],
            onTap: () => _open(
              context,
              'RegisterPlayerScreen',
              const RegisterPlayerScreen(),
            ),
          ),
          const SizedBox(height: 14),
          _ChoiceCard(
            title: 'Turnuva Kurucu / Sorumlusu',
            text:
                'Turnuvanı Lig Masası\'nda kurmak için talep oluştur; '
                'seninle iletişime geçip kurulumu birlikte yapalım.',
            icon: Icons.emoji_events_rounded,
            colors: const [Color(0xFFF59E0B), Color(0xFF9A5B06)],
            // Turnuva sorumlusu turnuva talebi akışından gelir.
            onTap: () => TournamentRequestAccess.open(context),
          ),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.text,
    required this.icon,
    required this.colors,
    required this.onTap,
    this.badge = false,
    this.tags = const [],
  });

  final String title;
  final String text;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  final bool badge;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: Colors.white, size: 26),
                  ),
                  const Spacer(),
                  if (badge)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          VerifiedBadge(size: 15),
                          SizedBox(width: 5),
                          Text(
                            'Onaylı profil',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                text,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final t in tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          t,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
