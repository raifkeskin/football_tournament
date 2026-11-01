import 'package:flutter/material.dart';

import '../../core/services/app_settings.dart';
import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import 'verified_badge.dart';

/// Kimlik Yönetimi (yalnız admin): kimlik doğrulama Aktif/Pasif. Sunucu da
/// aynı ayara bakar (identity_allowed).
class AdminIdentityScreen extends StatefulWidget {
  const AdminIdentityScreen({super.key});

  @override
  State<AdminIdentityScreen> createState() => _AdminIdentityScreenState();
}

class _AdminIdentityScreenState extends State<AdminIdentityScreen> {
  bool _saving = false;

  Future<void> _set(bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await AppSettings.setIdentityVerificationEnabled(on);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Kimlik Yönetimi',
      body: ValueListenableBuilder<bool>(
        valueListenable: AppSettings.identityVerificationEnabled,
        builder: (context, on, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            AdminFormSection(
              title: 'Kimlik doğrulama',
              child: AdminFieldGroup(
                children: [
                  AdminFieldRow(
                    icon: Icons.verified_user_rounded,
                    label: 'Durum',
                    onTap: _saving ? null : () => _set(!on),
                    trailing: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Switch.adaptive(
                            value: on,
                            activeTrackColor: kVerifiedBlue,
                            onChanged: _set,
                          ),
                    child: Text(
                      on ? 'Aktif' : 'Pasif',
                      style: TextStyle(
                        color: on ? Colors.white : kAdminMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Text(
                on
                    ? 'Futbolcu profilini kendi doğrular (doğrulayınca menüdeki '
                          'düğme gizlenir). Kurucu başkan, bölge ve takım '
                          'sorumluları kadrolarını doğrular ve esamede kimlik '
                          'okutur.'
                    : 'Admin dışında kimse kimlik doğrulama, esamede kimlik '
                          'okutma ve sezondaki kimlik zorunluluğunu görmez. '
                          'Mavi tikler görünmeye devam eder.',
                style: const TextStyle(
                  color: kAdminMuted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                'Kayıt Ol › Futbolcu Profili her durumda kimlik çipiyle '
                'yapılır. Kimlik okuma yalnız uygulamada (Android / iPhone).',
                style: TextStyle(color: kAdminMuted, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
