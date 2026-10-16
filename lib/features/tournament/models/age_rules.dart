/// Sezonun yaş ve kontenjan kuralları (`seasons.age_rules`).
///
/// Örnek 40+: oyuncular 1986 ve öncesi, kaleci 1991 ve öncesi; kaleci
/// dışında kadroda 1988 doğumlu en fazla 4, 1989 doğumlu en fazla 2
/// kontenjan oyuncusu; maç günü esamede toplam en fazla 3, sahada aynı anda
/// en fazla 2.
class AgeRules {
  const AgeRules({
    this.playerMaxYear,
    this.gkMaxYear,
    this.quotas = const [],
    this.matchMax,
    this.matchFieldMax,
  });

  /// Oyuncular için en geç doğum yılı (null: sınır yok).
  final int? playerMaxYear;

  /// Kaleci için en geç doğum yılı (null: oyuncu sınırı geçerli).
  final int? gkMaxYear;
  final List<AgeQuota> quotas;

  /// Maç günü esamede (ilk 11 + yedek) toplam en fazla kontenjanlı oyuncu;
  /// kaleci kontenjanı hariç (null: sınır yok).
  final int? matchMax;

  /// Sahada aynı anda toplam en fazla kontenjanlı oyuncu; kaleci kontenjanı
  /// hariç (null: sınır yok).
  final int? matchFieldMax;

  bool get isEmpty =>
      playerMaxYear == null &&
      gkMaxYear == null &&
      quotas.isEmpty &&
      matchMax == null &&
      matchFieldMax == null;

  bool get hasMatchLimits => matchMax != null || matchFieldMax != null;

  /// "1988-05-12" / "12.05.1988" gibi tarihten yıl.
  static int? birthYearOf(String? birthDate) => int.tryParse(
    RegExp(r'(\d{4})').firstMatch(birthDate ?? '')?.group(1) ?? '',
  );

  /// Maç günü sınırlarına sayılan (kaleci dışı) kontenjan oyuncusu mu.
  bool isMatchQuota({required int? birthYear, required bool isGk}) {
    if (isGk) return false;
    return check(birthYear: birthYear, isGk: false).status == AgeStatus.quota;
  }

  factory AgeRules.fromJson(Object? raw) {
    if (raw is! Map) return const AgeRules();
    int? year(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    return AgeRules(
      playerMaxYear: year(raw['player_max_year']),
      gkMaxYear: year(raw['gk_max_year']),
      quotas: [
        for (final q in (raw['quotas'] as List? ?? const []))
          if (q is Map) AgeQuota.fromJson(q),
      ],
      matchMax: year(raw['match_max']),
      matchFieldMax: year(raw['match_field_max']),
    );
  }

  Map<String, dynamic>? toJson() => isEmpty
      ? null
      : {
          'player_max_year': ?playerMaxYear,
          'gk_max_year': ?gkMaxYear,
          'quotas': [for (final q in quotas) q.toJson()],
          'match_max': ?matchMax,
          'match_field_max': ?matchFieldMax,
        };

  /// Oyuncunun kurala göre durumu. Doğum yılı bilinmiyorsa [AgeStatus.ok].
  AgeCheck check({required int? birthYear, required bool isGk}) {
    if (birthYear == null || isEmpty) return const AgeCheck(AgeStatus.ok);
    final limit = isGk ? (gkMaxYear ?? playerMaxYear) : playerMaxYear;
    if (limit == null || birthYear <= limit) {
      return const AgeCheck(AgeStatus.ok);
    }
    for (var i = 0; i < quotas.length; i++) {
      final q = quotas[i];
      if (q.gk == isGk && q.years.contains(birthYear)) {
        return AgeCheck(AgeStatus.quota, i);
      }
    }
    return const AgeCheck(AgeStatus.violation);
  }

  /// Kısa açıklama: "Oyuncu ≤1986 · Kaleci ≤1991 · 1 kontenjan".
  String get summary {
    if (isEmpty) return 'Kural yok';
    return [
      if (playerMaxYear != null) 'Oyuncu $playerMaxYear ve öncesi',
      if (gkMaxYear != null) 'Kaleci $gkMaxYear ve öncesi',
      if (quotas.isNotEmpty) '${quotas.length} kontenjan',
      if (matchMax != null) 'esamede en fazla $matchMax',
      if (matchFieldMax != null) 'sahada en fazla $matchFieldMax',
    ].join(' · ');
  }
}

class AgeQuota {
  const AgeQuota({
    required this.years,
    required this.max,
    this.fieldMax,
    this.gk = false,
  });

  /// Kontenjana giren doğum yılları (ör. 1988, 1989).
  final List<int> years;

  /// Kadroda en fazla.
  final int max;

  /// Eski kayıtlar için: kontenjana özel saha sınırı. Yeni formda yerini
  /// sezon geneli [AgeRules.matchFieldMax] aldı; kayıtta korunur.
  final int? fieldMax;

  /// true: kaleci kontenjanı; false: kaleci dışındaki oyuncular.
  final bool gk;

  factory AgeQuota.fromJson(Map raw) {
    int? n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    return AgeQuota(
      years: [
        for (final y in (raw['years'] as List? ?? const []))
          if (n(y) != null) n(y)!,
      ]..sort(),
      max: n(raw['max']) ?? 1,
      fieldMax: n(raw['field_max']),
      gk: raw['gk'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'years': years,
    'max': max,
    'field_max': ?fieldMax,
    'gk': gk,
  };

  /// "1988–1989" ya da "1988, 1990".
  String get yearsLabel {
    if (years.isEmpty) return '-';
    final consecutive = years.last - years.first == years.length - 1;
    if (years.length > 1 && consecutive) return '${years.first}–${years.last}';
    return years.join(', ');
  }

  String get label => '${gk ? 'Kaleci ' : ''}$yearsLabel';
}

enum AgeStatus { ok, quota, violation }

class AgeCheck {
  const AgeCheck(this.status, [this.quotaIndex]);

  final AgeStatus status;

  /// [AgeStatus.quota] ise hangi kontenjan.
  final int? quotaIndex;
}
