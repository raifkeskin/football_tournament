class UserDoc {
  const UserDoc({required this.uid, required this.role, required this.phone});

  final String uid;
  final String? role;
  final String phone;
}

class RosterAssignment {
  const RosterAssignment({
    required this.id,
    required this.tournamentId,
    required this.teamId,
    required this.role,
  });

  final String id;
  final String tournamentId;
  final String teamId;
  final String role;
}

class OtpRequest {
  const OtpRequest({
    required this.phoneRaw10,
    required this.code,
    required this.expiresAt,
  });

  final String phoneRaw10;
  final String code;
  final DateTime expiresAt;
}

class OtpCodeEntry {
  const OtpCodeEntry({
    required this.id,
    required this.phoneRaw10,
    required this.code,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String phoneRaw10;
  final String code;
  final String status;
  final DateTime expiresAt;
  final DateTime? createdAt;
}

class ProfileLookupResult {
  const ProfileLookupResult._({
    required this.profileFound,
    required this.resolvedRole,
    required this.matchedPlayerId,
    required this.playerName,
    required this.resolvedTeamId,
    required this.resolvedTeamName,
    required this.resolvedTournamentId,
    required this.matchedLeagueIds,
    required this.leagues,
  });

  const ProfileLookupResult.notFound()
    : this._(
        profileFound: false,
        resolvedRole: 'player',
        matchedPlayerId: null,
        playerName: null,
        resolvedTeamId: 'free_agent_pool',
        resolvedTeamName: null,
        resolvedTournamentId: null,
        matchedLeagueIds: const [],
        leagues: const [],
      );

  ProfileLookupResult.tournamentAdmin({
    required List<String> matchedLeagueIds,
    required List<Map<String, dynamic>> leagues,
  }) : this._(
         profileFound: true,
         resolvedRole: 'tournament_admin',
         matchedPlayerId: null,
         playerName: null,
         resolvedTeamId: null,
         resolvedTeamName: null,
         resolvedTournamentId: null,
         matchedLeagueIds: matchedLeagueIds,
         leagues: leagues,
       );

  ProfileLookupResult.playerProfile({
    required String? matchedPlayerId,
    required String? playerName,
    required String resolvedRole,
    required String? resolvedTeamId,
    required String? resolvedTournamentId,
    required String? resolvedTeamName,
  }) : this._(
         profileFound: true,
         resolvedRole: resolvedRole,
         matchedPlayerId: matchedPlayerId,
         playerName: playerName,
         resolvedTeamId: resolvedTeamId,
         resolvedTeamName: resolvedTeamName,
         resolvedTournamentId: resolvedTournamentId,
         matchedLeagueIds: const [],
         leagues: const [],
       );

  final bool profileFound;
  final String resolvedRole;
  final String? matchedPlayerId;
  final String? playerName;
  final String? resolvedTeamId;
  final String? resolvedTeamName;
  final String? resolvedTournamentId;
  final List<String> matchedLeagueIds;
  final List<Map<String, dynamic>> leagues;
}

class OnlineRegistrationResult {
  const OnlineRegistrationResult({
    required this.uid,
    required this.isTournamentAdmin,
    required this.tournamentId,
  });

  final String uid;
  final bool isTournamentAdmin;
  final String? tournamentId;
}
