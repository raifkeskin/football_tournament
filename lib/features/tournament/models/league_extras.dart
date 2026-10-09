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
    this.seasonId = '',
    required this.content,
    required this.isPublished,
    required this.createdAt,
    this.imageUrl,
    this.imageUrls = const [],
    this.likeCount = 0,
    this.leagueName = '',
    this.leagueLogoUrl,
    this.leagueIsPrivate = false,
    this.likedByMe = false,
    this.publishUntil,
    this.regionId,
    this.regionName = '',
    this.liveDrawId,
  });

  /// Canlı kura haberi ise kuranın kimliği (kart kura görünümüyle çizilir).
  final String? liveDrawId;

  final String id;
  final String tournamentId;

  /// Haber sezona bağlıdır; [tournamentId] sezondan türetilir.
  final String seasonId;
  final String content;
  final bool isPublished;
  final DateTime? createdAt;
  final String? imageUrl;

  /// Haberin fotoğrafları (en fazla 5; ilki kapak = [imageUrl]).
  final List<String> imageUrls;
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

  /// İsteğe bağlı bölge (ör. İstanbul (Avrupa)); null: tüm turnuva.
  final String? regionId;

  /// Akışta bölge etiketi (`season_regions` ile okunduğunda dolu).
  final String regionName;

  bool get isExpired =>
      publishUntil != null && !publishUntil!.isAfter(DateTime.now());

  /// Akışta görünüyor mu: yayında ve süresi dolmamış.
  bool get isLive => isPublished && !isExpired;
}
