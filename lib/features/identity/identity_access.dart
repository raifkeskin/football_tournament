import 'package:flutter/widgets.dart';

import '../../core/services/app_session.dart';
import '../../core/services/app_settings.dart';

/// Kimlik doğrulama şimdilik gizli: admin ve deneme hesapları görür.
/// `identity_verification_enabled` açılınca giriş yapan herkes görür.
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
