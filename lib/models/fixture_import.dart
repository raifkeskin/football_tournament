class FixtureImportTeam {
  const FixtureImportTeam({
    required this.name,
    required this.groupName,
  });

  final String name;
  final String groupName;
}

class FixtureImportMatch {
  const FixtureImportMatch({
    required this.week,
    required this.groupId,
    required this.homeTeamName,
    required this.awayTeamName,
    required this.matchDateYyyyMmDd,
    required this.matchTime,
    required this.pitchName,
  });

  final int week;
  final String groupId;
  final String homeTeamName;
  final String awayTeamName;
  final String? matchDateYyyyMmDd;
  final String? matchTime;
  final String? pitchName;
}
