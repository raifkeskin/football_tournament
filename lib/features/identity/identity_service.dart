import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'id_card.dart';

/// [IdentityService.addToRoster] sonucu.
class RosterAddResult {
  const RosterAddResult({
    required this.pending,
    required this.playerId,
    required this.name,
  });

  /// Takım sorumlusu ekledi: onay bekliyor.
  final bool pending;
  final String playerId;
  final String name;
}

/// Esamede "Kadroda yok" satırı için hedef: kimliği okunan oyuncu bu maçın
/// bu takımına eklenir.
class RosterTarget {
  const RosterTarget({
    required this.matchId,
    required this.teamId,
    required this.teamName,
    this.jersey,
    this.readName,
  });

  final String matchId;
  final String teamId;
  final String teamName;

  /// Kağıttaki forma numarası ve ad (Türkçe yazım için).
  final String? jersey;
  final String? readName;
}

/// Kimlik çipinden okunan bilgilere uyan profil (`identity_candidates`).
class IdentityCandidate {
  const IdentityCandidate({
    required this.playerId,
    required this.name,
    required this.surname,
    required this.birthDate,
    required this.photoUrl,
    required this.teams,
    required this.matchKind,
    required this.verifiedOther,
  });

  final String playerId;
  final String name;
  final String surname;
  final String birthDate;
  final String photoUrl;
  final String teams;

  /// tc: bu kimlik zaten bu profile onaylı; exact: ad, soyad ve doğum
  /// tarihi tutuyor; near: doğum tarihi ve ad ya da soyad tutuyor.
  final String matchKind;

  /// Profil başka bir kimlikle onaylı.
  final bool verifiedOther;

  String get fullName => '$name $surname'.trim();

