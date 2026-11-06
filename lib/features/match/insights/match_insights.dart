import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/services/service_locator.dart';
import '../models/match.dart';

/// Kadro/Diziliş olay ikonları, futbolcu puanı ve "Olay ekle" (yeni
/// özellik): admin ve kurucu başkan her zaman, diğerleri ayar açıksa görür.
bool matchInsightsVisible(BuildContext context) {
  try {
    final s = AppSession.of(context).value;
    if (s.isAdmin || s.isLeagueOwner) return true;
  } catch (_) {}
  return AppSettings.matchInsightsEnabled.value;
}

// ------------------------------------------------------------------ kurallar

/// Sezonun puanlama kuralları (`seasons.player_rating`). Kayıtta olmayan
/// değerler varsayılanlarla tamamlanır.
@immutable
class RatingRules {
  const RatingRules({required this.enabled, required this.values});

  final bool enabled;
  final Map<String, double> values;

  /// Otomatik kurallar: anahtar, ekrandaki ad, varsayılan değer.
  static const auto = <(String, String, double)>[
    ('base', 'Başlangıç puanı', 7.0),
    ('goal', 'Gol', 1.0),
    ('pen_goal', 'Penaltı golü', 0.7),
    ('assist', 'Asist', 0.5),
    ('win', 'Galibiyet', 0.3),
    ('loss', 'Mağlubiyet', -0.3),
    ('cs_gk', 'Gol yemeden bitirme (kaleci)', 1.0),
    ('cs_def', 'Gol yemeden bitirme (defans)', 0.5),
    ('motm', 'Maçın oyuncusu', 0.5),
    ('yellow', 'Sarı kart', -0.5),
    ('second_yellow', 'Çift sarıdan kırmızı', -1.0),
    ('red', 'Direkt kırmızı', -2.0),
    ('own_goal', 'Kendi kalesine gol', -1.0),
  ];

  /// Süre kuralları.
  static const duration = <(String, String, double)>[
    ('min_minutes', 'Puan verilmesi için en az (dk)', 10),
    ('sub_base', 'Oyuna sonradan girenin başlangıç puanı', 6.5),
    ('full_bonus', '60 dk ve üzeri oynayana', 0.2),
    ('cs_minutes', 'Gol yemeden bitirme için en az (dk)', 60),
  ];

  static final Map<String, double> defaults = {
    for (final r in [...auto, ...duration]) r.$1: r.$3,
    for (final m in MomentKind.all) 'm_${m.key}': m.points,
  };

  double v(String key) => values[key] ?? defaults[key] ?? 0;

  factory RatingRules.fromJson(Object? raw) {
    if (raw is! Map) return RatingRules(enabled: false, values: const {});
    final vals = <String, double>{};
    for (final part in ['rules', 'moments']) {
      final m = raw[part];
      if (m is Map) {
        for (final e in m.entries) {
          final n = e.value is num
              ? (e.value as num).toDouble()
              : double.tryParse('${e.value}');
          if (n != null) {
            vals[part == 'moments' ? 'm_${e.key}' : '${e.key}'] = n;
          }
        }
      }
    }
    return RatingRules(enabled: raw['enabled'] == true, values: vals);
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'rules': {
      for (final r in [...auto, ...duration]) r.$1: v(r.$1),
    },
    'moments': {for (final m in MomentKind.all) m.key: v('m_${m.key}')},
  };

  RatingRules copyWith({bool? enabled, Map<String, double>? values}) =>
      RatingRules(
        enabled: enabled ?? this.enabled,
        values: values ?? this.values,
      );
}

/// Elle girilen puan olayı türü ("Olay ekle").
@immutable
class MomentKind {
  const MomentKind(this.key, this.label, this.group, this.points);

  final String key;
  final String label;

  /// KALECİ / DEFANS / ORTA SAHA / FORVET / HERKES (yalnız düzen için).
  final String group;
  final double points;

