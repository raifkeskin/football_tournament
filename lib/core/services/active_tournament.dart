import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'global_filter.dart';

/// Uygulamanın büründüğü turnuva kimliği (logo, ad, renkler).
@immutable
class TournamentTheme {
  const TournamentTheme({
    required this.leagueId,
    required this.name,
    required this.logoUrl,
    required this.primary,
    required this.secondary,
    this.instagramUrl = '',
    this.facebookUrl = '',
    this.youtubeUrl = '',
    this.websiteUrl = '',
  });

  /// Turnuvanın sosyal medya / web adresleri (boş: yok).
  final String instagramUrl;
  final String facebookUrl;
  final String youtubeUrl;
  final String websiteUrl;

  final String leagueId;

  /// Bantta görünen ad (kısa ad varsa o).
  final String name;
  final String logoUrl;
  final Color primary;
  final Color secondary;

  /// Bant gradyanının koyu kenarları.
  Color get primaryDark => Color.lerp(primary, Colors.black, 0.45)!;

  static Color? _hex(dynamic v) {
    final s = (v ?? '').toString().trim();
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(s)) return null;
    return Color(int.parse('FF${s.substring(1)}', radix: 16));
  }

  static String _toHex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// `leagues` satırından. Tema rengi girilmemiş turnuva da aynı bant
  /// tasarımıyla (adı + seçici) görünür; renk olarak varsayılan yeşil.
  static TournamentTheme? fromRow(Map<String, dynamic> r) {
    if ((r['id'] ?? '').toString().isEmpty) return null;
    final p = _hex(r['theme_primary']) ?? const Color(0xFF064E3B);
    final short = (r['short_name'] ?? '').toString().trim();
    return TournamentTheme(
      leagueId: (r['id'] ?? '').toString(),
      name: short.isNotEmpty ? short : (r['name'] ?? '').toString().trim(),
      logoUrl: (r['logo_url'] ?? '').toString().trim(),
      primary: p,
      instagramUrl: (r['instagram_url'] ?? '').toString().trim(),
      facebookUrl: (r['facebook_url'] ?? '').toString().trim(),
      youtubeUrl: (r['youtube_url'] ?? '').toString().trim(),
      websiteUrl: (r['website_url'] ?? '').toString().trim(),
      secondary:
          _hex(r['theme_secondary']) ??
          (_hex(r['theme_primary']) == null
              ? const Color(0xFF10B981)
              : Colors.white),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': leagueId,
    'short_name': name,
    'logo_url': logoUrl,
    'theme_primary': _toHex(primary),
    'theme_secondary': _toHex(secondary),
    'instagram_url': instagramUrl,
    'facebook_url': facebookUrl,
    'youtube_url': youtubeUrl,
    'website_url': websiteUrl,
  };
}

/// Uygulama hangi turnuvanın kimliğiyle açılsın? Soru sorulmadan:
/// 1. Giriş yapmış kişi: kendi turnuvası (`my_preferred_league`: oyuncu,
///    takım sorumlusu, kurucu başkan, takipçi).
/// 2. Misafir: en son seçip baktığı turnuva (cihazda saklanır).
/// 3. Hiçbiri yoksa ya da turnuvanın teması yoksa: genel TVL görünümü.
/// Son tema cihazda saklanır; açılış ekranı beklemeden boyanır.
class ActiveTournament {
  ActiveTournament._();

  static final theme = ValueNotifier<TournamentTheme?>(null);

  /// Uygulamanın içinde bulunduğu turnuva (teması olmasa da).
  static final currentLeagueId = ValueNotifier<String?>(null);

  /// Kişinin turnuvaları (bant seçicisi; birden fazlaysa ▾ görünür).
  static final myLeagues = ValueNotifier<List<LeagueChoice>>(const []);

  static const _kTheme = 'active_tournament_theme';
  static const _kGuestLeague = 'guest_last_league';

  /// Misafir modu seçildi mi (GuestMode ile aynı anahtar).
  static const _kGuestChosen = 'guest_mode_chosen';

  /// Giriş yapmış kişinin bantta seçtiği turnuva (kullanıcıya göre).
  static String _kChosen(String uid) => 'chosen_league_$uid';

  /// Üst üste gelen refresh çağrılarında yalnızca sonuncusu uygulanır.
  static int _generation = 0;

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Giriş yapmış (misafir olmayan) kullanıcı mı.
  static bool get isRealUser => _isRealUser;

  static bool get _isRealUser {
    final u = _sb.auth.currentUser;
    return u != null && !u.isAnonymous;
  }

