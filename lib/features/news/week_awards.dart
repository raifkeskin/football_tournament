import 'package:flutter/material.dart';

import '../../core/utils/team_name.dart';

/// Haftanın Enleri bülteni (news.auto_kind = 'week_awards'): haftanın 11'i
/// ve sorumlunun o hafta seçtiği enler. Veri haberin auto_data'sında.

/// Bültendeki bir ödül türü; her birinin kendi rengi ve simgesi var.
enum AwardKind { player, keeper, fair, goal, match, team }

extension AwardKindX on AwardKind {
  String get key => name;

  /// "Oyuncusu" (kartta "HAFTANIN" altında).
  String get title => switch (this) {
    AwardKind.player => 'Oyuncusu',
    AwardKind.keeper => 'Kalecisi',
    AwardKind.fair => 'Centilmeni',
    AwardKind.goal => 'Golü',
    AwardKind.match => 'Maçı',
    AwardKind.team => 'Takımı',
  };

  String get full => 'Haftanın $title';

  Color get color => switch (this) {
    AwardKind.player => const Color(0xFFE2B845),
    AwardKind.keeper => const Color(0xFF38BDF8),
    AwardKind.fair => const Color(0xFFA7F3D0),
    AwardKind.goal => const Color(0xFFF87171),
    AwardKind.match => const Color(0xFFFB923C),
    AwardKind.team => const Color(0xFF10B981),
  };

  IconData get icon => switch (this) {
    AwardKind.player => Icons.star_rounded,
    AwardKind.keeper => Icons.sports_handball_rounded,
    AwardKind.fair => Icons.handshake_rounded,
    AwardKind.goal => Icons.sports_soccer_rounded,
    AwardKind.match => Icons.local_fire_department_rounded,
    AwardKind.team => Icons.shield_rounded,
  };

  /// Kişiye verilen ödül (maç ve takım değil).
  bool get personal =>
      this == AwardKind.player ||
      this == AwardKind.keeper ||
      this == AwardKind.fair ||
      this == AwardKind.goal;

  static AwardKind? of(String? key) =>
      AwardKind.values.where((k) => k.key == key).firstOrNull;
}

/// Bülten kartındaki takım.
class AwardTeam {
  const AwardTeam({
    required this.id,
    required this.name,
    this.logo = '',
    this.color,
  });

  factory AwardTeam.fromJson(Object? raw) {
    final m = raw is Map ? raw : const {};
    return AwardTeam(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      logo: (m['logo'] ?? '').toString().trim(),
      color: m['color']?.toString(),
    );
  }

  final String id;
  final String name;
  final String logo;
  final String? color;

  /// "Masterlar" eki olmadan.
  String get short => shortTeamName(name);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'logo': logo,
    'color': color,
  };
}

/// Bülten kartındaki oyuncu.
class AwardPerson {
  const AwardPerson({required this.id, required this.name, this.photo = ''});

  factory AwardPerson.fromJson(Object? raw) {
    final m = raw is Map ? raw : const {};
    return AwardPerson(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString().trim(),
      photo: (m['photo'] ?? '').toString().trim(),
    );
  }

  final String id;
  final String name;
  final String photo;

  /// Avatarda fotoğraf yoksa baş harfler.
  String get initials {
    final w = name.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (w.isEmpty) return '?';
    final s = w.length == 1
        ? w.first.characters.take(2).toString()
        : '${w.first.characters.first}${w.last.characters.first}';
    return s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'photo': photo};
}

/// Haftanın 11'inde bir yer: dizilişteki sırasıyla (0 kaleci).
class ElevenSlot {
  const ElevenSlot({
    required this.person,
    required this.team,
    this.rating,
    this.number = '',
  });

  factory ElevenSlot.fromJson(Map m) => ElevenSlot(
    person: AwardPerson.fromJson(m['player']),
    team: AwardTeam.fromJson(m['team']),
    rating: (m['rating'] as num?)?.toDouble(),
    number: (m['number'] ?? '').toString(),
  );

  final AwardPerson person;
  final AwardTeam team;
  final double? rating;
  final String number;

  Map<String, dynamic> toJson() => {
    'player': person.toJson(),
    'team': team.toJson(),
    'rating': rating,
    'number': number,
  };
}

/// Bir en: kişi (maç ve takım ödülünde yok), takım, maç skoru, seçilen
/// fotoğraf ve kartta yazan kısa bilgiler ("3 GOL", "4-4").
class WeekAward {
  const WeekAward({
    required this.kind,
    required this.team,
    this.person,
    this.photo = '',
    this.stats = const [],
    this.rating,
    this.home,
    this.away,
    this.hs,
    this.as,
    this.matchId,
    this.clip,
  });

