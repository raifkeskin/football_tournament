import 'package:flutter/material.dart';

import 'admin_panel_screen.dart';

/// Uygulama içindeki kullanıcı rolleri.
enum UserRole { admin, teamManager, standard }

/// Profil ekranı — rol tabanlı yönetim aksiyonları içerir.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  /// Demo amaçlı aktif kullanıcı rolü.
  /// Gerçek projede bu değer auth katmanından gelmelidir.
  final UserRole _aktifRol = UserRole.admin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rolMetni = switch (_aktifRol) {
      UserRole.admin => 'Admin',
      UserRole.teamManager => 'Takım Yöneticisi',
      UserRole.standard => 'Standart Kullanıcı',
    };

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Card(
            elevation: 0,
            color: cs.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: cs.primary.withValues(alpha: 0.14),
                    child: Icon(Icons.person, size: 40, color: cs.primary),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Raif Keskin',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rolMetni,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ..._rolButonlari(context, _aktifRol),
        ],
      ),
    );
  }

  /// Role göre görünecek aksiyonlar.
  List<Widget> _rolButonlari(BuildContext context, UserRole rol) {
    return switch (rol) {
      UserRole.admin => [
        _AksiyonButonu(
          baslik: 'Sistem Yönetim Paneli',
          ikon: Icons.admin_panel_settings_outlined,
          arkaPlan: const Color(0xFFFFEBEE),
          yaziRenk: const Color(0xFFC62828),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AdminPanelScreen()),
            );
          },
        ),
        const SizedBox(height: 12),
        _AksiyonButonu(
          baslik: 'Lig/Haber Ayarları',
          ikon: Icons.settings_suggest_outlined,
          arkaPlan: const Color(0xFFFFF1F1),
          yaziRenk: const Color(0xFFC62828),
          onPressed: () {},
        ),
      ],
      UserRole.teamManager => [
        _AksiyonButonu(
          baslik: 'Takım Yönetimi',
          ikon: Icons.groups_2_outlined,
          arkaPlan: const Color(0xFFEAF2FF),
          yaziRenk: const Color(0xFF1565C0),
          onPressed: () {},
        ),
        const SizedBox(height: 12),
        _AksiyonButonu(
          baslik: 'Kadro Güncelle (Excel)',
          ikon: Icons.upload_file_outlined,
          arkaPlan: const Color(0xFFF0F6FF),
          yaziRenk: const Color(0xFF1565C0),
          onPressed: () {},
        ),
      ],
      UserRole.standard => [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Standart kullanıcılar için ek yönetim işlemi bulunmuyor.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    };
  }
}

/// Gölgesiz, pastel renkli aksiyon butonu.
class _AksiyonButonu extends StatelessWidget {
  const _AksiyonButonu({
    required this.baslik,
    required this.ikon,
    required this.arkaPlan,
    required this.yaziRenk,
    required this.onPressed,
  });

  final String baslik;
  final IconData ikon;
  final Color arkaPlan;
  final Color yaziRenk;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        elevation: 0,
        minimumSize: const Size(double.infinity, 52),
        backgroundColor: arkaPlan,
        foregroundColor: yaziRenk,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(ikon),
      label: Text(baslik, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}
