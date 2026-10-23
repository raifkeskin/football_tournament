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
    AppSettings.identityVerificationRoles,
  ]);

  static bool visible(AppSessionState s) {
    final u = s.user;
    if (u == null || u.isAnonymous) return false;
    if (s.isAdmin) return true;
    if (AppSettings.identityVerificationEnabled.value) return true;
    if (AppSettings.identityVerificationUsers.value.contains(u.id)) {
      return true;
    }
    // Kimlik Yönetimi'nde açılan roller (sunucu identity_allowed ile aynı).
    final roles = AppSettings.identityVerificationRoles.value;
    return (roles.contains('league_owner') && s.isLeagueOwner) ||
        (roles.contains('region_owner') && s.isRegionOwner) ||
        (roles.contains('team_manager') && s.managedTeams.isNotEmpty) ||
        (roles.contains('player') && (s.playerId ?? '').isNotEmpty);
  }

  static bool visibleIn(BuildContext context) {
    try {
      return visible(AppSession.of(context).value);
    } catch (_) {
      return false;
    }
  }
}
