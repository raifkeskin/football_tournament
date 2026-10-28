import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/app_settings.dart';

/// Hakem havuzundaki kayıt (`referees`); turnuva listesinde telefon ve
/// hesap durumu yalnız turnuva yöneticisine gelir.
@immutable
class Referee {
  const Referee({
    required this.id,
    required this.name,
    this.photoUrl,
    this.phone,
    this.hasAccount = false,
    this.matchCount = 0,
  });

  final String id;
  final String name;
  final String? photoUrl;

  /// 10 hane (5XX…); yalnız yöneticiye.
  final String? phone;
  final bool hasAccount;
  final int matchCount;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
  }

  static String? _s(dynamic v) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty || t == 'null' ? null : t;
  }

  factory Referee.fromMap(Map<String, dynamic> m) => Referee(
    id: m['id'].toString(),
    name: (m['name'] ?? '').toString(),
    photoUrl: _s(m['photo_url']),
    phone: _s(m['phone_raw10']),
    hasAccount: m['has_account'] == true,
    matchCount: (m['match_count'] as num?)?.toInt() ?? 0,
  );
}

/// Havuzda eşleşen hakem ("mevcudu bağla" önerisi).
@immutable
class RefereeCandidate {
  const RefereeCandidate({
    required this.id,
    required this.name,
    required this.samePhone,
    this.leagues,
  });

  final String id;
  final String name;
  final bool samePhone;
  final String? leagues;
}

/// Hakemin bir maçı ve görevi.
@immutable
class RefereeMatch {
  const RefereeMatch(this.m);

  final Map<String, dynamic> m;

  String get id => m['id'].toString();
  String get leagueName => (m['league_name'] ?? '').toString();
  String get home => (m['home_name'] ?? 'Ev Sahibi').toString();
  String get away => (m['away_name'] ?? 'Deplasman').toString();
  int? get homeScore => (m['home_score'] as num?)?.toInt();
  int? get awayScore => (m['away_score'] as num?)?.toInt();
  String get status => (m['status'] ?? '').toString();
  bool get isCenter => m['role'] == 'center';
  String? get pitch => Referee._s(m['pitch_name']);
  int? get week => (m['week'] as num?)?.toInt();

  DateTime? get start {
    final d = DateTime.tryParse((m['match_date'] ?? '').toString());
    if (d == null) return null;
    final t = RegExp(
      r'^(\d{1,2}):(\d{2})',
    ).firstMatch((m['match_time'] ?? '').toString());
    return t == null
        ? d
        : DateTime(
            d.year,
            d.month,
            d.day,
            int.parse(t.group(1)!),
            int.parse(t.group(2)!),
          );
  }

  String? get timeLabel {
    final t = (m['match_time'] ?? '').toString();
    return t.length >= 5 ? t.substring(0, 5) : null;
  }

  bool get isUpcoming => status == 'notStarted' || status == 'postponed';
}

/// Turnuva bazında hakem sayıları.
@immutable
class RefereeLeagueStats {
  const RefereeLeagueStats(this.m);

  final Map<String, dynamic> m;

  int _i(String k) => (m[k] as num?)?.toInt() ?? 0;
  String get leagueName => (m['league_name'] ?? '').toString();
  int get center => _i('center');
  int get assistant => _i('assistant');
  int get yellow => _i('yellow');
  int get red => _i('red');
  int get penalty => _i('penalty');
  int get goals => _i('goals');
}

/// Hakem verisi; yazmalar RPC ile (yetki ve özellik anahtarı sunucuda).
class RefereeService {
  RefereeService._();

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Özellik açık mı (kapalıyken yalnız admin).
  static bool enabledFor({required bool isAdmin}) =>
      isAdmin || AppSettings.refereesEnabled.value;

  static final Map<String, Referee> _byId = {};

  static Future<List<Referee>> leagueList(String leagueId) async {
    final rows = await _sb.rpc(
      'league_referees_list',
      params: {'p_league_id': leagueId},
    );
    final list = [
      for (final r in (rows as List? ?? const []))
        Referee.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
    for (final r in list) {
      _byId[r.id] = r;
    }
    return list;
  }

  /// Ad / fotoğraf (herkese açık); bellekte tutulur.
  static Future<Map<String, Referee>> byIds(Iterable<String> ids) async {
    final want = ids.where((e) => e.isNotEmpty).toSet();
    final missing = want.where((id) => !_byId.containsKey(id)).toList();
    if (missing.isNotEmpty) {
      final rows = await _sb
          .from('referees')
          .select('id, name, photo_url')
          .inFilter('id', missing);
      for (final r in rows) {
        final ref = Referee.fromMap(r);
        _byId[ref.id] = ref;
      }
    }
    return {
      for (final id in want)
        if (_byId[id] != null) id: _byId[id]!,
    };
  }

  static Referee? cached(String? id) => id == null ? null : _byId[id];

  static Future<List<RefereeCandidate>> candidates(
    String leagueId,
    String name,
    String? phone,
  ) async {
    final rows = await _sb.rpc(
      'referee_candidates',
      params: {'p_league_id': leagueId, 'p_name': name, 'p_phone': phone},
    );
    return [
      for (final r in (rows as List? ?? const []))
        RefereeCandidate(
          id: (r as Map)['id'].toString(),
          name: (r['name'] ?? '').toString(),
          samePhone: r['same_phone'] == true,
          leagues: Referee._s(r['leagues']),
        ),
    ];
  }

  static Future<String> save({
    required String leagueId,
    String? refereeId,
    required String name,
    String? phone,
  }) async {
    final id = await _sb.rpc(
      'referee_save',
      params: {
        'p_league_id': leagueId,
        'p_referee_id': refereeId,
        'p_name': name,
        'p_phone': phone,
      },
    );
    if (refereeId != null) _byId.remove(refereeId);
    return id.toString();
  }

  static Future<void> link(String leagueId, String refereeId) => _sb.rpc(
    'referee_link',
    params: {'p_league_id': leagueId, 'p_referee_id': refereeId},
  );

  static Future<void> unlink(String leagueId, String refereeId) => _sb.rpc(
    'referee_unlink',
    params: {'p_league_id': leagueId, 'p_referee_id': refereeId},
  );

  static Future<void> setMatchReferees(
    String matchId, {
    String? referee,
    String? assistant1,
    String? assistant2,
  }) => _sb.rpc(
    'match_set_referees',
    params: {
      'p_match_id': matchId,
      'p_referee': referee,
      'p_assistant1': assistant1,
      'p_assistant2': assistant2,
    },
  );

  static Future<String?> myRefereeId() async {
    final r = await _sb.rpc('my_referee_id');
    final s = (r ?? '').toString();
    return s.isEmpty || s == 'null' ? null : s;
  }

  static Future<List<RefereeMatch>> matches(String refereeId) async {
    final rows = await _sb.rpc(
      'referee_matches',
      params: {'p_referee_id': refereeId},
    );
    return [
      for (final r in (rows as List? ?? const []))
        RefereeMatch(Map<String, dynamic>.from(r as Map)),
    ];
  }

  static Future<List<RefereeLeagueStats>> stats(String refereeId) async {
    final rows = await _sb.rpc(
      'referee_stats',
      params: {'p_referee_id': refereeId},
    );
    return [
      for (final r in (rows as List? ?? const []))
        RefereeLeagueStats(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Sunucu hata metnini kullanıcıya uygun hâle getirir.
  static String message(Object e) {
    if (e is PostgrestException) return e.message;
    return e.toString();
  }
}
