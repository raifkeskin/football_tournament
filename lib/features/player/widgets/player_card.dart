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

  /// Özet › Bu sezon sekmesi: -1 toplam, diğerleri turnuva sırası.
  int _seasonTab = -1;

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

  /// "13.06.1987"; tarih okunamazsa yalnız yıl, o da yoksa "-".
  String _birthDateText() {
    final s = widget.birthDate.trim();
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
    if (m != null) return '${m[3]}.${m[2]}.${m[1]}';
    final dmy = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$').firstMatch(s);
    if (dmy != null) {
      return '${dmy[1]!.padLeft(2, '0')}.${dmy[2]!.padLeft(2, '0')}.${dmy[3]}';
    }
    return RegExp(r'(\d{4})').firstMatch(s)?.group(1) ?? '-';
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
    final startedMatchIds = <String>{};
    try {
      final res = await _sb
          .from('match_events')
          .select(
            'match_id, event_type, player_id, assist_player_id, '
            'sub_in_player_id, is_own_goal, minute',
          )
          .or(
            'player_id.eq.$pid,assist_player_id.eq.$pid,'
            'sub_in_player_id.eq.$pid',
          );
      events.addAll(res.cast<Map<String, dynamic>>());
    } catch (_) {}
    try {
      final res = await _sb
          .from('match_rosters')
          .select('match_id, is_starting')
          .eq('player_id', pid);
      for (final r in res) {
        final id = (r['match_id'] ?? '').toString();
        if (id.isEmpty) continue;
        rosterMatchIds.add(id);
        if (r['is_starting'] == true) startedMatchIds.add(id);
      }
    } catch (_) {}

    final matchIds = {
      ...rosterMatchIds,
      for (final e in events) (e['match_id'] ?? '').toString(),
    }..remove('');

    // Maç süresi (dakika) sezonun devre süresinden.
    final periodBySeason = <String, int>{};

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

    final seasonIdsForPeriods = seasonByMatch.values.toSet();
    if (seasonIdsForPeriods.isNotEmpty) {
      try {
        final res = await _sb
            .from('seasons')
            .select('id, match_period_duration')
            .inFilter('id', seasonIdsForPeriods.toList());
        for (final r in res) {
          periodBySeason[(r['id'] ?? '').toString()] = _readInt(
            r['match_period_duration'],
          );
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

    // İlk 11 ve dakika: ilk 11'de başladıysa 0. dakikadan, oyuna girdiyse
    // giriş dakikasından; oyundan çıkış ya da kırmızı kartta biter. Dakikası
    // girilmemiş değişiklikle giren oyuncuya dakika yazılmaz.
    int? minuteOf(Map<String, dynamic> e) =>
        e['minute'] == null ? null : _readInt(e['minute']);
    for (final mid in finished) {
      final started = startedMatchIds.contains(mid);
      if (started) add(mid, const _StatTotals(starts: 1));
      final duration = 2 * (periodBySeason[seasonByMatch[mid]] ?? 0);
      final mine = [
        for (final e in events)
          if ((e['match_id'] ?? '').toString() == mid) e,
      ];
      int? inAt = started ? 0 : null;
      if (!started) {
        for (final e in mine) {
          if (e['event_type'] == 'substitution' &&
              (e['sub_in_player_id'] ?? '').toString() == pid) {
            inAt = minuteOf(e);
          }
        }
      }
      if (inAt == null || duration <= 0) continue;
      var outAt = duration;
      for (final e in mine) {
        final type = (e['event_type'] ?? '').toString();
        final isOut =
            (type == 'substitution' || type == 'red_card') &&
            (e['player_id'] ?? '').toString() == pid;
        final m = minuteOf(e);
        if (isOut && m != null && m < outAt) outAt = m;
      }
      final mins = (outAt - inAt).clamp(0, duration);
      add(mid, _StatTotals(minutes: mins));
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

    // Sezon başına oynadığı takım(lar); bu sezonun armaları için id ve logo.
    final teamsBySeason = <String, List<String>>{};
    final teamIdBySeason = <String, String>{};
    final teamName = <String, String>{};
    final teamLogo = <String, String>{};
    try {
      final links = await _sb
          .from('season_team_players')
          .select('season_id, team_id, is_active')
          .eq('player_id', pid);
      final teamIds = {for (final l in links) (l['team_id'] ?? '').toString()}
        ..remove('');
      if (teamIds.isNotEmpty) {
        final res = await _sb
            .from('teams')
            .select('id, name, logo_url')
            .inFilter('id', teamIds.toList());
        for (final t in res) {
          final id = (t['id'] ?? '').toString();
          teamName[id] = (t['name'] ?? '').toString().trim();
          teamLogo[id] = (t['logo_url'] ?? '').toString().trim();
        }
      }
      for (final l in links) {
        final sid = (l['season_id'] ?? '').toString();
        final tid = (l['team_id'] ?? '').toString();
        final n = teamName[tid] ?? '';
        if (sid.isEmpty || n.isEmpty) continue;
        final list = teamsBySeason.putIfAbsent(sid, () => []);
        if (!list.contains(n)) list.add(n);
        // Sezon içinde takım değiştirdiyse güncel (aktif) kayıt.
        if (l['is_active'] != false || !teamIdBySeason.containsKey(sid)) {
          teamIdBySeason[sid] = tid;
        }
      }
    } catch (_) {}

    var foot = '';
    try {
      final r = await _sb
          .from('players')
          .select('preferred_foot')
          .eq('id', pid)
          .maybeSingle();
      foot = (r?['preferred_foot'] ?? '').toString().trim();
    } catch (_) {}

    // Maçı / esamesi olmasa da kayıtlı olduğu aktif sezonlar da listelenir.
    final seasonIds = {...totalsBySeason.keys, ...teamsBySeason.keys}.toList();

    final seasonById = <String, Map<String, dynamic>>{};
    final leagueById = <String, Map<String, dynamic>>{};
    if (seasonIds.isNotEmpty) {
      try {
        final res = await _sb
            .from('seasons')
            .select('id, name, league_id, start_date, is_active, deleted_at')
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
              .select('id, name, logo_url')
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

    // Bu sezon: kayıtlı olduğu aktif sezonlar (turnuva başına bir sekme).
    final current = <_CurrentEntry>[];
    for (final sid in seasonIds) {
      final row = seasonById[sid];
      if (row == null ||
          row['is_active'] != true ||
          row['deleted_at'] != null) {
        continue;
      }
      final league = leagueById[(row['league_id'] ?? '').toString().trim()];
      final tid = teamIdBySeason[sid] ?? '';
      current.add(
        _CurrentEntry(
          leagueName: (league?['name'] ?? 'Turnuva').toString().trim(),
          leagueLogo: (league?['logo_url'] ?? '').toString().trim(),
          teamId: tid,
          teamName: teamName[tid] ?? '',
          teamLogo: teamLogo[tid] ?? '',
          sortKey: (row['start_date'] ?? row['name'] ?? '').toString(),
          totals: totalsBySeason[sid] ?? const _StatTotals(),
        ),
      );
    }
    current.sort((a, b) => b.sortKey.compareTo(a.sortKey));

    return _PlayerCardData(
      overall: overall,
      tournaments: tournaments,
      current: current,
      foot: foot,
    );
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
              _hero(context, data),
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
                      PlayerPositionsTab(playerId: _cardPlayerId, accent: _tone)
                    else if (_tab == 2)
                      _goalsTab()
                    else if (loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_tab == 0)
                      _summary(data)
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

  /// Üst bölüm: ortada vesikalık fotoğraf (sağ üst köşesinde kimlik onayı),
  /// solda bu sezon oynadığı takımların armaları; altında ad soyad.
  Widget _hero(BuildContext context, _PlayerCardData data) {
    final photo = _normalizeUrl(widget.photoUrl);
    final topInset = MediaQuery.paddingOf(context).top;
    final name = widget.name.trim().isEmpty ? '-' : widget.name.trim();

    // Aynı takım birden çok turnuvadaysa arması bir kez gösterilir.
    final crests = <_CurrentEntry>[];
    for (final e in data.current) {
      if (e.teamId.isEmpty || crests.any((c) => c.teamId == e.teamId)) continue;
      crests.add(e);
    }

    Widget crest(_CurrentEntry e) => Tooltip(
      message: e.teamName,
      child: SizedBox(
        width: 40,
        height: 40,
        child: e.teamLogo.isEmpty
            ? const Icon(Icons.shield_outlined, color: _mid, size: 22)
            : WebSafeImage(
                url: _normalizeUrl(e.teamLogo),
                fit: BoxFit.contain,
                fallbackIconSize: 20,
              ),
      ),
    );

    return Container(
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
      ),
      // Tam ekran: üst bölüm durum çubuğunun altına uzanır; kapat düğmesi
      // fotoğraf satırının üstüne biner, bölüm dar kalır.
      padding: EdgeInsets.fromLTRB(16, topInset + 12, 16, 14),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < crests.length && i < 3; i++) ...[
                            if (i > 0) const SizedBox(height: 6),
                            crest(crests[i]),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 84,
                        height: 108,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: _bgDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _tone, width: 2),
                        ),
                        child: photo.isEmpty
                            ? Center(
                                child: Text(
                                  _initials(name),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              )
                            : WebSafeImage(
                                url: photo,
                                fit: BoxFit.cover,
                                fallbackIconSize: 32,
                              ),
                      ),
                      if (widget.playerId.isNotEmpty)
                        Positioned(
                          top: -12,
                          right: -12,
                          child: _IdentityMenu(
                            playerId: widget.playerId,
                            playerName: widget.name,
                          ),
                        ),
                    ],
                  ),
                  const Expanded(child: SizedBox()),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ],
          ),
          Positioned(
            top: -10,
            right: -8,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
              tooltip: 'Kapat',
            ),
          ),
        ],
      ),
    );
  }

  /// Özet: künye kutuları (3×2) ve bu sezonun istatistikleri; birden çok
  /// turnuvada oynuyorsa üstte "Toplam" + turnuva logoları sekmeleri.
  Widget _summary(_PlayerCardData data) {
    final age = _ageFromBirthDate(widget.birthDate);
    final pos = widget.position.trim();
    final line =
        (pos.isEmpty || pos == '-') && widget.mainPosition.trim().isEmpty
        ? '-'
        : positionLineLabels[positionLineOf(widget.mainPosition, pos)];
    final sub = widget.subPosition.trim();

    Widget info(String label, String value, [String note = '']) => Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.all(10),
        decoration: _panel(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _mid,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (note.isNotEmpty)
              Text(note, style: const TextStyle(color: _mid, fontSize: 11)),
          ],
        ),
      ),
    );

    Widget heading(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        t,
        style: const TextStyle(
          color: _mid,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('KÜNYE'),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              info(
                'Doğum tarihi',
                _birthDateText(),
                age == null ? '' : '$age yaş',
              ),
              const SizedBox(width: 8),
              info('Boy', widget.height == null ? '-' : '${widget.height} cm'),
              const SizedBox(width: 8),
              info('Kilo', widget.weight == null ? '-' : '${widget.weight} kg'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              info('Ana mevki', line),
              const SizedBox(width: 8),
              info('Alt mevki', sub.isEmpty ? '-' : sub),
              const SizedBox(width: 8),
              info('Kullandığı ayak', data.foot.isEmpty ? '-' : data.foot),
            ],
          ),
        ),
        const SizedBox(height: 18),
        heading('BU SEZON'),
        _seasonBox(data),
      ],
    );
  }

  /// Bu sezonun istatistik kutusu (8 değer); birden çok turnuvada sekmeli.
  Widget _seasonBox(_PlayerCardData data) {
    final entries = data.current;
    final multi = entries.length > 1;
    final sel = multi && _seasonTab < entries.length ? _seasonTab : -1;
    final _StatTotals t;
    final String caption;
    if (entries.isEmpty) {
      t = data.overall;
      caption = 'Bu sezon kaydı yok · tüm turnuvalar';
    } else if (!multi || sel >= 0) {
      final e = entries[multi ? sel : 0];
      t = e.totals;
      // Çok turnuvada turnuva adı sekmede yazar; altta yalnız takım.
      caption = multi
          ? e.teamName
          : [e.leagueName, if (e.teamName.isNotEmpty) e.teamName].join(' · ');
    } else {
      t = entries.fold(const _StatTotals(), (a, e) => a + e.totals);
      caption = 'Sezon toplamı · ${entries.length} turnuva';
    }

    Widget tab(int index, Widget child, String label) {
      final on = sel == index;
      return Semantics(
        selected: on,
        button: true,
        label: label,
        child: InkWell(
          onTap: () => setState(() => _seasonTab = index),
          child: Container(
            height: 48,
            constraints: const BoxConstraints(minWidth: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: on ? _tone : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Opacity(opacity: on ? 1 : 0.55, child: child),
          ),
        ),
      );
    }

    Widget logo(_CurrentEntry e) => SizedBox(
      width: 28,
      height: 28,
      child: e.leagueLogo.isEmpty
          ? const Icon(Icons.emoji_events_outlined, color: _yellow, size: 22)
          : WebSafeImage(
              url: _normalizeUrl(e.leagueLogo),
              fit: BoxFit.contain,
              isCircle: true,
              fallbackIconSize: 18,
            ),
    );

    Widget stat(String value, String label, Color color) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _mid,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Color.lerp(_bgDark, _tone, 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _tone.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (multi)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: _tone.withValues(alpha: 0.3)),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    tab(
                      -1,
                      const Text(
                        'Toplam',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      'Toplam',
                    ),
                    for (var i = 0; i < entries.length; i++)
                      tab(
                        i,
                        sel == i
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  logo(entries[i]),
                                  const SizedBox(width: 8),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 190,
                                    ),
                                    child: Text(
                                      entries[i].leagueName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : logo(entries[i]),
                        '${entries[i].leagueName}, ${entries[i].teamName}',
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  child: Text(
                    caption,
                    style: const TextStyle(
                      color: Color(0xFFC9D1E2),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Row(
                  children: [
                    stat('${t.matches}', 'Maç', Colors.white),
                    stat('${t.starts}', 'İlk 11', Colors.white),
                    stat("${t.minutes}'", 'Dakika', Colors.white),
                    stat('${t.goals}', 'Gol', _tone),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    stat('${t.assists}', 'Asist', _purple),
                    stat('${t.yellow}', 'Sarı kart', _yellow),
                    stat('${t.red}', 'Kırmızı kart', _red),
                    stat('${t.motm}', 'Maçın adamı', _yellow),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
  const _PlayerCardData({
    required this.overall,
    required this.tournaments,
    this.current = const [],
    this.foot = '',
  });

  final _StatTotals overall;
  final List<_TournamentNode> tournaments;

  /// Bu sezon oynadığı turnuvalar (aktif sezonlar), en yenisi önde.
  final List<_CurrentEntry> current;

  /// Kullandığı ayak.
  final String foot;

  factory _PlayerCardData.empty() => const _PlayerCardData(
    overall: _StatTotals(),
    tournaments: <_TournamentNode>[],
  );
}

/// Bu sezonun bir turnuvası: Özet'te sekme, üstte takım arması.
class _CurrentEntry {
  const _CurrentEntry({
    required this.leagueName,
    required this.leagueLogo,
    required this.teamId,
    required this.teamName,
    required this.teamLogo,
    required this.sortKey,
    required this.totals,
  });

  final String leagueName;
  final String leagueLogo;
  final String teamId;
  final String teamName;
  final String teamLogo;
  final String sortKey;
  final _StatTotals totals;
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
    this.starts = 0,
    this.minutes = 0,
  });

  final int matches;
  final int goals;
  final int assists;
  final int yellow;
  final int red;
  final int motm;

  /// İlk 11'de başladığı maç sayısı (esameden).
  final int starts;

  /// Oynadığı dakika: ilk 11 / oyuna giriş ile oyundan çıkış ya da kırmızı
  /// kart arası; maç süresi sezonun devre süresinin iki katı.
  final int minutes;

  _StatTotals operator +(_StatTotals other) {
    return _StatTotals(
      matches: matches + other.matches,
      goals: goals + other.goals,
      assists: assists + other.assists,
      yellow: yellow + other.yellow,
      red: red + other.red,
      motm: motm + other.motm,
      starts: starts + other.starts,
      minutes: minutes + other.minutes,
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
    // Seçenek yoksa yalnız onay rozeti (onaysızsa hiçbir şey).
    final badge = VerifiedBadgeFor(
      playerId: widget.playerId,
      size: 28,
      leading: 0,
    );
    if (!_ready || !IdentityAccess.visibleIn(context)) return badge;
    // Başkasının kimliğini admin, kurucu başkan ve bölge sorumlusu okutur;
    // diğerleri yalnız kendi profilinde.
    final session = AppSession.of(context).value;
    final canRead =
        !_verified &&
        !kIsWeb &&
        (session.hasManagementPanel || session.playerId == widget.playerId);
    if (!canRead && !_canUnverify) return badge;
    return PopupMenuButton<String>(
      tooltip: 'Kimlik',
      padding: EdgeInsets.zero,
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
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: _bgDark,
          shape: BoxShape.circle,
          border: Border.all(color: _bgDark, width: 1),
        ),
        alignment: Alignment.center,
        child: Icon(
          _verified ? Icons.verified_rounded : Icons.verified_outlined,
          color: _verified ? kVerifiedBlue : Colors.white70,
          size: 26,
        ),
      ),
    );
  }
}
