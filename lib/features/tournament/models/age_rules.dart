/// Sezonun yaş ve kontenjan kuralları (`seasons.age_rules`).
///
/// Örnek 40+: oyuncular 1986 ve öncesi, kaleci 1991 ve öncesi; kaleci
/// dışında 1988–1989 doğumlu en fazla 3 kontenjan oyuncusu (sahada aynı anda
/// en fazla 2).
class AgeRules {
  const AgeRules({this.playerMaxYear, this.gkMaxYear, this.quotas = const []});

  /// Oyuncular için en geç doğum yılı (null: sınır yok).
  final int? playerMaxYear;

  /// Kaleci için en geç doğum yılı (null: oyuncu sınırı geçerli).
  final int? gkMaxYear;
  final List<AgeQuota> quotas;

  bool get isEmpty =>
      playerMaxYear == null && gkMaxYear == null && quotas.isEmpty;

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
    );
  }

  Map<String, dynamic>? toJson() => isEmpty
      ? null
      : {
          'player_max_year': ?playerMaxYear,
          'gk_max_year': ?gkMaxYear,
          'quotas': [for (final q in quotas) q.toJson()],
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

  /// Sahada aynı anda en fazla (null: sınır yok).
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
