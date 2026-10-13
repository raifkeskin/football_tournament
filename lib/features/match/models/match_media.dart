/// Maç yayın linki (YouTube); skorun altında gösterilir.
const kMediaLiveLink = 'Maç Yayın Linki';

/// Turnuvanın kendi albümü (Drive / Google Fotoğraflar); dışarıda açılır.
const kMediaAlbumLink = 'Fotoğraf Albümü';

class MatchMediaModel {
  final String id;
  final String matchId;
  final String? teamId;
  final String mediaType;
  final String url;
  final String? description;
  final DateTime? createdAt;

  /// Fotoğraf mı (link türleri hariç)? Maç başı fotoğraf sınırına sayılır.
  bool get isPhoto =>
      mediaType != kMediaLiveLink && mediaType != kMediaAlbumLink;

  MatchMediaModel({
    required this.id,
    required this.matchId,
    this.teamId,
    required this.mediaType,
    required this.url,
    this.description,
    this.createdAt,
  });

  factory MatchMediaModel.fromMap(Map<String, dynamic> map, String id) {
    dynamic v(String camel, String snake) => map[camel] ?? map[snake];

    DateTime? readDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return MatchMediaModel(
      id: id,
      matchId: (v('matchId', 'match_id') ?? '').toString(),
      teamId: (v('teamId', 'team_id') ?? '').toString().trim().isEmpty
          ? null
          : (v('teamId', 'team_id') ?? '').toString().trim(),
      mediaType: (v('mediaType', 'media_type') ?? '').toString(),
      url: (v('url', 'url') ?? '').toString(),
      description:
          (v('description', 'description') ?? '').toString().trim().isEmpty
          ? null
          : (v('description', 'description') ?? '').toString().trim(),
      createdAt: readDate(v('createdAt', 'created_at')),
    );
  }

  Map<String, dynamic> toMap({bool snakeCase = false}) {
    if (!snakeCase) {
      return {
        'matchId': matchId,
        'teamId': teamId,
        'mediaType': mediaType,
        'url': url,
        'description': description,
        'createdAt': createdAt?.toIso8601String(),
      };
    }
    return {
      if (id.trim().isNotEmpty) 'id': id.trim(),
      'match_id': matchId,
      'team_id': teamId,
      'media_type': mediaType,
      'url': url,
      'description': description,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