  static const all = <MomentKind>[
    MomentKind('save', 'Kurtarış', 'KALECİ', 0.3),
    MomentKind('one_on_one', 'Bire bir kurtarış', 'KALECİ', 0.5),
    MomentKind('pen_save', 'Penaltı kurtarışı', 'KALECİ', 1.0),
    MomentKind('gk_error', 'Hatalı çıkış', 'KALECİ', -0.5),
    MomentKind('tackle', 'Kritik müdahale', 'DEFANS', 0.3),
    MomentKind('line_clear', 'Çizgiden çıkarma', 'DEFANS', 0.5),
    MomentKind('interception', 'Top kesme', 'DEFANS', 0.2),
    MomentKind('pen_conceded', 'Penaltı yaptırma', 'DEFANS', -0.5),
    MomentKind('key_pass', 'Kilit pas', 'ORTA SAHA', 0.3),
    MomentKind('recovery', 'Top kapma', 'ORTA SAHA', 0.2),
    MomentKind('woodwork', 'Direkten dönen şut', 'ORTA SAHA', 0.2),
    MomentKind('bad_loss', 'Kritik top kaybı', 'ORTA SAHA', -0.5),
    MomentKind('pen_won', 'Kazanılan penaltı', 'FORVET', 0.5),
    MomentKind('big_miss', 'Net gol kaçırma', 'FORVET', -0.3),
    MomentKind('pen_miss', 'Kaçan penaltı', 'FORVET', -1.0),
    MomentKind('error_goal', 'Gole sebep hata', 'HERKES', -1.0),
  ];

  static const groups = ['KALECİ', 'DEFANS', 'ORTA SAHA', 'FORVET', 'HERKES'];

  static MomentKind? of(String key) =>
      all.where((m) => m.key == key).firstOrNull;
}

/// Sezon kuralları ve maç süresi (önbellekli).
class RatingRulesRepo {
  RatingRulesRepo._();

  static final Map<String, ({RatingRules rules, int matchMinutes})> _cache = {};

  /// Ayar kaydedilince açık ekranlar yenilensin.
  static final changes = ValueNotifier<int>(0);

  static Future<({RatingRules rules, int matchMinutes})> load(
    String seasonId,
  ) async {
    final hit = _cache[seasonId];
    if (hit != null) return hit;
    try {
      final row = await Supabase.instance.client
          .from('seasons')
          .select('player_rating, match_period_duration')
          .eq('id', seasonId)
          .maybeSingle();
      final half = (row?['match_period_duration'] as num?)?.toInt() ?? 0;
      final r = (
        rules: RatingRules.fromJson(row?['player_rating']),
        matchMinutes: (half > 0 ? half : 45) * 2,
      );
      return _cache[seasonId] = r;
    } catch (_) {
      return (
        rules: const RatingRules(enabled: false, values: {}),
        matchMinutes: 90,
      );
    }
  }

  static Future<void> save(String seasonId, RatingRules rules) async {
    await Supabase.instance.client
        .from('seasons')
        .update({'player_rating': rules.toJson()})
        .eq('id', seasonId);
    _cache.remove(seasonId);
    changes.value++;
  }
}

// ------------------------------------------------------------------ olaylar

/// Elle girilmiş puan olayı.
@immutable
class MatchMoment {
  const MatchMoment({
    required this.id,
    required this.playerId,
    required this.teamId,
    required this.kind,
    this.minute,
  });

  final String id;
  final String playerId;
  final String teamId;
  final String kind;
  final int? minute;
}

class MatchMomentsRepo {
  MatchMomentsRepo._();

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Maç id → değişiklik sayacı (ekleme/silme sonrası yeniden okunur).
  static final changes = ValueNotifier<int>(0);

