class Pitch {
  const Pitch({
    required this.id,
    required this.name,
    required this.nameKey,
    required this.location,
  });

  final String id;
  final String name;
  final String nameKey;
  final String location;
}

class NewsItem {
  const NewsItem({
    required this.id,
    required this.tournamentId,
    required this.content,
    required this.isPublished,
    required this.createdAt,
  });

  final String id;
  final String tournamentId;
  final String content;
  final bool isPublished;
  final DateTime? createdAt;
}
