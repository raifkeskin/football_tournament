import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Künye türü: turnuvanın fotoğrafçısı ya da maç yayıncısı.
enum MediaCreditKind {
  photo('Fotoğrafçı', 'Fotoğraf', 'Maç Fotoğrafçısı'),
  broadcast('Yayıncı', 'Yayın', 'Maç Yayıncısı');

  const MediaCreditKind(this.label, this.chipLabel, this.defaultTitle);

  /// Yönetim ekranındaki bölüm adı.
  final String label;

  /// Medya sekmesindeki etiketin ön eki ("Fotoğraf: Ekrem Ayyüz").
  final String chipLabel;

  /// Kartvizitte adın altındaki unvan (boş bırakılırsa).
  final String defaultTitle;

  static MediaCreditKind parse(dynamic v) =>
      v == 'broadcast' ? MediaCreditKind.broadcast : MediaCreditKind.photo;
}

/// Turnuvanın medya künyesi (`media_credits`): fotoğrafçı ya da yayıncının
/// kartvizit bilgileri. Telefon ve e-posta yalnız kişinin onayıyla tutulur.
class MediaCredit {
  const MediaCredit({
    required this.id,
    required this.leagueId,
    required this.kind,
    required this.name,
    this.title,
    this.avatarUrl,
    this.phone,
    this.email,
    this.instagram,
    this.youtubeUrl,
    this.note,
    this.contactConsent = false,
    this.isActive = true,
    this.isDefault = false,
  });

  final String id;
  final String leagueId;
  final MediaCreditKind kind;
  final String name;
  final String? title;
  final String? avatarUrl;
  final String? phone;
  final String? email;

  /// Kullanıcı adı, @ olmadan.
  final String? instagram;
  final String? youtubeUrl;

  /// Kartvizitteki kısa not (ör. "Baskı ve özel çekim için arayın").
  final String? note;
  final bool contactConsent;
  final bool isActive;

  /// Maçına ayrı ekip seçilmemiş maçlarda görünen kişi (türü başına bir).
  final bool isDefault;

  String get displayTitle =>
      (title ?? '').trim().isEmpty ? kind.defaultTitle : title!.trim();

  static String? _s(dynamic v) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? null : t;
  }

  factory MediaCredit.fromMap(Map<String, dynamic> m) => MediaCredit(
    id: (m['id'] ?? '').toString(),
    leagueId: (m['league_id'] ?? '').toString(),
    kind: MediaCreditKind.parse(m['kind']),
    name: (m['name'] ?? '').toString(),
    title: _s(m['title']),
    avatarUrl: _s(m['avatar_url']),
    phone: _s(m['phone']),
    email: _s(m['email']),
    instagram: _s(m['instagram']),
    youtubeUrl: _s(m['youtube_url']),
    note: _s(m['note']),
    contactConsent: m['contact_consent'] == true,
    isActive: m['is_active'] != false,
    isDefault: m['is_default'] == true,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'league_id': leagueId,
    'kind': kind.name,
    'name': name,
    'title': title,
    'avatar_url': avatarUrl,
    'phone': phone,
    'email': email,
    'instagram': instagram,
    'youtube_url': youtubeUrl,
    'note': note,
    'contact_consent': contactConsent,
    'is_active': isActive,
    'is_default': isDefault,
  };
}

/// Turnuvanın etkin künyeleri; Medya sekmesi önce bellekteki/cihazdaki hâli
/// çizer, sonra veritabanından tazeler.
class MediaCreditFeed {
  MediaCreditFeed._();

  static SupabaseClient get _sb => Supabase.instance.client;
  static String _key(String leagueId) => 'media_credits_$leagueId';

  static final _memory = <String, List<MediaCredit>>{};

  /// Yönetim ekranında değişiklik olan turnuvanın id'si.
  static final changes = ValueNotifier<String?>(null);

  static void notifyChanged(String leagueId) {
    _memory.remove(leagueId);
    changes.value = null;
    changes.value = leagueId;
  }

  static List<MediaCredit>? memory(String leagueId) => _memory[leagueId];

  @visibleForTesting
  static void clearMemory() => _memory.clear();

  static Future<List<MediaCredit>?> cached(String leagueId) async {
    final mem = _memory[leagueId];
    if (mem != null) return mem;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(leagueId));
      if (raw == null) return null;
      return _memory[leagueId] = [
        for (final m in jsonDecode(raw) as List)
          MediaCredit.fromMap(Map<String, dynamic>.from(m as Map)),
      ];
    } catch (_) {
      return null;
    }
  }

  static Future<List<MediaCredit>> fetch(String leagueId) async {
    final rows = await _sb
        .from('media_credits')
        .select()
        .eq('league_id', leagueId)
        .eq('is_active', true);
    final list = [for (final r in rows) MediaCredit.fromMap(r)];
    _memory[leagueId] = list;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(leagueId),
        jsonEncode([for (final c in list) c.toMap()]),
      );
    } catch (_) {}
    return list;
  }
}

/// Maçın medya ekibi: [custom] ise maç için seçilmiş kişiler ([ids]; boşsa
/// ekip yok), değilse turnuvanın varsayılanları.
typedef MatchCrew = ({bool custom, Set<String> ids});

class MatchMediaCrew {
  MatchMediaCrew._();

  static SupabaseClient get _sb => Supabase.instance.client;
  static final _memory = <String, MatchCrew>{};

  /// Ekibi değişen maçın id'si.
  static final changes = ValueNotifier<String?>(null);

  static MatchCrew? memory(String matchId) => _memory[matchId];

  static Future<MatchCrew> fetch(String matchId) async {
    final row = await _sb
        .from('matches')
        .select('media_crew_custom, match_media_crew(credit_id)')
        .eq('id', matchId)
        .maybeSingle();
    final crew = (
      custom: row?['media_crew_custom'] == true,
      ids: {
        for (final r in (row?['match_media_crew'] as List? ?? const []))
          (r as Map)['credit_id'].toString(),
      },
    );
    return _memory[matchId] = crew;
  }

  /// [ids] null → turnuvanın varsayılanına döner; boş → ekip yok.
  static Future<void> save(String matchId, Set<String>? ids) async {
    await _sb.rpc(
      'set_match_media_crew',
      params: {'p_match_id': matchId, 'p_credit_ids': ids?.toList()},
    );
    _memory[matchId] = (custom: ids != null, ids: ids ?? const {});
    changes.value = null;
    changes.value = matchId;
  }

  /// Maçta görünen [kind] türündeki kişiler.
  static List<MediaCredit> resolve(
    List<MediaCredit>? credits,
    MatchCrew? crew,
    MediaCreditKind kind,
  ) {
    final list = [
      for (final c in credits ?? const <MediaCredit>[])
        if (c.kind == kind && c.isActive) c,
    ];
    if (crew != null && crew.custom) {
      return [
        for (final c in list)
          if (crew.ids.contains(c.id)) c,
      ];
    }
    final def = list.where((c) => c.isDefault).firstOrNull ?? list.firstOrNull;
    return def == null ? const [] : [def];
  }
}
