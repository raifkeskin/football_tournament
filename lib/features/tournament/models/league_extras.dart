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
    this.autoKind,
    this.matchId,
    this.week,
    this.autoData,
  });

  /// Canlı kura haberi ise kuranın kimliği (kart kura görünümüyle çizilir).
  final String? liveDrawId;

  /// Sistemin oluşturduğu haber: 'match_result' (tek maç skor kartı),
  /// 'week_results' (haftanın sonuçları), 'match_preview' / 'day_preview'
  /// (maç günü kartı ve günün programı), 'instagram' (turnuvanın
  /// Instagram gönderisi) veya 'goal_of_week' / 'player_of_week' /
  /// 'team_of_week' (Haftanın Seçimi). null: elle yazılmış haber.
  final String? autoKind;
  final String? matchId;
  final int? week;

  /// Otomatik haberin kart verisi (takımlar, skor, golcüler).
  final Map<String, dynamic>? autoData;

  bool get isMatchResult => autoKind == 'match_result' && autoData != null;
  bool get isWeekResults => autoKind == 'week_results' && autoData != null;

  /// Maç günü haberleri: tek maç kartı ve günün programı.
  bool get isMatchPreview => autoKind == 'match_preview' && autoData != null;
  bool get isDayPreview => autoKind == 'day_preview' && autoData != null;

  /// Haftanın Seçimi: kurucu başkan / bölge sorumlusunun seçtiği haftanın
  /// golü, oyuncusu ya da takımı.
  bool get isWeeklyPick =>
      autoData != null &&
      (autoKind == 'goal_of_week' ||
          autoKind == 'player_of_week' ||
          autoKind == 'team_of_week');

  /// Turnuvanın Instagram hesabından aktarılan gönderi (instagram-sync).
  bool get isInstagram => autoKind == 'instagram';

  /// Gönderinin Instagram adresi.
  String? get igPermalink {
    final u = (autoData?['permalink'] ?? '').toString().trim();
    return u.isEmpty ? null : u;
  }

  /// Video/Reels: kapak gösterilir, oynatma Instagram'da.
  bool get igIsVideo => autoData?['video'] == true;

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
