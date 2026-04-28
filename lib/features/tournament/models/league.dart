import 'package:cloud_firestore/cloud_firestore.dart';

class League {
  const League({
    required this.id,
    required this.name,
    required this.logoUrl,
    required this.country,
    this.city,
    this.managerFullName,
    this.managerPhoneRaw10,
    this.startDate,
    this.endDate,
    this.season,
    this.isActive = true,
    this.isDefault = false,
    this.isPrivate = false,
    this.accessCode,
    this.transferStartDate,
    this.transferEndDate,
    this.youtubeUrl,
    this.instagramUrl,
    this.matchPeriodDuration = 25,
    this.startingPlayerCount = 11,
    this.subPlayerCount = 7,
    this.numberOfGroups = 1,
    this.groups = const [],
    this.groupCount = 1,
    this.teamsPerGroup = 4,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String logoUrl;
  final String country;
  final String? city;
  final String? managerFullName;
  final String? managerPhoneRaw10;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? season;
  final bool isActive;
  final bool isDefault;
  final bool isPrivate;
  final String? accessCode;
  final DateTime? transferStartDate;
  final DateTime? transferEndDate;
  final String? youtubeUrl;
  final String? instagramUrl;
  final int matchPeriodDuration;
  final int startingPlayerCount;
  final int subPlayerCount;
  final int numberOfGroups;
  final List<String> groups;
  final int groupCount;
  final int teamsPerGroup;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory League.fromMap(Map<String, dynamic> map) {
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

    return League(
      id: (v('id', 'id') as String?) ?? '',
      name: (v('name', 'name') as String?) ?? '',
      logoUrl: (v('logoUrl', 'logo_url') ?? v('logo', 'logo')) as String? ?? '',
      country: (v('country', 'country') as String?) ?? '',
      city: nullableTrimmed(v('city', 'city')),
      managerFullName: () {
        final direct =
            (v('managerFullName', 'manager_full_name') as String?)?.trim() ?? '';
        if (direct.isNotEmpty) return direct;
        final mn = (v('managerName', 'manager_name') as String?)?.trim() ?? '';
        final ms =
            (v('managerSurname', 'manager_surname') as String?)?.trim() ?? '';
        final combined = ('$mn $ms').trim();
        return combined.isEmpty ? null : combined;
      }(),
      managerPhoneRaw10: (v('managerPhoneRaw10', 'manager_phone_raw10') ??
              v('managerPhone', 'manager_phone'))
          as String?,
      startDate: _readDate(v('startDate', 'start_date')),
      endDate: _readDate(v('endDate', 'end_date')),
      season: v('season', 'season') as String?,
      isActive: boolFrom(v('isActive', 'is_active'), fallback: true),
      isDefault: boolFrom(v('isDefault', 'is_default'), fallback: false),
      isPrivate: boolFrom(v('isPrivate', 'is_private'), fallback: false),
      accessCode: nullableTrimmed(v('accessCode', 'access_code')),
      transferStartDate:
          _readDate(v('transferStartDate', 'transfer_start_date')),
      transferEndDate: _readDate(v('transferEndDate', 'transfer_end_date')),
      youtubeUrl: v('youtubeUrl', 'youtube_url') as String?,
      instagramUrl: v('instagramUrl', 'instagram_url') as String?,
      matchPeriodDuration: intFrom(
        v('matchPeriodDuration', 'match_period_duration'),
        fallback: 25,
      ),
      startingPlayerCount: intFrom(
        v('startingPlayerCount', 'starting_player_count'),
        fallback: 11,
      ),
      subPlayerCount: intFrom(
        v('subPlayerCount', 'sub_player_count'),
        fallback: 7,
      ),
      numberOfGroups: intFrom(
        v('numberOfGroups', 'number_of_groups'),
        fallback: 1,
      ),
      groups: (v('groups', 'groups') as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      teamsPerGroup:
          intFrom(v('teamsPerGroup', 'teams_per_group'), fallback: 4),
      createdAt: _readDate(v('createdAt', 'created_at')),
      updatedAt: _readDate(v('updatedAt', 'updated_at')),
    );
  }

  factory League.fromJson(Map<String, dynamic> json) => League.fromMap(json);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'logo_url': logoUrl,
      'access_code': accessCode,
      'is_private': isPrivate,
      'is_active': isActive,
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
        'name': name,
        'logoUrl': logoUrl,
        'country': country,
        'city': city,
        'managerFullName': managerFullName,
        'managerPhoneRaw10': managerPhoneRaw10,
        'startDate': dateOnly(startDate),
        'endDate': dateOnly(endDate),
        'season': season,
        'isActive': isActive,
        'isDefault': isDefault,
        'isPrivate': isPrivate,
        'accessCode': accessCode,
        'transferStartDate': transferStartDate?.toIso8601String(),
        'transferEndDate': transferEndDate?.toIso8601String(),
        'youtubeUrl': youtubeUrl,
        'instagramUrl': instagramUrl,
        'matchPeriodDuration': matchPeriodDuration,
        'startingPlayerCount': startingPlayerCount,
        'subPlayerCount': subPlayerCount,
        'numberOfGroups': numberOfGroups,
        'groupCount': groupCount,
        'teamsPerGroup': teamsPerGroup,
      };
    }
    return toJson();
  }

  static DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
