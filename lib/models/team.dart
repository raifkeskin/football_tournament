import 'package:cloud_firestore/cloud_firestore.dart';

class Team {
  const Team({
    required this.id,
    required this.name,
    required this.logoUrl,
    this.colors,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String logoUrl;
  final Map<String, dynamic>? colors;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Team.fromMap(Map<String, dynamic> map) {
    return Team(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      logoUrl: (map['logoUrl'] ?? map['logo']) as String? ?? '',
      colors: map['colors'] as Map<String, dynamic>?,
      createdAt: _readDate(map['createdAt']),
      updatedAt: _readDate(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'logoUrl': logoUrl,
      'colors': colors,
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
