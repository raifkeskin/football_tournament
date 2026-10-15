import 'package:flutter/material.dart';

/// Sezonun lig formatı (`seasons.league_format`): play-off kupaları, kupaya
/// girmeyen sıraların durumu ve "Bugün bitse" kartı. Boşsa puan tablosu eski
/// görünümünü (ilk 4 / son 4) kullanır.
class LeagueFormat {
  const LeagueFormat({
    this.cups = const [],
    this.restOut = true,
    this.showIfNow = true,
    this.template,
  });

  final List<FormatCup> cups;

  /// Kupaya girmeyen sıralar "Lige veda" (kırmızı) mı, işaretsiz mi.
  final bool restOut;

  /// Puan tablosunun altındaki "Bugün bitse" eşleşme kartı açık mı (sezonun
  /// yarısı oynandıktan sonra görünür).
  final bool showIfNow;

  /// Seçili hazır şablon (düzenlenince null: özel format).
  final String? template;

  static const colors = [
    Color(0xFF10B981),
    Color(0xFF60A5FA),
    Color(0xFFA78BFA),
    Color(0xFFFBBF24),
  ];
  static const outColor = Color(0xFFF87171);

  static LeagueFormat? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final cups = <FormatCup>[
      for (final c in (raw['cups'] as List? ?? const []))
        if (c is Map) FormatCup.fromJson(c),
    ];
    return LeagueFormat(
      cups: cups,
      restOut: (raw['rest'] ?? 'out') == 'out',
      showIfNow: raw['show_if_now'] != false,
      template: raw['template']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'cups': [for (final c in cups) c.toJson()],
    'rest': restOut ? 'out' : 'none',
    'show_if_now': showIfNow,
    'template': ?template,
  };

  LeagueFormat copyWith({
    List<FormatCup>? cups,
    bool? restOut,
    bool? showIfNow,
    String? template,
    bool clearTemplate = false,
  }) => LeagueFormat(
    cups: cups ?? this.cups,
    restOut: restOut ?? this.restOut,
    showIfNow: showIfNow ?? this.showIfNow,
    template: clearTemplate ? null : (template ?? this.template),
  );

  /// Hazır şablonlar (id, ad).
  static const templates = [
    ('none', 'Play-off yok'),
    ('top4', 'İlk 4 Play-Off'),
    ('top4p', 'İlk 4 + Prestij Kupası'),
    ('top8', 'İlk 8 Play-Off'),
  ];

  /// Şablonu [teamCount] takımlı lige uyarlar.
  static LeagueFormat fromTemplate(String id, int teamCount) {
    final n = teamCount < 2 ? 2 : teamCount;
    int clamp(int v) => v > n ? n : v;
    final cups = switch (id) {
      'top4' => [
        FormatCup(name: 'Şampiyonluk Play-Off', from: 1, to: clamp(4)),
      ],
      'top4p' => [
        FormatCup(name: 'Şampiyonluk Play-Off', from: 1, to: clamp(4)),
        if (n >= 6) FormatCup(name: 'Prestij Kupası', from: 5, to: clamp(8)),
      ],
      'top8' => [FormatCup(name: 'Play-Off', from: 1, to: clamp(8))],
      _ => <FormatCup>[],
    };
    return LeagueFormat(cups: cups, restOut: id != 'none', template: id);
  }

  /// Kupadaki hatalar (çakışma, ters aralık, takım sayısını aşma).
  List<String> errorsOf(int i, int teamCount) {
    final c = cups[i];
    final errs = <String>[];
    if (c.to < c.from) {
      errs.add('Bitiş sırası başlangıçtan küçük olamaz.');
    } else if (c.size < 2) {
      errs.add('Kupaya en az 2 takım katılmalı.');
    }
    for (var j = 0; j < cups.length; j++) {
      if (j == i) continue;
      final o = cups[j];
      final lo = c.from > o.from ? c.from : o.from;
      final hi = c.to < o.to ? c.to : o.to;
      if (lo <= hi) {
        final what = lo == hi ? '$lo. sıra' : '$lo–$hi. sıralar';
        errs.add('$what "${o.name}" ile çakışıyor.');
      }
    }
    if (c.to > teamCount) errs.add('Ligde $teamCount takım var.');
    return errs;
  }

