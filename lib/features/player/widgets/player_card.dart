import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../team/widgets/team_page_tabs.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/active_tournament.dart';
import '../../../core/services/app_settings.dart';
import '../../../core/services/app_session.dart';
import '../../../core/widgets/youtube_player_page.dart';
import '../../match/widgets/youtube_find_sheet.dart' show BroadcastThumb;
import '../../tournament/models/league.dart';
import '../../match/utils/minute_label.dart';
import '../../tournament/screens/formation_tab.dart'
    show positionLineLabels, positionLineOf;
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/utils/string_utils.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/widgets/admin_page.dart' show showAdminConfirmDialog;
import '../../identity/identity_access.dart';
import '../../identity/identity_service.dart';
import '../../identity/identity_verify_screen.dart';
import '../../identity/verified_badge.dart';
import 'player_positions_tab.dart';

// Uygulamanın ortak renkleri
const _bgDark = Color(0xFF0F172A);
const _forest = Color(0xFF064E3B);
const _accent = Color(0xFF10B981);
const _mid = Color(0xFF94A3B8);
const _purple = Color(0xFFA78BFA);
const _yellow = Color(0xFFFBBF24);
const _red = Color(0xFFEF4444);

String _positionLabel(String main, String sub) {
  switch (sub) {
    case 'GK':
      return 'Kaleci';
    case 'DEF':
      return 'Defans';
    case 'ORT':
      return 'Orta Saha';
    case 'FOR':
      return 'Forvet';
  }
  if (sub.isNotEmpty) return sub;
  return main;
}

/// Alt mevki ("Santrfor"); yalnız hat kodu (GK/DEF/ORT/FOR) girilmişse alt
/// mevki yoktur.
String _subPositionLabel(String sub) {
  final s = sub.trim();
  if (const {'GK', 'DEF', 'ORT', 'FOR'}.contains(s)) return '';
  return s;
}

/// Oyuncu kartını tam ekran sayfa olarak açar; kapatınca açıldığı ekrana
/// döner. [playerKey] oyuncu id'si ya da telefonu (istatistik ekranları
/// telefonla tanımlar). Diğer bilgiler buradan okunur.
Future<void> showPlayerCard(
  BuildContext context, {
  required String playerKey,
  String number = '',
}) {
  final key = playerKey.trim();
  final isId = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(key);
  // Oyuncu yalnız id ile açılır (telefon tablodan okunmaz).
  final Future<List<Map<String, dynamic>>> future = !isId
      ? Future.value(const <Map<String, dynamic>>[])
      : Supabase.instance.client
            .from('players')
            .select(
              'id, name, surname, photo_url, birth_date, height, weight, '
              'main_position, sub_position',
            )
            .eq('id', key)
            .limit(1);
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (ctx) => Scaffold(
        backgroundColor: _bgDark,
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: future,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: _accent),
              );
            }
            final rows = snap.data ?? const [];
            if (rows.isEmpty) {
              return SafeArea(
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        onPressed: () => Navigator.of(ctx).maybePop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                        ),
                        tooltip: 'Kapat',
                      ),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Oyuncu bulunamadı.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            final r = rows.first;
            String str(String k) => (r[k] ?? '').toString().trim();
            return PlayerCard(
              playerPhone: key,
              playerId: str('id'),
              name: [
                str('name'),
                str('surname'),
              ].where((e) => e.isNotEmpty).join(' '),
              number: number,
              photoUrl: str('photo_url'),
              position: _positionLabel(
                str('main_position'),
                str('sub_position'),
              ),
              mainPosition: str('main_position'),
              subPosition: _subPositionLabel(str('sub_position')),
              birthDate: str('birth_date'),
              height: (r['height'] as num?)?.toInt(),
              weight: (r['weight'] as num?)?.toInt(),
              seasons: const [],
              initialSeasonId: '',
            );
          },
        ),
      ),
    ),
  );
}

/// Oyuncu kartı: üstte kimlik, ortada kariyer özeti, altta turnuva/sezon
/// bazında sıkı bir tablo. İstatistikler maç olaylarından hesaplanır.
class PlayerCard extends StatefulWidget {
  const PlayerCard({
    super.key,
    required this.playerPhone,
    required this.name,
    required this.number,
    required this.photoUrl,
    required this.position,
    this.mainPosition = '',
    this.subPosition = '',
    required this.birthDate,
    required this.height,
    required this.weight,
    required this.seasons,
    required this.initialSeasonId,
    this.playerId = '',
  });

  final String playerPhone;

  /// Onay ikonu ve onay menüsü için oyuncu id'si.
  final String playerId;
  final String name;
  final String number;
  final String photoUrl;

