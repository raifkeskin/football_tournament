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
  Map<String, bool> _ibraz = const {};

  @override
  void initState() {
    super.initState();
    AppSettings.loadIbrazSettings()
        .then((m) {
          if (mounted) setState(() => _ibraz = m);
        })
        .catchError((_) {});
  }

  Future<void> _setIbraz(String key, bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    final prev = _ibraz;
    setState(() => _ibraz = {...prev, key: on});
    try {
      await AppSettings.setIbrazSetting(key, on);
    } catch (e) {
      if (mounted) setState(() => _ibraz = prev);
      messenger.showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    }
  }

  Widget _ibrazRow(IconData icon, String label, String key, String sub) {
    final on = _ibraz[key] ?? false;
    return AdminFieldRow(
      icon: icon,
      label: label,
      onTap: () => _setIbraz(key, !on),
      trailing: Switch.adaptive(
        value: on,
        activeTrackColor: kIbrazOrange,
        onChanged: (v) => _setIbraz(key, v),
      ),
      child: Text(
        sub,
        style: TextStyle(
          color: on ? Colors.white : kAdminMuted,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

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
            const SizedBox(height: 18),
            AdminFormSection(
              title: 'Kimlik ibrazıyla onay',
              child: AdminFieldGroup(
                children: [
                  _ibrazRow(
                    Icons.badge_outlined,
                    'İbraz özelliği',
                    'ibraz_enabled',
                    (_ibraz['ibraz_enabled'] ?? false) ? 'Açık' : 'Kapalı',
                  ),
                  _ibrazRow(
                    Icons.account_balance_outlined,
                    'Kurucu başkan onaylar',
                    'ibraz_approve_owner',
                    'Kendi turnuvasındaki kayıtlar',
                  ),
                  _ibrazRow(
                    Icons.map_outlined,
                    'Bölge sorumlusu onaylar',
                    'ibraz_approve_region',
                    'Yalnız kendi bölgesindeki kayıtlar',
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                'Açıkken Kayıt Ol ekranında "Kimliğimi okutmadan devam et" '
                'görünür; kayıtlar yetkilinin kimliği görüp onaylamasıyla '
                'turuncu tikli olur. Admin her zaman onaylayabilir.',
                style: TextStyle(color: kAdminMuted, fontSize: 12, height: 1.4),
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
