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
    this.managerName,
    this.managerSurname,
    this.managerPhoneRaw10,
    this.startDate,
    this.endDate,
    this.season,
    this.isActive = true,
    this.isDefault = false,
    this.youtubeUrl,
    this.twitterUrl,
    this.instagramUrl,
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
  final String? managerName;
  final String? managerSurname;
  final String? managerPhoneRaw10;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? season;
  final bool isActive;
  final bool isDefault;
  final String? youtubeUrl;
  final String? twitterUrl;
  final String? instagramUrl;
  final int numberOfGroups;
  final List<String> groups;
  final int groupCount;
  final int teamsPerGroup;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory League.fromMap(Map<String, dynamic> map) {
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
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      subtitle: (map['subtitle'] as String?)?.trim().isEmpty ?? true
          ? null
          : (map['subtitle'] as String?)?.trim(),
      logoUrl: (map['logoUrl'] ?? map['logo']) as String? ?? '',
      country: map['country'] as String? ?? '',
      managerName: (map['managerName'] as String?)?.trim().isEmpty ?? true
          ? null
          : (map['managerName'] as String?)?.trim(),
      managerSurname: (map['managerSurname'] as String?)?.trim().isEmpty ?? true
          ? null
          : (map['managerSurname'] as String?)?.trim(),
      managerPhoneRaw10:
          (map['managerPhoneRaw10'] ?? map['managerPhone']) as String?,
      startDate: _readDate(map['startDate']),
      endDate: _readDate(map['endDate']),
      season: map['season'] as String?,
      isActive: boolFrom(map['isActive'], fallback: true),
      isDefault: boolFrom(map['isDefault'], fallback: false),
      youtubeUrl: map['youtubeUrl'] as String?,
      twitterUrl: map['twitterUrl'] as String?,
      instagramUrl: map['instagramUrl'] as String?,
      numberOfGroups: intFrom(map['numberOfGroups'], fallback: intFrom(map['groupCount'], fallback: 1)),
      groups: (map['groups'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      groupCount: intFrom(map['groupCount'], fallback: 1),
      teamsPerGroup: intFrom(map['teamsPerGroup'], fallback: 4),
      createdAt: _readDate(map['createdAt']),
      updatedAt: _readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'subtitle': subtitle,
      'logoUrl': logoUrl,
      'country': country,
      'managerName': managerName,
      'managerSurname': managerSurname,
      'managerPhoneRaw10': managerPhoneRaw10,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'season': season,
      'isActive': isActive,
      'isDefault': isDefault,
      'youtubeUrl': youtubeUrl,
      'twitterUrl': twitterUrl,
      'instagramUrl': instagramUrl,
      'numberOfGroups': numberOfGroups,
      'groups': groups,
      'groupCount': groupCount,
      'teamsPerGroup': teamsPerGroup,
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