  /// Saklanan son temayı yükler (main'de, runApp'ten önce). Giriş yapılmamış
  /// ve misafir seçimi de yapılmamışsa (açılışta giriş kapısı çıkacak) uygulama
  /// TVL kimliğiyle açılır; eski tema temizlenir.
  static Future<void> init({required bool guestChosen}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_isRealUser && !guestChosen) {
        theme.value = null;
        await prefs.remove(_kTheme);
        return;
      }
      final raw = prefs.getString(_kTheme);
      if (raw == null) return;
      theme.value = TournamentTheme.fromRow(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      currentLeagueId.value = theme.value?.leagueId;
    } catch (_) {}
  }

  /// Kişiye göre turnuvayı belirler (açılışta ve giriş/çıkışta).
  /// Giriş yapılmamış ve misafir modu seçilmemişse (giriş kapısı) tema
  /// boştur: kapıda hiçbir turnuvanın adı görünmez.
  static Future<void> refresh() async {
    final gen = ++_generation;
    try {
      String? id;
      final prefs = await SharedPreferences.getInstance();
      if (_isRealUser) {
        final uid = _sb.auth.currentUser!.id;
        final choices = await _loadMyLeagues();
        if (gen == _generation) myLeagues.value = choices;
        // Bantta seçtiği turnuva hâlâ onun turnuvasıysa o; yoksa en yakın
        // maçı olan kendi turnuvası.
        final chosen = prefs.getString(_kChosen(uid));
        if (chosen != null && choices.any((c) => c.id == chosen)) {
          id = chosen;
        } else {
          final res = await _sb.rpc('my_preferred_league');
          id = res?.toString();
          // Hiçbir turnuvaya bağlı olmayan (ör. admin): varsayılan sezonu
          // olan turnuva, yoksa listedeki ilki; bant seçicisi görünür olur.
          if ((id == null || id.isEmpty) && choices.isNotEmpty) {
            id = await _defaultLeague(choices);
          }
        }
      } else {
        final guest = prefs.getBool(_kGuestChosen) ?? false;
        // Misafir: herkese açık tüm aktif turnuvalar arasında seçebilir.
        final choices = guest
            ? await _loadMyLeagues(guest: true)
            : const <LeagueChoice>[];
        if (gen == _generation) myLeagues.value = choices;
        if (guest) {
          id = prefs.getString(_kGuestLeague);
          // Henüz seçmediyse varsayılan sezonu olan turnuva (yoksa ilki):
          // bant giriş yapmış kişidekiyle aynı görünür.
          if (id == null || id.isEmpty) id = await _defaultLeague(choices);
        }
      }
      await _apply(id, gen: gen);
    } catch (e) {
      debugPrint('Turnuva teması belirlenemedi: $e');
    }
  }

  /// Varsayılan sezonu olan turnuva (listede varsa), yoksa listedeki ilki.
  static Future<String?> _defaultLeague(List<LeagueChoice> choices) async {
    final def = await _sb
        .from('seasons')
        .select('league_id')
        .eq('is_default', true)
        .limit(1);
    final defId = def.isEmpty ? null : def.first['league_id']?.toString();
    if (choices.any((c) => c.id == defId)) return defId;
    return choices.isEmpty ? null : choices.first.id;
  }

  /// Bant seçicisinden turnuva değişimi: tema, ortak filtre (Fikstür, Puan
  /// Durumu, İstatistik, ana sayfa) ve cihazdaki seçim birlikte değişir.
  static Future<void> choose(String id) async {
    final gen = ++_generation;
    GlobalFilter.setLeague(id);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_isRealUser) {
        await prefs.setString(_kChosen(_sb.auth.currentUser!.id), id);
      } else {
        // Misafirin son turnuvası (açılışta bu turnuvayla gelir).
        await prefs.setString(_kGuestLeague, id);
      }
      await _apply(id, gen: gen);
    } catch (e) {
      debugPrint('Turnuva seçilemedi: $e');
    }
  }

  /// Kişinin turnuvaları: admin ve misafir tüm aktif turnuvalar (gizli ve
  /// demo turnuvalar veritabanı kuralıyla misafire gelmez), diğerleri
  /// my_league_ids (oyuncu, sorumlu, kurucu, bölge, gözlemci, takipçi).
  static Future<List<LeagueChoice>> _loadMyLeagues({bool guest = false}) async {
    final all = guest || await _sb.rpc('is_admin') == true;
    var query = _sb
        .from('leagues')
        .select('id, name, short_name, logo_url, is_active');
    if (!all) {
      final ids = ((await _sb.rpc('my_league_ids')) as List? ?? const [])
          .map((e) => e.toString())
          .toList();
      if (ids.length < 2) return const [];
      query = query.inFilter('id', ids);
    }
    final rows = await query.order('name');
    final list = [
      for (final r in rows)
        if (r['is_active'] != false)
          LeagueChoice(
            id: r['id'].toString(),
            name: (r['name'] ?? '').toString(),
            logoUrl: (r['logo_url'] ?? '').toString(),
          ),
    ];
    return list.length < 2 ? const [] : list;
  }

  /// Misafir bir turnuvayı seçip baktığında: uygulama o turnuvaya bürünür.
  /// Giriş yapmış kişide tema kendi turnuvasında kalır.
  static Future<void> noteViewed(String? leagueId) async {
    if (_isRealUser || (leagueId ?? '').isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kGuestLeague) == leagueId) return;
      await prefs.setString(_kGuestLeague, leagueId!);
      await _apply(leagueId);
    } catch (_) {}
  }

  static Future<void> _apply(String? leagueId, {int? gen}) async {
    TournamentTheme? next;
    if ((leagueId ?? '').isNotEmpty) {
      final row = await _sb
          .from('leagues')
          .select(
            'id, name, short_name, logo_url, theme_primary, theme_secondary, '
            'instagram_url, facebook_url, youtube_url, website_url',
          )
          .eq('id', leagueId!)
          .maybeSingle();
      if (row != null) next = TournamentTheme.fromRow(row);
    }
    // Bu arada daha yeni bir refresh başladıysa onun sonucu geçerli.
    if (gen != null && gen != _generation) return;
    theme.value = next;
    currentLeagueId.value = (leagueId ?? '').isEmpty ? null : leagueId;
    // Diğer ekranlar da bu turnuvayla açılsın.
    if (leagueId != null && leagueId.isNotEmpty) {
      GlobalFilter.setLeague(leagueId);
    }
    final prefs = await SharedPreferences.getInstance();
    if (next == null) {
      await prefs.remove(_kTheme);
    } else {
      await prefs.setString(_kTheme, jsonEncode(next.toJson()));
    }
  }
}

/// Bant seçicisindeki bir turnuva.
@immutable
class LeagueChoice {
  const LeagueChoice({
    required this.id,
    required this.name,
    required this.logoUrl,
  });

  final String id;
  final String name;
  final String logoUrl;
}
