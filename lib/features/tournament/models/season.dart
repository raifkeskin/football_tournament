class Season {
  const Season({
    required this.id,
    required this.leagueId,
    required this.name,
    this.subtitle,
    this.startDate,
    this.endDate,
    this.startingPlayerCount = 11,
    this.subPlayerCount = 7,
    this.city,
    required this.country,
    this.isActive = true,
    this.isDefault = false,
    this.transferStartDate,
    this.transferEndDate,
    this.teamsPerGroup = 4,
    this.numberOfGroups = 1,
    this.instagramUrl,
    this.youtubeUrl,
    this.matchPeriodDuration = 25,
    this.numberOfPlayerChanges = 3,
  });

  final String id;
  final String leagueId;
  final String name;
  final String? subtitle;
  final DateTime? startDate;
  final DateTime? endDate;
  final int startingPlayerCount;
  final int subPlayerCount;
  final String? city;
  final String country;
  final bool isActive;
  final bool isDefault;
  final DateTime? transferStartDate;
  final DateTime? transferEndDate;
  final int teamsPerGroup;
  final int numberOfGroups;
  final String? instagramUrl;
  final String? youtubeUrl;
  final int matchPeriodDuration;
  final int numberOfPlayerChanges;

  factory Season.fromMap(Map<String, dynamic> map) {
    dynamic v(String camel, String snake) => map[camel] ?? map[snake];

    int intFrom(dynamic value, {required int fallback}) {
      if (value == null) return fallback;
      if (value is num) return value.toInt();
      final s = value.toString().replaceAll('\u0000', '').trim();
      return int.tryParse(s) ??
          double.tryParse(s.replaceAll(',', '.'))?.toInt() ??
          fallback;
    }

    bool boolFrom(dynamic value, {required bool fallback}) {
      if (value == null) return fallback;
      if (value is bool) return value;
      if (value is num) return value != 0;
      final s = value.toString().trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes' || s == 'y') return true;
      if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
      return fallback;
    }

    String? nullableTrimmed(dynamic value) {
      final s = (value ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    return Season(
      id: (v('id', 'id') as String?) ?? '',
      leagueId: (nullableTrimmed(v('leagueId', 'league_id')) ?? ''),
      name: (v('name', 'name') as String?) ?? '',
      subtitle: nullableTrimmed(v('subtitle', 'subtitle')),
      startDate: _readDate(v('startDate', 'start_date')),
      endDate: _readDate(v('endDate', 'end_date')),
      startingPlayerCount: intFrom(
        v('startingPlayerCount', 'starting_player_count'),
        fallback: 11,
      ),
      subPlayerCount: intFrom(
        v('subPlayerCount', 'sub_player_count'),
        fallback: 7,
      ),
      city: nullableTrimmed(v('city', 'city')),
      country: (nullableTrimmed(v('country', 'country')) ?? ''),
      numberOfGroups: intFrom(
        v('numberOfGroups', 'number_of_groups'),
        fallback: 1,
      ),
      numberOfPlayerChanges: intFrom(v('numberOfPlayerChanges', 'number_of_player_changes'), fallback: 1),
      teamsPerGroup:
          intFrom(v('teamsPerGroup', 'teams_per_group'), fallback: 4),
      isActive: boolFrom(v('isActive', 'is_active'), fallback: true),
      isDefault: boolFrom(v('isDefault', 'is_default'), fallback: false),
      transferStartDate:
          _readDate(v('transferStartDate', 'transfer_start_date')),
      transferEndDate: _readDate(v('transferEndDate', 'transfer_end_date')),
      instagramUrl: nullableTrimmed(v('instagramUrl', 'instagram_url')),
      youtubeUrl: nullableTrimmed(v('youtubeUrl', 'youtube_url')),
      matchPeriodDuration: intFrom(
        v('matchPeriodDuration', 'match_period_duration'),
        fallback: 25,
      ),
    );
  }

  factory Season.fromJson(Map<String, dynamic> json) => Season.fromMap(json);

  Map<String, dynamic> toJson() {
    String? dateOnly(DateTime? d) {
      if (d == null) return null;
      final y = d.year.toString().padLeft(4, '0');
      final m = d.month.toString().padLeft(2, '0');
      final day = d.day.toString().padLeft(2, '0');
      return '$y-$m-$day';
    }

    return {
      'id': id,
      'name': name,
      'subtitle': subtitle,
      'start_date': dateOnly(startDate),
      'end_date': dateOnly(endDate),
      'starting_player_count': startingPlayerCount,
      'sub_player_count': subPlayerCount,
      'city': city,
      'country': country,
      'is_active': isActive,
      'is_default': isDefault,
      'transfer_start_date': dateOnly(transferStartDate),
      'transfer_end_date': dateOnly(transferEndDate),
      'teams_per_group': teamsPerGroup,
      'number_of_groups': numberOfGroups,
      'instagram_url': instagramUrl,
      'youtube_url': youtubeUrl,
      'match_period_duration': matchPeriodDuration,
      'number_of_player_changes': numberOfPlayerChanges,
      'league_id': leagueId.trim().isEmpty ? null : leagueId.trim(),
    };
  }

  Map<String, dynamic> toMap({bool snakeCase = false}) {
    String? dateOnly(DateTime? d) {
      if (d == null) return null;
      final y = d.year.toString().padLeft(4, '0');
      final m = d.month.toString().padLeft(2, '0');
      final day = d.day.toString().padLeft(2, '0');
      return '$y-$m-$day';
    }

    if (!snakeCase) {
      return {
        'id': id,
        'leagueId': leagueId,
        'name': name,
        'subtitle': subtitle,
        'startDate': dateOnly(startDate),
        'endDate': dateOnly(endDate),
        'startingPlayerCount': startingPlayerCount,
        'subPlayerCount': subPlayerCount,
        'city': city,
        'country': country,
        'isActive': isActive,
        'isDefault': isDefault,
        'transferStartDate': transferStartDate?.toIso8601String(),
        'transferEndDate': transferEndDate?.toIso8601String(),
        'youtubeUrl': youtubeUrl,
        'instagramUrl': instagramUrl,
        'matchPeriodDuration': matchPeriodDuration,
        'numberOfGroups': numberOfGroups,
        'numberOfPlayerChanges': numberOfPlayerChanges,
        'teamsPerGroup': teamsPerGroup,
      };
    }
    return toJson();
  }

  static DateTime? _readDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