  /// "Ana Mevki" kutusunda hat (Kaleci/Defans/Orta Saha/Forvet);
  /// [mainPosition] boşsa [position]'dan çıkarılır. "Alt Mevki" kutusunda
  /// [subPosition] ("Santrfor"; boşsa "-").
  final String position;
  final String mainPosition;
  final String subPosition;
  final String birthDate;
  final int? height;
  final int? weight;
  final List<League> seasons;
  final String initialSeasonId;

  @override
  State<PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends State<PlayerCard> {
  late final Future<_PlayerCardData> _future = _load();

  late final Future<List<_GoalClip>> _goals = _loadGoals();

  /// Açık gol satırı (dar listede dokununca ayrıntısı açılır).
  String? _openGoal;

  /// Alt bölüm sekmesi: 0 Özet, 1 Turnuvalar, 2 Goller, 3 Mevki.
  int _tab = 0;

  /// Kartın oyuncu id'si (eski girişler id'yi [PlayerCard.playerPhone]'da
  /// taşır).
  String get _cardPlayerId {
    final id = widget.playerId.trim();
    if (id.isNotEmpty) return id;
    final key = widget.playerPhone.trim();
    return _uuidLike.hasMatch(key) ? key : '';
  }

  /// Mevki sekmesi: açılana dek yalnız admin (veritabanı da aynı anahtarla
  /// kaydı açar).
  bool get _showPositionsTab =>
      _cardPlayerId.isNotEmpty &&
      (AppSettings.positionsTabEnabled.value ||
          AppSession.of(context).value.isAdmin);

  /// Kart, uygulamanın içinde bulunduğu turnuvanın renklerini alır; teması
  /// olmayan turnuvada varsayılan yeşil.
  TournamentTheme? get _theme => ActiveTournament.theme.value;
  Color get _primary => _theme?.primary ?? _forest;
  Color get _tone => _theme?.secondary ?? _accent;

  /// Zemin rengine göre okunur yazı rengi.
  static Color _on(Color c) =>
      ThemeData.estimateBrightnessForColor(c) == Brightness.light
      ? _bgDark
      : Colors.white;

  /// Alt çizgili sekme çubuğu (takım sayfası ve maç detayıyla aynı).
  Widget _tabBar(int goalCount) => TeamPageTabBar(
    index: _tab,
    labels: [
      'Özet',
      'Turnuvalar',
      goalCount > 0 ? 'Goller ($goalCount)' : 'Goller',
      if (_showPositionsTab) 'Mevki',
    ],
    indicatorColor: _tone,
    onChanged: (i) => setState(() => _tab = i),
  );

  SupabaseClient get _sb => Supabase.instance.client;

  /// GG/AA/YYYY, GG.AA.YYYY, veritabanındaki YYYY-AA-GG ya da sadece yıl.
  int? _ageFromBirthDate(String? birthDate) {
    final s = (birthDate ?? '').trim();
    if (s.isEmpty) return null;
    int dd, mm, yyyy;
    final dmy = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$').firstMatch(s);
    final ymd = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    final y = RegExp(r'^(\d{4})$').firstMatch(s);
    if (dmy != null) {
      dd = int.parse(dmy.group(1)!);
      mm = int.parse(dmy.group(2)!);
      yyyy = int.parse(dmy.group(3)!);
    } else if (ymd != null) {
      yyyy = int.parse(ymd.group(1)!);
      mm = int.parse(ymd.group(2)!);
      dd = int.parse(ymd.group(3)!);
    } else if (y != null) {
      yyyy = int.parse(y.group(1)!);
      mm = 1;
      dd = 1;
    } else {
      return null;
    }
    if (dd < 1 || dd > 31 || mm < 1 || mm > 12 || yyyy < 1900 || yyyy > 2100) {
      return null;
    }
    final now = DateTime.now();
    var age = now.year - yyyy;
    final hadBirthday = (now.month > mm) || (now.month == mm && now.day >= dd);
    if (!hadBirthday) age -= 1;
    return age < 0 ? null : age;
  }

  /// "16/09/1989 (37)"; tarih okunamazsa yalnız yıl, o da yoksa "-".
  String _birthText(int? age) {
    final s = widget.birthDate.trim();
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
    final ageText = age == null ? '' : ' ($age)';
    if (m != null) return '${m[3]}/${m[2]}/${m[1]}$ageText';
    final y = RegExp(r'(\d{4})').firstMatch(s)?.group(1);
    return y == null ? '-' : '$y$ageText';
  }

  /// "175 cm · 80 kg"; biri yoksa yalnız diğeri, ikisi de yoksa "-".
  String _bodyText() {
    final parts = [
      if (widget.height != null) '${widget.height} cm',
      if (widget.weight != null) '${widget.weight} kg',
    ];
    return parts.isEmpty ? '-' : parts.join(' · ');
  }

  String _normalizeUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return 'https://$url';
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).trUpper;
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).trUpper;
  }

  int _readInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    final s = v.toString().replaceAll('\u0000', '').trim();
    return int.tryParse(s) ??
        double.tryParse(s.replaceAll(',', '.'))?.toInt() ??
        0;
  }

  // ---------------------------------------------------------------------------
  // Veri
  // ---------------------------------------------------------------------------

  static final _uuidLike = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Oyuncunun sezon bazında istatistikleri:
  /// - Gol/asist/kart/maçın adamı: match_events
  /// - Oynanan maç: esamede (match_rosters) olduğu ya da olayı bulunan bitmiş
  ///   maçlar
  /// Olayı olmayan sezonlarda player_season_stats kayıtları kullanılır.
  /// Kart oyuncu id'siyle açılır (telefonla eşleştirme yok).
  Future<String?> _resolvePlayerId(String key) async =>
      _uuidLike.hasMatch(key) ? key : null;

  Future<Map<String, _StatTotals>> _loadTotalsBySeason(String pid) async {
    final events = <Map<String, dynamic>>[];
    final rosterMatchIds = <String>{};
    try {
      final res = await _sb
          .from('match_events')
          .select(
            'match_id, event_type, player_id, assist_player_id, is_own_goal',
          )
          .or('player_id.eq.$pid,assist_player_id.eq.$pid');
      events.addAll(res.cast<Map<String, dynamic>>());
    } catch (_) {}
    try {
      final res = await _sb
          .from('match_rosters')
          .select('match_id')
          .eq('player_id', pid);
      for (final r in res) {
        final id = (r['match_id'] ?? '').toString();
        if (id.isNotEmpty) rosterMatchIds.add(id);
      }
    } catch (_) {}

    final matchIds = {
      ...rosterMatchIds,
      for (final e in events) (e['match_id'] ?? '').toString(),
    }..remove('');

    final seasonByMatch = <String, String>{};
    final finished = <String>{};
    if (matchIds.isNotEmpty) {
      try {
        final res = await _sb
            .from('matches')
            .select('id, season_id, status')
            .inFilter('id', matchIds.toList());
        for (final m in res) {
          final id = (m['id'] ?? '').toString();
          final sid = (m['season_id'] ?? '').toString();
          if (id.isEmpty || sid.isEmpty) continue;
          // Ertelenen / iptal maç oynanmadı: hiçbir sayıya katılmaz.
          final st = (m['status'] ?? '').toString();
          if (st == 'cancelled' || st == 'postponed') continue;
          seasonByMatch[id] = sid;
          if ((m['status'] ?? '').toString() == 'finished') finished.add(id);
        }
      } catch (_) {}
    }

    final out = <String, _StatTotals>{};
    void add(String? matchId, _StatTotals t) {
      final sid = seasonByMatch[matchId ?? ''];
      if (sid == null) return;
      out[sid] = (out[sid] ?? const _StatTotals()) + t;
    }

    // Oynanan maç: esamede olduğu ya da olayı olan bitmiş maçlar (tekil).
    final played = {
      ...rosterMatchIds,
      for (final e in events)
        if ((e['player_id'] ?? '').toString() == pid)
          (e['match_id'] ?? '').toString(),
    }.where(finished.contains);
    for (final mid in played) {
      add(mid, const _StatTotals(matches: 1));
    }

    final yellowMatches = <String>{};
    for (final e in events) {
      final mid = (e['match_id'] ?? '').toString();
      final type = (e['event_type'] ?? '').toString();
      final isScorer = (e['player_id'] ?? '').toString() == pid;
      final isAssist = (e['assist_player_id'] ?? '').toString() == pid;
      if (type == 'goal') {
        if (isScorer && e['is_own_goal'] != true) {
          add(mid, const _StatTotals(goals: 1));
        }
        if (isAssist) add(mid, const _StatTotals(assists: 1));
      } else if (isScorer) {
        switch (type) {
          case 'assist':
            add(mid, const _StatTotals(assists: 1));
          case 'yellow_card':
            // Aynı maçta ikinci sarı: iki sarı yerine bir kırmızı sayılır.
            add(
              mid,
              yellowMatches.add(mid)
                  ? const _StatTotals(yellow: 1)
                  : const _StatTotals(yellow: -1, red: 1),
            );
          case 'red_card':
            add(mid, const _StatTotals(red: 1));
          case 'man_of_the_match':
            add(mid, const _StatTotals(motm: 1));
        }
      }
    }

    // Olayı olmayan sezonlar için kayıtlı sezon istatistikleri (ör. mock veri).
    try {
      final res = await _sb
          .from('player_season_stats')
          .select()
          .eq('player_id', pid);
      for (final r in res) {
        final sid = (r['season_id'] ?? '').toString();
        if (sid.isEmpty || out.containsKey(sid)) continue;
        out[sid] = _StatTotals(
          matches: _readInt(r['matches_played']),
          goals: _readInt(r['goals']),
          assists: _readInt(r['assists']),
          yellow: _readInt(r['yellow_cards']),
          red: _readInt(r['red_cards']),
        );
      }
    } catch (_) {}

    return out;
  }

  /// Oyuncunun onaylı gol videoları, en yeni maç üstte. Kesit oyuncuya
  /// (player_id) ya da oyuncunun golüne (match_event_id) bağlıdır.
  Future<List<_GoalClip>> _loadGoals() async {
    final pid = await _resolvePlayerId(widget.playerPhone.trim());
    if (pid == null || pid.isEmpty) return const [];
    const cols =
        'id, match_id, minute, added_minute, video_id, start_sec, end_sec, description, '
        'player_id';
    final rows = <String, Map<String, dynamic>>{};
    try {
      final res = await _sb
          .from('match_highlights')
          .select(cols)
          .eq('status', 'approved')
          .eq('kind', 'goal')
          .eq('player_id', pid);
      for (final r in res) {
        rows[r['id'].toString()] = r;
      }
    } catch (_) {}
    try {
      final ev = await _sb
          .from('match_events')
          .select('id')
          .eq('player_id', pid)
          .eq('event_type', 'goal')
          .not('is_own_goal', 'is', true);
      final ids = [for (final e in ev) e['id'].toString()];
      if (ids.isNotEmpty) {
        final res = await _sb
            .from('match_highlights')
            .select(cols)
            .eq('status', 'approved')
            .eq('kind', 'goal')
            .inFilter('match_event_id', ids);
        for (final r in res) {
          // Kesit başka bir oyuncuya atanmışsa onun golüdür.
          final owner = (r['player_id'] ?? '').toString();
          if (owner.isNotEmpty && owner != pid) continue;
          rows[r['id'].toString()] = r;
        }
      }
    } catch (_) {}
    if (rows.isEmpty) return const [];

    final matchById = <String, Map<String, dynamic>>{};
    try {
      final res = await _sb
          .from('matches')
          .select(
            'id, match_date, week, home_score, away_score, leagues(name), '
            'home:teams!matches_home_team_id_fkey(name), '
            'away:teams!matches_away_team_id_fkey(name)',
          )
          .inFilter(
            'id',
            {for (final r in rows.values) r['match_id']}.toList(),
          );
      for (final m in res) {
        matchById[m['id'].toString()] = m;
      }
    } catch (_) {}

    String name(dynamic v) =>
        v is Map ? (v['name'] ?? '').toString().trim() : '';
    final out = <_GoalClip>[];
    for (final r in rows.values) {
      final m = matchById[r['match_id'].toString()];
      if (m == null) continue;
      out.add(
        _GoalClip(
          id: r['id'].toString(),
          videoId: r['video_id'].toString(),
          startSec: _readInt(r['start_sec']),
          endSec: _readInt(r['end_sec']),
          minute: r['minute'] == null ? null : _readInt(r['minute']),
          addedMinute: r['added_minute'] == null
              ? null
              : _readInt(r['added_minute']),
          description: (r['description'] ?? '').toString().trim(),
          home: name(m['home']),
          away: name(m['away']),
          homeScore: m['home_score'] == null ? null : _readInt(m['home_score']),
          awayScore: m['away_score'] == null ? null : _readInt(m['away_score']),
          date: DateTime.tryParse((m['match_date'] ?? '').toString()),
          week: m['week'] == null ? null : _readInt(m['week']),
          league: name(m['leagues']),
        ),
      );
    }
    // En yeni maç üstte; aynı maçta son gol üstte.
    out.sort((a, b) {
      final da = a.date, db = b.date;
      if (da != null && db != null && da != db) return db.compareTo(da);
      if (da == null && db != null) return 1;
      if (da != null && db == null) return -1;
      return (b.minute ?? b.startSec).compareTo(a.minute ?? a.startSec);
    });
    return out;
  }

  Future<_PlayerCardData> _load() async {
    final playerKey = widget.playerPhone.trim();
    if (playerKey.isEmpty) return _PlayerCardData.empty();

    final pid = await _resolvePlayerId(playerKey);
    if (pid == null || pid.isEmpty) return _PlayerCardData.empty();
    final totalsBySeason = await _loadTotalsBySeason(pid);

    // Sezon başına oynadığı takım(lar).
    final teamsBySeason = <String, List<String>>{};
    try {
      final links = await _sb
          .from('season_team_players')
          .select('season_id, team_id')
          .eq('player_id', pid);
      final teamIds = {for (final l in links) (l['team_id'] ?? '').toString()}
        ..remove('');
      final teamName = <String, String>{};
      if (teamIds.isNotEmpty) {
        final res = await _sb
            .from('teams')
            .select('id, name')
            .inFilter('id', teamIds.toList());
        for (final t in res) {
          teamName[(t['id'] ?? '').toString()] = (t['name'] ?? '')
              .toString()
              .trim();
        }
      }
      for (final l in links) {
        final sid = (l['season_id'] ?? '').toString();
        final n = teamName[(l['team_id'] ?? '').toString()] ?? '';
        if (sid.isEmpty || n.isEmpty) continue;
        final list = teamsBySeason.putIfAbsent(sid, () => []);
        if (!list.contains(n)) list.add(n);
      }
    } catch (_) {}

    // Maçı / esamesi olmasa da kayıtlı olduğu aktif sezonlar da listelenir.
    final seasonIds = {...totalsBySeason.keys, ...teamsBySeason.keys}.toList();

    final seasonById = <String, Map<String, dynamic>>{};
    final leagueById = <String, Map<String, dynamic>>{};
    if (seasonIds.isNotEmpty) {
      try {
        final res = await _sb
            .from('seasons')
            .select('id, name, league_id, start_date, is_active')
            .inFilter('id', seasonIds);
        for (final row in res) {
          final id = (row['id'] ?? '').toString().trim();
          if (id.isNotEmpty) seasonById[id] = row;
        }
      } catch (_) {}

      final leagueIds = {
        for (final s in seasonById.values)
          (s['league_id'] ?? '').toString().trim(),
      }..remove('');
      if (leagueIds.isNotEmpty) {
        try {
          final res = await _sb
              .from('leagues')
              .select('id, name')
              .inFilter('id', leagueIds.toList());
          for (final row in res) {
            final id = (row['id'] ?? '').toString().trim();
            if (id.isNotEmpty) leagueById[id] = row;
          }
        } catch (_) {}
      }
    }

    final byLeague = <String, _TournamentNode>{};
    var overall = const _StatTotals();
    for (final sid in seasonIds) {
      final totals = totalsBySeason[sid];
      final seasonRow = seasonById[sid];
      // İstatistiği olmayan kayıt: yalnız aktif sezondaysa gösterilir.
      if (totals == null && seasonRow?['is_active'] != true) continue;
      final entry = MapEntry(sid, totals ?? const _StatTotals());
      overall = overall + entry.value;
      final leagueId = (seasonRow?['league_id'] ?? '').toString().trim();
      final leagueName = (leagueById[leagueId]?['name'] ?? '')
          .toString()
          .trim();
      final node = byLeague.putIfAbsent(
        leagueId.isEmpty ? '__unknown__' : leagueId,
        () => _TournamentNode(
          name: leagueName.isEmpty ? 'Turnuva' : leagueName,
          seasons: [],
        ),
      );
      node.seasons.add(
        _SeasonNode(
          name: (seasonRow?['name'] ?? '').toString().trim().isEmpty
              ? 'Sezon'
              : seasonRow!['name'].toString().trim(),
          sortKey: (seasonRow?['start_date'] ?? seasonRow?['name'] ?? '')
              .toString(),
          totals: entry.value,
          teams: teamsBySeason[entry.key] ?? const [],
        ),
      );
    }

    // En yeni sezon üstte; turnuvalar en yeni sezonlarına göre sıralı.
    final tournaments = byLeague.values.toList();
    for (final t in tournaments) {
      t.seasons.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    }
    tournaments.sort(
      (a, b) => b.seasons.first.sortKey.compareTo(a.seasons.first.sortKey),
    );

    return _PlayerCardData(overall: overall, tournaments: tournaments);
  }

  // ---------------------------------------------------------------------------
  // Görünüm
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _bgDark,
      child: FutureBuilder<_PlayerCardData>(
        future: _future,
        builder: (context, snap) {
          final loading = snap.connectionState != ConnectionState.done;
          final data = snap.data ?? _PlayerCardData.empty();
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              _hero(context),
              Padding(
                // Üst kart ile sekmeler arası dar tutulur.
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FutureBuilder<List<_GoalClip>>(
                      future: _goals,
                      builder: (context, g) => _tabBar(g.data?.length ?? 0),
                    ),
                    const SizedBox(height: 10),
                    if (_tab == 3 && _showPositionsTab)
                      PlayerPositionsTab(
                        playerId: _cardPlayerId,
                        accent: _tone,
                      )
                    else if (_tab == 2)
                      _goalsTab()
                    else if (loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_tab == 0)
                      _summaryGrid(data.overall)
                    else if (data.tournaments.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: _panel(),
                        child: const Text(
                          'Henüz turnuva verisi yok.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _mid),
                        ),
                      )
                    else
                      _historyTable(data.tournaments),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Goller: dar satırlar (dakika, maç, tarih); dokununca ayrıntı açılır,
  /// videoya dokununca gol kesiti uygulama içi oynatıcıda açılır.
  Widget _goalsTab() {
    return FutureBuilder<List<_GoalClip>>(
      future: _goals,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final goals = snap.data ?? const <_GoalClip>[];
        if (goals.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: _panel(),
            child: const Text(
              'Henüz gol videosu yok.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _mid),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final g in goals) _goalRow(g)],
        );
      },
    );
  }

  Widget _goalRow(_GoalClip g) {
    final open = _openGoal == g.id;
    final score = g.homeScore == null || g.awayScore == null
        ? '–'
        : '${g.homeScore}–${g.awayScore}';
    final when = [
      if (g.date != null) DateFormat('d MMMM y', 'tr_TR').format(g.date!),
      if (g.week != null && g.week! > 0) '${g.week}. Hafta',
    ].join(' · ');
    final title =
        "${g.minute != null ? '${minuteLabel(g.minute, g.addedMinute)} ' : ''}Gol";
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: open
                ? _tone.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _openGoal = open ? null : g.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: _tone,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        g.minute != null
                            ? minuteLabel(g.minute, g.addedMinute)
                            : 'Gol',
                        style: TextStyle(
                          color: _on(_tone),
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${shortTeamName(g.home)} $score '
                            '${shortTeamName(g.away)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (when.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              when,
                              style: const TextStyle(
                                color: _mid,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.expand_more_rounded,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (open)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      onTap: () => openYoutubeClip(
                        context,
                        videoId: g.videoId,
                        startSec: g.startSec,
                        endSec: g.endSec,
                        title: title,
                      ),
                      child: BroadcastThumb(videoId: g.videoId, radius: 12),
                    ),
                    if (g.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        g.description,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (g.league.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.emoji_events_outlined,
                            size: 13,
                            color: _tone,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              g.league,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _mid,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _panel() => BoxDecoration(
    color: Colors.white.withValues(alpha: 0.04),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
  );

  /// Üst bölüm: solda büyük oyuncu görseli (~%62), sağda yaş / boy / kilo /
  /// doğum alt alta; altında isim ve mevki.
  Widget _hero(BuildContext context) {
    final photo = _normalizeUrl(widget.photoUrl);
    final number = widget.number.trim();
    final pos = widget.position.trim();
    final topInset = MediaQuery.paddingOf(context).top;
    final name = widget.name.trim().isEmpty ? '-' : widget.name.trim();
    final age = _ageFromBirthDate(widget.birthDate);
    final photoHeight = (MediaQuery.of(context).size.height * 0.26).clamp(
      212.0,
      244.0,
    );

    Widget info(IconData icon, String label, String value) => Expanded(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: _tone),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: const TextStyle(
                    color: _mid,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            // Değer sağa yaslı; etiket solda kalır.
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final hero = Container(
      decoration: BoxDecoration(
        // Turnuva renginin koyulaştırılmış degradesi; beyaz yazı okunur kalır.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(_primary, _bgDark, 0.45)!,
            Color.lerp(_primary, Colors.black, 0.5)!,
          ],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      // Tam ekran: üst bölüm durum çubuğunun altına uzanır.
      padding: EdgeInsets.fromLTRB(16, topInset + 44, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: photoHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 62,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: _bgDark,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _tone.withValues(alpha: 0.6),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _tone.withValues(alpha: 0.18),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: photo.isEmpty
                            ? Align(
                                alignment: const Alignment(0, -0.25),
                                child: Text(
                                  _initials(name),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 56,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              )
                            : WebSafeImage(
                                url: photo,
                                fit: BoxFit.cover,
                                fallbackIconSize: 48,
                              ),
                      ),
                      // İsim ve mevki görselin altında, okunsun diye koyulaşma.
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 28, 12, 10),
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(20),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x000F172A), Color(0xE60F172A)],
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text.rich(
                                TextSpan(
                                  text: name,
                                  children: [
                                    if (widget.playerId.isNotEmpty)
                                      WidgetSpan(
                                        alignment: PlaceholderAlignment.middle,
                                        child: VerifiedBadgeFor(
                                          playerId: widget.playerId,
                                          size: 19,
                                          leading: 6,
                                        ),
                                      ),
                                  ],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (number.isNotEmpty)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _tone,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '#$number',
                              style: TextStyle(
                                color: _on(_tone),
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 38,
                  child: Column(
                    children: [
                      // "16/09/1989 (37)"
                      info(
                        Icons.cake_outlined,
                        'Doğum Tarihi',
                        _birthText(age),
                      ),
                      const SizedBox(height: 8),
                      info(Icons.height_rounded, 'Boy / Kilo', _bodyText()),
                      const SizedBox(height: 8),
                      info(
                        Icons.sports_soccer_outlined,
                        'Ana Mevki',
                        (pos.isEmpty || pos == '-') &&
                                widget.mainPosition.trim().isEmpty
                            ? '-'
                            : positionLineLabels[positionLineOf(
                                widget.mainPosition,
                                pos,
                              )],
                      ),
                      const SizedBox(height: 8),
                      info(
                        Icons.my_location_rounded,
                        'Alt Mevki',
                        widget.subPosition.trim().isEmpty
                            ? '-'
                            : widget.subPosition.trim(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Stack(
      children: [
        hero,
        Positioned(
          top: topInset,
          right: 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.playerId.isNotEmpty)
                _IdentityMenu(
                  playerId: widget.playerId,
                  playerName: widget.name,
                ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                tooltip: 'Kapat',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryGrid(_StatTotals t) {
    Widget tile(String label, int value, IconData icon, Color color) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: 18),
            Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 24,
                height: 1.1,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _mid,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: [
        tile('Maç', t.matches, Icons.sports_soccer_rounded, _mid),
        tile('Gol', t.goals, Icons.sports_score_rounded, _accent),
        tile('Asist', t.assists, Icons.assistant_direction_rounded, _purple),
        tile('Maçın Adamı', t.motm, Icons.star_rounded, _yellow),
        tile('Sarı Kart', t.yellow, Icons.rectangle_rounded, _yellow),
        tile('Kırmızı Kart', t.red, Icons.rectangle_rounded, _red),
      ],
    );
  }

  /// Turnuva > sezon satırları; sütunlar: M G A S K.
  Widget _historyTable(List<_TournamentNode> tournaments) {
    const colW = 30.0;
    Widget cell(String v, {Color color = Colors.white, bool bold = false}) =>
        SizedBox(
          width: colW,
          child: Text(
            v,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        );

    Widget header() => Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Turnuva / Sezon',
              style: TextStyle(
                color: _mid,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (final h in const ['M', 'G', 'A', 'S', 'K'])
            cell(h, color: _mid, bold: true),
        ],
      ),
    );

    // Ağaç: turnuva başlık satırı, altında girintili sezonlar (takım adıyla).
    final children = <Widget>[header()];
    for (final t in tournaments) {
      children.add(
        Container(
          width: double.infinity,
          color: Colors.white.withValues(alpha: 0.04),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Row(
            children: [
              const Icon(Icons.emoji_events_outlined, size: 15, color: _accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      for (var i = 0; i < t.seasons.length; i++) {
        final sn = t.seasons[i];
        final last = i == t.seasons.length - 1;
        final x = sn.totals;
        children.add(
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Ağaç çizgisi: son sezonda yarıda biter (└), diğerlerinde ├.
                SizedBox(
                  width: 34,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 21,
                        top: 0,
                        bottom: last ? null : 0,
                        height: last ? 22 : null,
                        child: Container(
                          width: 1.5,
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      Positioned(
                        left: 21,
                        top: 21,
                        child: Container(
                          width: 9,
                          height: 1.5,
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                sn.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (sn.teams.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.shield_outlined,
                                      size: 11,
                                      color: _mid,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        sn.teams.join(', '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _mid,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        cell('${x.matches}'),
                        cell('${x.goals}', color: _accent, bold: true),
                        cell('${x.assists}', color: _purple, bold: true),
                        cell('${x.yellow}', color: _yellow),
                        cell('${x.red}', color: _red),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _panel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...children,
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: Text(
              'M: Maç  G: Gol  A: Asist  S: Sarı kart  K: Kırmızı kart',
              style: TextStyle(color: _mid, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerCardData {
  const _PlayerCardData({required this.overall, required this.tournaments});

  final _StatTotals overall;
  final List<_TournamentNode> tournaments;

  factory _PlayerCardData.empty() => const _PlayerCardData(
    overall: _StatTotals(),
    tournaments: <_TournamentNode>[],
  );
}

/// Oyuncu kartı › Goller satırı.
class _GoalClip {
  const _GoalClip({
    required this.id,
    required this.videoId,
    required this.startSec,
    required this.endSec,
    required this.minute,
    this.addedMinute,
    required this.description,
    required this.home,
    required this.away,
    required this.homeScore,
    required this.awayScore,
    required this.date,
    required this.week,
    required this.league,
  });

  final String id;
  final String videoId;
  final int startSec;
  final int endSec;
  final int? minute;
  final int? addedMinute;
  final String description;
  final String home;
  final String away;
  final int? homeScore;
  final int? awayScore;
  final DateTime? date;
  final int? week;
  final String league;
}

class _TournamentNode {
  _TournamentNode({required this.name, required this.seasons});

  final String name;
  final List<_SeasonNode> seasons;
}

class _SeasonNode {
  const _SeasonNode({
    required this.name,
    required this.sortKey,
    required this.totals,
    this.teams = const [],
  });

  final String name;
  final String sortKey;
  final _StatTotals totals;
  final List<String> teams;
}

class _StatTotals {
  const _StatTotals({
    this.matches = 0,
    this.goals = 0,
    this.assists = 0,
    this.yellow = 0,
    this.red = 0,
    this.motm = 0,
  });

  final int matches;
  final int goals;
  final int assists;
  final int yellow;
  final int red;
  final int motm;

  _StatTotals operator +(_StatTotals other) {
    return _StatTotals(
      matches: matches + other.matches,
      goals: goals + other.goals,
      assists: assists + other.assists,
      yellow: yellow + other.yellow,
      red: red + other.red,
      motm: motm + other.motm,
    );
  }
}

/// Oyuncu kartındaki kimlik menüsü: onaylı değilse "Kimliği okut" (giriş
/// yapan herkes, uygulamada); onaylıysa admin ve kurucu başkana "Onayı
/// kaldır". Menüde seçenek yoksa görünmez.
class _IdentityMenu extends StatefulWidget {
  const _IdentityMenu({required this.playerId, required this.playerName});

  final String playerId;
  final String playerName;

  @override
  State<_IdentityMenu> createState() => _IdentityMenuState();
}

class _IdentityMenuState extends State<_IdentityMenu> {
  bool _verified = false;
  bool _canUnverify = false;
  bool _ready = false;

  bool get _loggedIn {
    final u = Supabase.instance.client.auth.currentUser;
    return u != null && !u.isAnonymous;
  }

  @override
  void initState() {
    super.initState();
    IdentityService.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    IdentityService.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!_loggedIn) return;
    try {
      final v = await IdentityService.isVerified(widget.playerId);
      final can = v && await IdentityService.canUnverify(widget.playerId);
      if (!mounted) return;
      setState(() {
        _verified = v;
        _canUnverify = can;
        _ready = true;
      });
    } catch (_) {}
  }

  Future<void> _unverify() async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Onayı kaldır',
      message:
          '${widget.playerName} profilinin kimlik onayı kaldırılsın mı? '
          'Kimlik yeniden okutulana kadar profil onaysız görünür.',
      confirmLabel: 'KALDIR',
      icon: Icons.gpp_bad_outlined,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await IdentityService.unverify(widget.playerId);
      messenger.showSnackBar(
        const SnackBar(content: Text('Kimlik onayı kaldırıldı.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(IdentityService.errorText(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || !IdentityAccess.visibleIn(context)) {
      return const SizedBox.shrink();
    }
    // Başkasının kimliğini admin, kurucu başkan ve bölge sorumlusu okutur;
    // diğerleri yalnız kendi profilinde.
    final session = AppSession.of(context).value;
    final canRead =
        !_verified &&
        !kIsWeb &&
        (session.hasManagementPanel || session.playerId == widget.playerId);
    if (!canRead && !_canUnverify) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Kimlik',
      icon: Icon(
        _verified ? Icons.verified_rounded : Icons.verified_outlined,
        color: _verified ? kVerifiedBlue : Colors.white70,
      ),
      color: const Color(0xFF1E293B),
      onSelected: (v) {
        if (v == 'read') {
          IdentityVerifyScreen.open(
            context,
            expectedPlayerId: widget.playerId,
            expectedName: widget.playerName,
          );
        } else if (v == 'unverify') {
          _unverify();
        }
      },
      itemBuilder: (_) => [
        if (canRead)
          const PopupMenuItem(
            value: 'read',
            child: Text('Kimliği okut', style: TextStyle(color: Colors.white)),
          ),
        if (_canUnverify)
          const PopupMenuItem(
            value: 'unverify',
            child: Text(
              'Onayı kaldır',
              style: TextStyle(color: Color(0xFFF87171)),
            ),
          ),
      ],
    );
  }
}