  static Future<List<MatchMoment>> load(String matchId) async {
    try {
      final rows = await _sb
          .from('match_moments')
          .select('id, player_id, team_id, kind, minute')
          .eq('match_id', matchId)
          .order('minute', ascending: true);
      return [
        for (final r in rows)
          MatchMoment(
            id: '${r['id']}',
            playerId: '${r['player_id']}',
            teamId: '${r['team_id'] ?? ''}',
            kind: '${r['kind']}',
            minute: (r['minute'] as num?)?.toInt(),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> add({
    required String matchId,
    required String teamId,
    required String playerId,
    required String kind,
    int? minute,
  }) async {
    await _sb.from('match_moments').insert({
      'match_id': matchId,
      'team_id': teamId,
      'player_id': playerId,
      'kind': kind,
      'minute': ?minute,
    });
    changes.value++;
  }

  static Future<void> remove(String id) async {
    await _sb.from('match_moments').delete().eq('id', id);
    changes.value++;
  }
}

/// Bir oyuncunun maçtaki olayları (dakikalar; dakikasız sezonda null).
class PlayerMarks {
  final goals = <int?>[];
  final penGoals = <int?>[];
  final ownGoals = <int?>[];
  final assists = <int?>[];
  final yellows = <int?>[];
  final reds = <int?>[];
  int? subIn;
  int? subOut;
  bool subbedIn = false;
  bool subbedOut = false;
  bool motm = false;
  final moments = <MatchMoment>[];

  bool get hasLineEvents =>
      goals.isNotEmpty ||
      penGoals.isNotEmpty ||
      ownGoals.isNotEmpty ||
      yellows.isNotEmpty ||
      reds.isNotEmpty ||
      subbedIn ||
      subbedOut;

  /// Kırmızı kartı sarıdan sonra mı gördü (çift sarı).
  bool get secondYellow => reds.isNotEmpty && yellows.isNotEmpty;
}

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

/// Maçın olayları oyuncu bazında + puanlama.
class MatchInsights {
  MatchInsights({
    required this.match,
    required this.marks,
    required this.rules,
    required this.matchMinutes,
    required this.moments,
    this.subs = const [],
  });

  final MatchModel match;

  /// Değişiklikler sırayla: (çıkan, giren). Dizilişte giren çıkanın yerine
  /// geçer.
  final List<(String, String)> subs;
  final Map<String, PlayerMarks> marks;
  final RatingRules rules;
  final int matchMinutes;
  final List<MatchMoment> moments;

  PlayerMarks of(String playerId) => marks[playerId] ?? PlayerMarks();

  bool get ratingsOn =>
      rules.enabled &&
      match.status != MatchStatus.notStarted &&
      match.status != MatchStatus.postponed &&
      match.status != MatchStatus.cancelled;

  factory MatchInsights.build({
    required MatchModel match,
    required List<Map<String, dynamic>> events,
    required List<MatchMoment> moments,
    required RatingRules rules,
    required int matchMinutes,
  }) {
    final marks = <String, PlayerMarks>{};
    final subs = <(String, String)>[];
    PlayerMarks m(String? id) => marks.putIfAbsent(id ?? '', PlayerMarks.new);
    for (final e in events) {
      final type = '${e['event_type'] ?? ''}';
      final pid = e['player_id']?.toString();
      final min = _int(e['minute']);
      if (pid == null || pid.isEmpty) continue;
      switch (type) {
        case 'goal':
          if (e['is_own_goal'] == true) {
            m(pid).ownGoals.add(min);
          } else {
            (e['is_penalty'] == true ? m(pid).penGoals : m(pid).goals).add(min);
            final a = e['assist_player_id']?.toString();
            if (a != null && a.isNotEmpty) m(a).assists.add(min);
          }
        case 'substitution':
          m(pid)
            ..subbedOut = true
            ..subOut = min;
          final inId = e['sub_in_player_id']?.toString();
          if (inId != null && inId.isNotEmpty) {
            m(inId)
              ..subbedIn = true
              ..subIn = min;
            subs.add((pid, inId));
          }
        case 'yellow_card':
          m(pid).yellows.add(min);
        case 'red_card':
          m(pid).reds.add(min);
        case 'man_of_the_match':
          m(pid).motm = true;
      }
    }
    for (final mo in moments) {
      m(mo.playerId).moments.add(mo);
    }
    return MatchInsights(
      match: match,
      marks: marks,
      rules: rules,
      matchMinutes: matchMinutes,
      moments: moments,
      subs: subs,
    );
  }

  /// Şu ana kadar oynanan dakika (bitmiş maçta tam süre).
  int get _end {
    if (match.status == MatchStatus.finished) return matchMinutes;
    final half = matchMinutes ~/ 2;
    final now = DateTime.now().toUtc();
    final second = match.secondHalfAt;
    if (second != null) {
      return (half + now.difference(second).inMinutes).clamp(0, matchMinutes);
    }
    if (match.status == MatchStatus.halftime) return half;
    final k = match.kickoffAt;
    if (k == null) return matchMinutes;
    return now.difference(k).inMinutes.clamp(0, half);
  }

  /// Oyuncunun puanı; puanlama kapalıysa ya da yeterince oynamadıysa null.
  /// [line]: 0 kaleci, 1 defans, 2+ orta saha/forvet.
  double? ratingFor({
    required String playerId,
    required String teamId,
    required bool starter,
    required int line,
  }) {
    if (!ratingsOn) return null;
    final p = of(playerId);
    if (!starter && !p.subbedIn) return null;
    final end = _end;
    final from = starter ? 0 : (p.subIn ?? end);
    var to = p.subbedOut ? (p.subOut ?? end) : end;
    if (p.reds.isNotEmpty) to = math.min(to, p.reds.first ?? to);
    final played = math.max(0, to - from);
    if (played < rules.v('min_minutes')) return null;

    var r = starter ? rules.v('base') : rules.v('sub_base');
    r += rules.v('goal') * p.goals.length;
    r += rules.v('pen_goal') * p.penGoals.length;
    r += rules.v('assist') * p.assists.length;
    r += rules.v('own_goal') * p.ownGoals.length;
    if (p.motm) r += rules.v('motm');
    if (p.secondYellow) {
      r += rules.v('second_yellow');
      r += rules.v('yellow') * (p.yellows.length - 1);
    } else {
      r += rules.v('yellow') * p.yellows.length;
      r += rules.v('red') * p.reds.length;
    }
    if (played >= 60) r += rules.v('full_bonus');

    final home = teamId == match.homeTeamId;
    final mine = home ? match.homeScore : match.awayScore;
    final theirs = home ? match.awayScore : match.homeScore;
    if (match.status == MatchStatus.finished) {
      if (mine > theirs) r += rules.v('win');
      if (mine < theirs) r += rules.v('loss');
    }
    if (theirs == 0 && played >= rules.v('cs_minutes')) {
      if (line == 0) r += rules.v('cs_gk');
      if (line == 1) r += rules.v('cs_def');
    }
    for (final mo in p.moments) {
      r += rules.v('m_${mo.kind}');
    }
    return (r.clamp(3.0, 10.0) * 10).roundToDouble() / 10;
  }
}

/// Maçın olayları, elle girilen olaylar ve sezon kurallarıyla
/// [MatchInsights] üretir; özellik kapalıysa builder'a null verir.
class MatchInsightsBuilder extends StatefulWidget {
  const MatchInsightsBuilder({
    super.key,
    required this.match,
    required this.builder,
  });

  final MatchModel match;
  final Widget Function(BuildContext context, MatchInsights? insights) builder;

  @override
  State<MatchInsightsBuilder> createState() => _MatchInsightsBuilderState();
}

class _MatchInsightsBuilderState extends State<MatchInsightsBuilder> {
  late Stream<List<Map<String, dynamic>>> _events;
  List<MatchMoment> _moments = const [];
  ({RatingRules rules, int matchMinutes})? _rules;

  @override
  void initState() {
    super.initState();
    _events = ServiceLocator.matchService.watchInlineMatchEvents(
      widget.match.id,
    );
    MatchMomentsRepo.changes.addListener(_loadMoments);
    RatingRulesRepo.changes.addListener(_loadRules);
    _loadMoments();
    _loadRules();
  }

  @override
  void dispose() {
    MatchMomentsRepo.changes.removeListener(_loadMoments);
    RatingRulesRepo.changes.removeListener(_loadRules);
    super.dispose();
  }

  Future<void> _loadMoments() async {
    final m = await MatchMomentsRepo.load(widget.match.id);
    if (mounted) setState(() => _moments = m);
  }

  Future<void> _loadRules() async {
    final r = await RatingRulesRepo.load(widget.match.seasonId);
    if (mounted) setState(() => _rules = r);
  }

  @override
  Widget build(BuildContext context) {
    if (!matchInsightsVisible(context)) return widget.builder(context, null);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _events,
      builder: (context, snap) {
        final rules = _rules;
        if (rules == null) return widget.builder(context, null);
        return widget.builder(
          context,
          MatchInsights.build(
            match: widget.match,
            events: snap.data ?? const [],
            moments: _moments,
            rules: rules.rules,
            matchMinutes: rules.matchMinutes,
          ),
        );
      },
    );
  }
}