  factory WeekAward.fromJson(Map m) {
    final match = m['match'] is Map ? m['match'] as Map : null;
    return WeekAward(
      kind: AwardKindX.of(m['kind']?.toString()) ?? AwardKind.player,
      team: AwardTeam.fromJson(m['team']),
      person: m['player'] is Map ? AwardPerson.fromJson(m['player']) : null,
      photo: (m['photo'] ?? '').toString().trim(),
      stats: [for (final s in (m['stats'] as List? ?? const [])) s.toString()],
      rating: (m['rating'] as num?)?.toDouble(),
      home: match == null ? null : AwardTeam.fromJson(match['home']),
      away: match == null ? null : AwardTeam.fromJson(match['away']),
      hs: (match?['hs'] as num?)?.toInt(),
      as: (match?['as'] as num?)?.toInt(),
      matchId: match?['id']?.toString(),
      clip: m['clip'] is Map ? Map<String, dynamic>.from(m['clip']) : null,
    );
  }

  final AwardKind kind;
  final AwardTeam team;
  final AwardPerson? person;

  /// Kartta kullanılan fotoğraf (sorumlunun seçtiği ya da profil); boşsa
  /// baş harfler / takım logosu.
  final String photo;
  final List<String> stats;
  final double? rating;
  final AwardTeam? home;
  final AwardTeam? away;
  final int? hs;
  final int? as;
  final String? matchId;

  /// Haftanın golünün kesiti: video_id, start, end, clip_url, story_url.
  final Map<String, dynamic>? clip;

  String get score => hs == null ? '' : '$hs-$as';

  Map<String, dynamic> toJson() => {
    'kind': kind.key,
    'team': team.toJson(),
    if (person != null) 'player': person!.toJson(),
    'photo': photo,
    'stats': stats,
    'rating': rating,
    if (home != null)
      'match': {
        'id': matchId,
        'home': home!.toJson(),
        'away': away!.toJson(),
        'hs': hs,
        'as': as,
      },
    if (clip != null) 'clip': clip,
  };
}

/// Bültenin tamamı.
class WeekAwards {
  const WeekAwards({
    required this.week,
    required this.leagueName,
    required this.leagueLogo,
    required this.formation,
    required this.eleven,
    required this.awards,
    this.instagramUrl = '',
    this.goalVideoUrl = '',
  });

  factory WeekAwards.fromJson(Map d) => WeekAwards(
    week: (d['week'] as num?)?.toInt() ?? 0,
    leagueName: (d['league_name'] ?? '').toString(),
    leagueLogo: (d['league_logo'] ?? '').toString().trim(),
    formation: (d['formation'] ?? '').toString(),
    eleven: [
      for (final s in (d['eleven'] as List? ?? const []))
        if (s is Map) ElevenSlot.fromJson(s),
    ],
    awards: [
      for (final a in (d['awards'] as List? ?? const []))
        if (a is Map) WeekAward.fromJson(a),
    ],
    instagramUrl: (d['instagram_url'] ?? '').toString().trim(),
    goalVideoUrl: (d['goal_video_url'] ?? '').toString().trim(),
  );

  final int week;
  final String leagueName;
  final String leagueLogo;

  /// "4-3-3"; 11'i yoksa boş.
  final String formation;
  final List<ElevenSlot> eleven;
  final List<WeekAward> awards;

  /// Yayından sonra eklenen Instagram gönderisi / Reels (bültenin son sayfası).
  final String instagramUrl;

  /// Haftanın Golü hikâye videosu (2 sn kart + gol); Mac işi üretir.
  final String goalVideoUrl;

  bool get hasEleven =>
      eleven.isNotEmpty &&
      formationCounts(formation).fold<int>(0, (a, b) => a + b) + 1 ==
          eleven.length;

  Map<String, dynamic> toJson() => {
    'week': week,
    'league_name': leagueName,
    'league_logo': leagueLogo,
    'formation': formation,
    'eleven': [for (final s in eleven) s.toJson()],
    'awards': [for (final a in awards) a.toJson()],
  };
}

/// "4-2-3-1" → [4, 2, 3, 1].
List<int> formationCounts(String f) => [
  for (final p in f.split('-'))
    if (int.tryParse(p.trim()) case final n? when n > 0) n,
];

/// Saha oyuncusu sayısına göre seçilebilen dizilişler (ilki varsayılan).
List<String> formationOptions(int outfield) => switch (outfield) {
  10 => ['4-3-3', '4-4-2', '4-2-3-1', '3-5-2', '3-4-3', '5-3-2', '4-1-4-1'],
  9 => ['3-4-2', '4-3-2', '3-3-3', '4-4-1'],
  8 => ['3-3-2', '3-4-1', '4-3-1', '2-4-2'],
  7 => ['3-3-1', '2-3-2', '3-2-2', '2-4-1'],
  6 => ['2-3-1', '3-2-1', '2-2-2', '3-1-2'],
  5 => ['2-2-1', '1-3-1', '3-1-1', '2-1-2'],
  4 => ['2-1-1', '1-2-1', '2-2'],
  _ => ['$outfield'],
};

/// Dizilişteki sıranın hattı: 0 kaleci, 1 defans, 2 orta saha, 3 forvet.
int formationLineOf(String formation, int slot) {
  if (slot == 0) return 0;
  final c = formationCounts(formation);
  var cum = 0;
  for (var i = 0; i < c.length; i++) {
    cum += c[i];
    if (slot <= cum) {
      if (i == 0) return c.length == 1 ? 2 : 1;
      return i == c.length - 1 ? 3 : 2;
    }
  }
  return 2;
}
