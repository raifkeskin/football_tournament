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
    this.imageUrl,
    this.likeCount = 0,
    this.leagueName = '',
    this.leagueLogoUrl,
    this.leagueIsPrivate = false,
    this.likedByMe = false,
    this.publishUntil,
  });

  final String id;
  final String tournamentId;
  final String content;
  final bool isPublished;
  final DateTime? createdAt;
  final String? imageUrl;
  final int likeCount;

  /// Akış kartının başlığı için (`leagues` ile birlikte okunduğunda dolu).
  final String leagueName;
  final String? leagueLogoUrl;
  final bool leagueIsPrivate;

  /// Giriş yapmış kullanıcı bu haberi beğenmiş mi (akışla aynı sorguda okunur,
  /// böylece [likeCount] ile tutarlıdır).
  final bool likedByMe;

  /// Yayın bitiş zamanı; geçince haber herkese kapanır (null: süresiz).
  final DateTime? publishUntil;

  bool get isExpired =>
      publishUntil != null && !publishUntil!.isAfter(DateTime.now());

  /// Akışta görünüyor mu: yayında ve süresi dolmamış.
  bool get isLive => isPublished && !isExpired;
}
