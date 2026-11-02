import 'package:flutter/widgets.dart';

import '../../core/services/app_session.dart';
import '../../core/services/app_settings.dart';

/// Kimlik doğrulama (Kimlik Yönetimi › Aktif/Pasif). Aktifken giriş yapan
/// herkes görür (futbolcu kendi profilini, sorumlular kadrolarını doğrular);
/// pasifken yalnız admin ve deneme hesapları. Mavi tik her durumda görünür.
class IdentityAccess {
  IdentityAccess._();

  static Listenable get changes => Listenable.merge([
    AppSettings.identityVerificationEnabled,
    AppSettings.identityVerificationUsers,
  ]);

  static bool visible(AppSessionState s) {
    final u = s.user;
    if (u == null || u.isAnonymous) return false;
    if (s.isAdmin) return true;
    if (AppSettings.identityVerificationEnabled.value) return true;
    return AppSettings.identityVerificationUsers.value.contains(u.id);
  }

  static bool visibleIn(BuildContext context) {
    try {
      return visible(AppSession.of(context).value);
    } catch (_) {
      return false;
    }
  }
}