  factory IdentityCandidate.fromJson(Map<String, dynamic> j) =>
      IdentityCandidate(
        playerId: (j['player_id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        surname: (j['surname'] ?? '').toString(),
        birthDate: (j['birth_date'] ?? '').toString(),
        photoUrl: (j['photo_url'] ?? '').toString(),
        teams: (j['teams'] ?? '').toString(),
        matchKind: (j['match_kind'] ?? 'near').toString(),
        verifiedOther: j['verified'] == true,
      );
}

/// Onaylı profil (mavi tik) bilgisi. Onay durumu herkese açık; TC numarası
/// sunucuda yalnız geri çevrilemez özet olarak tutulur.
class IdentityService {
  IdentityService._();

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Oyuncu id → onaylı mı (bu oturumda sorulanlar).
  static final Map<String, bool> _cache = {};

  /// Onay verildiğinde ya da kaldırıldığında artar; açık ekranlar yenilenir.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static bool? cached(String playerId) => _cache[playerId];

  /// [ids] içinden onaylı olanlar. Önbellekte olmayanlar tek sorguda okunur.
  static Future<Set<String>> verifiedAmong(Iterable<String> ids) async {
    final all = {...ids}..remove('');
    final missing = all.where((id) => !_cache.containsKey(id)).toList();
    for (var i = 0; i < missing.length; i += 150) {
      final part = missing.sublist(
        i,
        i + 150 > missing.length ? missing.length : i + 150,
      );
      final rows = await _sb
          .from('player_verifications')
          .select('player_id')
          .inFilter('player_id', part);
      final ok = {for (final r in rows) (r['player_id'] ?? '').toString()};
      for (final id in part) {
        _cache[id] = ok.contains(id);
      }
    }
    return {
      for (final id in all)
        if (_cache[id] == true) id,
    };
  }

  /// Tek oyuncu sorusu: aynı anda gelen sorular (ör. kadro listesindeki
  /// satırlar) tek sorguda toplanır.
  static Future<bool> isVerified(String playerId) async {
    final hit = _cache[playerId];
    if (hit != null) return hit;
    _batch.add(playerId);
    final c = _batchDone ??= Completer<void>();
    _batchTimer ??= Timer(const Duration(milliseconds: 40), () async {
      final ids = {..._batch};
      final done = _batchDone!;
      _batch.clear();
      _batchDone = null;
      _batchTimer = null;
      try {
        await verifiedAmong(ids);
        done.complete();
      } catch (e) {
        done.completeError(e);
      }
    });
    await c.future;
    return _cache[playerId] ?? false;
  }

  static final Set<String> _batch = {};
  static Completer<void>? _batchDone;
  static Timer? _batchTimer;

  static Future<List<IdentityCandidate>> candidates({
    required String firstName,
    required String lastName,
    required DateTime birthDate,
    required String tc,
  }) async {
    final rows = await _sb.rpc(
      'identity_candidates',
      params: {
        'p_first': firstName,
        'p_last': lastName,
        'p_birth': _date(birthDate),
        'p_tc': tc,
      },
    );
    return [
      for (final r in (rows as List))
        IdentityCandidate.fromJson(Map<String, dynamic>.from(r as Map)),
    ];
  }

  static Future<void> verify({
    required String playerId,
    required String firstName,
    required String lastName,
    required DateTime birthDate,
    required String tc,
  }) async {
    await _sb.rpc(
      'identity_verify',
      params: {
        'p_player_id': playerId,
        'p_first': firstName,
        'p_last': lastName,
        'p_birth': _date(birthDate),
        'p_tc': tc,
      },
    );
    _cache[playerId] = true;
    changes.value++;
  }

  /// Esamede "Kadroda yok": kimliği okunan oyuncuyu takıma ekler.
  /// [playerId] seçilen mevcut profil; null ise TC'yle onaylı profil ya da
  /// çipteki bilgilerle yeni onaylı profil kullanılır. Admin, kurucu başkan
  /// ve bölge sorumlusunda doğrudan eklenir ('added'); takım sorumlusunda
  /// kadro talebi açılır ('pending'), onaylanınca maçın esamesine yazılır.
  static Future<RosterAddResult> addToRoster({
    required String matchId,
    required String teamId,
    required IdCardData card,
    String? playerId,
    String? jersey,
    String? display,
  }) async {
    final r = await _sb.rpc(
      'identity_add_to_roster',
      params: {
        'p_match_id': matchId,
        'p_team_id': teamId,
        'p_first': card.firstName,
        'p_last': card.lastName,
        'p_birth': _date(card.birthDate),
        'p_tc': card.tc,
        'p_player_id': playerId,
        'p_jersey': int.tryParse((jersey ?? '').trim()),
        'p_display': display,
      },
    );
    final m = Map<String, dynamic>.from(r as Map);
    final id = (m['player_id'] ?? '').toString();
    _cache[id] = true;
    changes.value++;
    return RosterAddResult(
      pending: m['status'] == 'pending',
      playerId: id,
      name: (m['name'] ?? '').toString(),
    );
  }

  /// Profilin numara durumu: none, unconfirmed, confirmed ya da forbidden.
  static Future<String> phoneState(String playerId) async {
    final r = await _sb.rpc(
      'identity_phone_state',
      params: {'p_player_id': playerId},
    );
    return (r ?? 'forbidden').toString();
  }

  /// Doğrulanan telefonsuz profile numara yazar (sunucu sonuç kodu döner).
  static Future<String> setPhone(String playerId, String raw10) async {
    final r = await _sb.rpc(
      'identity_set_phone',
      params: {'p_player_id': playerId, 'p_phone': raw10},
    );
    return (r ?? '').toString();
  }

  /// Onayı kaldırma yetkisi: admin ya da oyuncunun turnuvasının kurucu
  /// başkanı.
  static Future<bool> canUnverify(String playerId) async {
    try {
      final r = await _sb.rpc(
        'can_unverify_player',
        params: {'p_player_id': playerId},
      );
      return r == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> unverify(String playerId) async {
    await _sb.rpc('identity_unverify', params: {'p_player_id': playerId});
    _cache[playerId] = false;
    changes.value++;
  }

  /// Sunucu hatasını kullanıcıya gösterilecek metne çevirir.
  static String errorText(Object e) {
    if (e is PostgrestException) return e.message;
    return 'Bağlantı hatası. Tekrar deneyin.';
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
