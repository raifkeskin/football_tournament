import 'package:firebase_auth/firebase_auth.dart';

import '../../models/auth_models.dart';

abstract class IAuthService {
  Future<ConfirmationResult> startPhoneAuthWeb({
    required String phoneNumber,
  });

  Stream<UserDoc?> watchUserDoc(String uid);

  Stream<List<RosterAssignment>> watchRosterAssignmentsByPhone(String phone);

  Future<void> createOtpRequest({
    required String phoneRaw10,
    required String code,
    required DateTime expiresAt,
  });

  Future<OtpRequest?> getOtpRequest(String phoneRaw10);

  Future<void> deleteOtpRequest(String phoneRaw10);

  Stream<List<OtpCodeEntry>> watchOtpCodes({bool includeVerified = false});

  Future<ProfileLookupResult> lookupProfileByPhoneRaw10(String phoneRaw10);

  Future<OnlineRegistrationResult> registerOnlineUser({
    required String phoneRaw10,
    required String password,
    required bool profileFound,
    required String resolvedRole,
    required String? resolvedTeamId,
    required String? resolvedTournamentId,
    required String? matchedPlayerId,
    required List<String> matchedTournamentIds,
    required String? selectedTournamentId,
    required String? name,
    required String? surname,
  });
}
