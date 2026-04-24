class Pitch {
  const Pitch({
    required this.id,
    required this.name,
    required this.city,
    required this.country,
    required this.location,
  });

  final String id;
  final String name;
  final String city;
  final String country;
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