  bool isValid(int teamCount) {
    for (var i = 0; i < cups.length; i++) {
      if (errorsOf(i, teamCount).isNotEmpty) return false;
    }
    return true;
  }

  /// Sıranın bölgesi (1'den başlar): kupa ya da "Lige veda"; yoksa null.
  ({String name, Color color})? zoneOf(int rank, int teamCount) {
    for (var i = 0; i < cups.length; i++) {
      final c = cups[i];
      if (errorsOf(i, teamCount).isNotEmpty) continue;
      if (rank >= c.from && rank <= c.to) {
        return (name: c.name, color: colors[i % colors.length]);
      }
    }
    if (restOut && rank <= teamCount) {
      return (name: 'Lige veda', color: outColor);
    }
    return null;
  }

  /// Kupaya girmeyen sıralar.
  List<int> restRanks(int teamCount) {
    final covered = <int>{};
    for (var i = 0; i < cups.length; i++) {
      if (errorsOf(i, teamCount).isNotEmpty) continue;
      for (var r = cups[i].from; r <= cups[i].to; r++) {
        covered.add(r);
      }
    }
    return [
      for (var r = 1; r <= teamCount; r++)
        if (!covered.contains(r)) r,
    ];
  }
}

/// Bir play-off kupası: [from]–[to] sıraları katılır; eşleşmeler en iyi –
/// en kötü kuralıyla, eksik takım varsa üst sıralar bay geçer.
class FormatCup {
  const FormatCup({
    required this.name,
    required this.from,
    required this.to,
    this.legs = 1,
    this.third = false,
  });

  final String name;
  final int from;
  final int to;

  /// 1: tek maç, 2: rövanşlı.
  final int legs;

  /// 3.lük maçı oynanır mı.
  final bool third;

  int get size => to - from + 1;

  factory FormatCup.fromJson(Map raw) {
    int read(dynamic v, int fb) =>
        v is num ? v.toInt() : int.tryParse('$v') ?? fb;
    return FormatCup(
      name: (raw['name'] ?? 'Kupa').toString(),
      from: read(raw['from'], 1),
      to: read(raw['to'], 4),
      legs: read(raw['legs'], 1) == 2 ? 2 : 1,
      third: raw['third'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'from': from,
    'to': to,
    'legs': legs,
    'third': third,
  };

  FormatCup copyWith({
    String? name,
    int? from,
    int? to,
    int? legs,
    bool? third,
  }) => FormatCup(
    name: name ?? this.name,
    from: from ?? this.from,
    to: to ?? this.to,
    legs: legs ?? this.legs,
    third: third ?? this.third,
  );

  /// Ağaç boyu (2'nin kuvveti).
  int get bracketSize {
    var s = 2;
    while (s < size) {
      s *= 2;
    }
    return s;
  }

  /// İlk turda bay geçen sıra sayısı.
  int get byes => bracketSize - size;

  /// Tur adları, ilk turdan finale.
  List<String> get roundNames => [
    for (var s = bracketSize; s >= 2; s ~/= 2) roundName(s),
  ];

  static String roundName(int teams) => switch (teams) {
    2 => 'Final',
    4 => 'Yarı Final',
    8 => 'Çeyrek Final',
    _ => 'Son $teams',
  };

  /// Standart tohumlama: 4 → [1,4,2,3]; 8 → [1,8,4,5,2,7,3,6].
  static List<int> seedOrder(int size) {
    var list = [1, 2];
    while (list.length < size) {
      final m = list.length * 2 + 1;
      list = [
        for (final s in list) ...[s, m - s],
      ];
    }
    return list;
  }

  /// İlk tur eşleşmeleri (lig sıraları); bay geçen tarafta null.
  List<(int?, int?)> firstRound() {
    final order = seedOrder(bracketSize);
    int? rank(int seed) => seed <= size ? from + seed - 1 : null;
    return [
      for (var i = 0; i < order.length; i += 2)
        (rank(order[i]), rank(order[i + 1])),
    ];
  }
}
