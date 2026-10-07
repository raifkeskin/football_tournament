import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Turnuva sponsoru: ana (`main`) ya da alt (`sub`) sponsor.
class Sponsor {
  const Sponsor({
    required this.id,
    required this.leagueId,
    required this.tier,
    required this.name,
    this.logoUrl = '',
    this.linkUrl,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String id;
  final String leagueId;
  final String tier;
  final String name;
  final String logoUrl;
  final String? linkUrl;
  final int sortOrder;
  final bool isActive;

  bool get isMain => tier == 'main';

  factory Sponsor.fromMap(Map<String, dynamic> m) => Sponsor(
    id: (m['id'] ?? '').toString(),
    leagueId: (m['league_id'] ?? '').toString(),
    tier: m['tier'] == 'sub' ? 'sub' : 'main',
    name: (m['name'] ?? '').toString(),
    logoUrl: (m['logo_url'] ?? '').toString(),
    linkUrl: (m['link_url'] as String?)?.trim().isEmpty ?? true
        ? null
        : (m['link_url'] as String).trim(),
    sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
    isActive: m['is_active'] != false,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'league_id': leagueId,
    'tier': tier,
    'name': name,
    'logo_url': logoUrl,
    'link_url': linkUrl,
    'sort_order': sortOrder,
    'is_active': isActive,
  };

  /// Önce ana sponsorlar, sonra alt sponsorlar; kendi içlerinde sıraya göre.
  static int compare(Sponsor a, Sponsor b) {
    if (a.isMain != b.isMain) return a.isMain ? -1 : 1;
    final c = a.sortOrder.compareTo(b.sortOrder);
    return c != 0 ? c : a.name.compareTo(b.name);
  }
}

/// Ana sayfa şeridinin verisi: aktif sponsorlar ve ekranda kalma süreleri.
class SponsorFeed {
  const SponsorFeed({
    required this.sponsors,
    this.mainSeconds = 8,
    this.subSeconds = 4,
  });

  final List<Sponsor> sponsors;
  final int mainSeconds;
  final int subSeconds;

  static SupabaseClient get _sb => Supabase.instance.client;
  static String _key(String leagueId) => 'sponsor_feed_$leagueId';

  /// Cihazdaki son hâl (şerit ilk karede çizilsin, sonradan zıplamasın).
  static Future<SponsorFeed?> cached(String leagueId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(leagueId));
      if (raw == null) return null;
      return _fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<SponsorFeed> fetch(String leagueId) async {
    final r = await Future.wait<dynamic>([
      _sb
          .from('sponsors')
          .select()
          .eq('league_id', leagueId)
          .eq('is_active', true),
      _sb
          .from('leagues')
          .select('sponsor_main_seconds, sponsor_sub_seconds')
          .eq('id', leagueId)
          .maybeSingle(),
    ]);
    final list = [
      for (final m in r[0] as List) Sponsor.fromMap(m as Map<String, dynamic>),
    ]..sort(Sponsor.compare);
    final l = r[1] as Map?;
    final feed = SponsorFeed(
      sponsors: list,
      mainSeconds: (l?['sponsor_main_seconds'] as num?)?.toInt() ?? 8,
      subSeconds: (l?['sponsor_sub_seconds'] as num?)?.toInt() ?? 4,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(leagueId), jsonEncode(feed._toJson()));
    } catch (_) {}
    return feed;
  }

  Map<String, dynamic> _toJson() => {
    'main': mainSeconds,
    'sub': subSeconds,
    'items': [for (final s in sponsors) s.toMap()],
  };

  static SponsorFeed _fromJson(Map<String, dynamic> j) => SponsorFeed(
    mainSeconds: (j['main'] as num?)?.toInt() ?? 8,
    subSeconds: (j['sub'] as num?)?.toInt() ?? 4,
    sponsors: [
      for (final m in (j['items'] as List? ?? const []))
        Sponsor.fromMap(Map<String, dynamic>.from(m as Map)),
    ],
  );
}
