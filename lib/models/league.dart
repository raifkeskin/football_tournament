/// Çoklu lig desteği için temel League modeli.
library;
import 'package:cloud_firestore/cloud_firestore.dart';

class League {
  const League({
    required this.id,
    required this.name,
    this.subtitle,
    required this.logoUrl,
    required this.country,
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
    this.numberOfGroups = 1,
    this.groups = const [],
    this.groupCount = 1,
    this.teamsPerGroup = 4,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? subtitle;
  final String logoUrl;
  final String country;
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

    return League(
      id: (v('id', 'id') as String?) ?? '',
      name: (v('name', 'name') as String?) ?? '',
      subtitle: (v('subtitle', 'subtitle') as String?)?.trim().isEmpty ?? true
          ? null
          : (v('subtitle', 'subtitle') as String?)?.trim(),
      logoUrl: (v('logoUrl', 'logo_url') ?? v('logo', 'logo')) as String? ?? '',
      country: (v('country', 'country') as String?) ?? '',
      managerFullName: () {
        final direct = (v('managerFullName', 'manager_full_name') as String?)?.trim() ?? '';
        if (direct.isNotEmpty) return direct;
        final mn = (v('managerName', 'manager_name') as String?)?.trim() ?? '';
        final ms = (v('managerSurname', 'manager_surname') as String?)?.trim() ?? '';
        final combined = ('$mn $ms').trim();
        return combined.isEmpty ? null : combined;
      }(),
      managerPhoneRaw10:
          (v('managerPhoneRaw10', 'manager_phone_raw10') ?? v('managerPhone', 'manager_phone'))
              as String?,
      startDate: _readDate(v('startDate', 'start_date')),
      endDate: _readDate(v('endDate', 'end_date')),
      season: v('season', 'season') as String?,
      isActive: boolFrom(v('isActive', 'is_active'), fallback: true),
      isDefault: boolFrom(v('isDefault', 'is_default'), fallback: false),
      isPrivate: boolFrom(v('isPrivate', 'is_private'), fallback: false),
      accessCode: (v('accessCode', 'access_code') as String?)?.trim().isEmpty ?? true
          ? null
          : (v('accessCode', 'access_code') as String?)?.trim(),
      transferStartDate: _readDate(v('transferStartDate', 'transfer_start_date')),
      transferEndDate: _readDate(v('transferEndDate', 'transfer_end_date')),
      youtubeUrl: v('youtubeUrl', 'youtube_url') as String?,
      instagramUrl: v('instagramUrl', 'instagram_url') as String?,
      matchPeriodDuration: intFrom(
        v('matchPeriodDuration', 'match_period_duration'),
        fallback: 25,
      ),
      numberOfGroups: intFrom(
        v('numberOfGroups', 'number_of_groups'),
        fallback: intFrom(v('groupCount', 'group_count'), fallback: 1),
      ),
      groups:
          (v('groups', 'groups') as List?)?.map((e) => e.toString()).toList() ?? const [],
      groupCount: intFrom(v('groupCount', 'group_count'), fallback: 1),
      teamsPerGroup: intFrom(v('teamsPerGroup', 'teams_per_group'), fallback: 4),
      createdAt: _readDate(v('createdAt', 'created_at')),
      updatedAt: _readDate(v('updatedAt', 'updated_at')),
    );
  }

  League copyWith({
    String? id,
    String? name,
    String? subtitle,
    String? logoUrl,
    String? country,
    String? managerFullName,
    String? managerPhoneRaw10,
    DateTime? startDate,
    DateTime? endDate,
    String? season,
    bool? isActive,
    bool? isDefault,
    bool? isPrivate,
    String? accessCode,
    DateTime? transferStartDate,
    DateTime? transferEndDate,
    String? youtubeUrl,
    String? instagramUrl,
    int? matchPeriodDuration,
    int? numberOfGroups,
    List<String>? groups,
    int? groupCount,
    int? teamsPerGroup,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return League(
      id: id ?? this.id,
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      logoUrl: logoUrl ?? this.logoUrl,
      country: country ?? this.country,
      managerFullName: managerFullName ?? this.managerFullName,
      managerPhoneRaw10: managerPhoneRaw10 ?? this.managerPhoneRaw10,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      season: season ?? this.season,
      isActive: isActive ?? this.isActive,
      isDefault: isDefault ?? this.isDefault,
      isPrivate: isPrivate ?? this.isPrivate,
      accessCode: accessCode ?? this.accessCode,
      transferStartDate: transferStartDate ?? this.transferStartDate,
      transferEndDate: transferEndDate ?? this.transferEndDate,
      youtubeUrl: youtubeUrl ?? this.youtubeUrl,
      instagramUrl: instagramUrl ?? this.instagramUrl,
      matchPeriodDuration: matchPeriodDuration ?? this.matchPeriodDuration,
      numberOfGroups: numberOfGroups ?? this.numberOfGroups,
      groups: groups ?? this.groups,
      groupCount: groupCount ?? this.groupCount,
      teamsPerGroup: teamsPerGroup ?? this.teamsPerGroup,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap({bool snakeCase = false}) {
    if (!snakeCase) {
      return {
        'id': id,
        'name': name,
        'subtitle': subtitle,
        'logoUrl': logoUrl,
        'country': country,
        'managerFullName': managerFullName,
        'managerPhoneRaw10': managerPhoneRaw10,
        'startDate': startDate?.toIso8601String(),
        'endDate': endDate?.toIso8601String(),
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
        'numberOfGroups': numberOfGroups,
        'groups': groups,
        'groupCount': groupCount,
        'teamsPerGroup': teamsPerGroup,
      };
    }
    return {
      'id': id,
      'name': name,
      'subtitle': subtitle,
      'logo_url': logoUrl,
      'country': country,
      'manager_full_name': managerFullName,
      'manager_phone_raw10': managerPhoneRaw10,
      'start_date': startDate?.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'season': season,
      'is_active': isActive,
      'is_default': isDefault,
      'is_private': isPrivate,
      'access_code': accessCode,
      'transfer_start_date': transferStartDate?.toIso8601String(),
      'transfer_end_date': transferEndDate?.toIso8601String(),
      'youtube_url': youtubeUrl,
      'instagram_url': instagramUrl,
      'match_period_duration': matchPeriodDuration,
      'number_of_groups': numberOfGroups,
      'groups': groups,
      'group_count': groupCount,
      'teams_per_group': teamsPerGroup,
    };
  }

  static DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
