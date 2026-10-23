import 'package:flutter/material.dart';

import '../../core/services/app_settings.dart';
import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import 'verified_badge.dart';

/// Kimlik Yönetimi (yalnız admin): kimlik doğrulama admin dışında hangi
/// rollere açık. Sunucu da aynı ayara bakar (identity_allowed).
class AdminIdentityScreen extends StatefulWidget {
  const AdminIdentityScreen({super.key});

  @override
  State<AdminIdentityScreen> createState() => _AdminIdentityScreenState();
}

class _AdminIdentityScreenState extends State<AdminIdentityScreen> {
  /// (anahtar, ad, açıklama, ikon)
  static const _roles = [
    (
      'league_owner',
      'Kurucu Başkan',
      'Oyuncuların kimliğini okutup profillerini onaylar.',
      Icons.workspace_premium_rounded,
    ),
    (
      'region_owner',
      'Bölge Sorumlusu',
      'Oyuncuların kimliğini okutup profillerini onaylar.',
      Icons.map_rounded,
    ),
    (
      'team_manager',
      'Takım Sorumlusu',
      'Oyuncuların kimliğini okutup profillerini onaylar.',
      Icons.shield_rounded,
    ),
    (
      'player',
      'Futbolcu',
      'Profili onaysızken kendi kimliğini okutur.',
      Icons.person_rounded,
    ),
  ];

  final Set<String> _saving = {};

  Future<void> _set(String role, bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving.add(role));
    try {
      await AppSettings.setIdentityRole(role, on);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _saving.remove(role));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Kimlik Yönetimi',
      body: ValueListenableBuilder<Set<String>>(
        valueListenable: AppSettings.identityVerificationRoles,
        builder: (context, roles, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            AdminFormSection(
              title: 'Kimlik doğrulamayı görebilen roller',
              child: AdminFieldGroup(
                children: [
                  for (final (key, name, hint, icon) in _roles)
                    AdminFieldRow(
                      icon: icon,
                      label: name,
                      onTap: _saving.contains(key)
                          ? null
                          : () => _set(key, !roles.contains(key)),
                      trailing: _saving.contains(key)
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Switch.adaptive(
                              value: roles.contains(key),
                              activeTrackColor: kVerifiedBlue,
                              onChanged: (v) => _set(key, v),
                            ),
                      child: Text(
                        roles.contains(key) ? 'Aktif · $hint' : 'Pasif',
                        style: TextStyle(
                          color: roles.contains(key)
                              ? Colors.white
                              : kAdminMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Text(
                'Admin her zaman görür. Değişiklik hemen geçerli olur; '
                'açık uygulamalarda bir sonraki açılışta görünür. Kimlik '
                'okuma yalnız uygulamada (Android / iPhone) yapılır.',
                style: TextStyle(color: kAdminMuted, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
