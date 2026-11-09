import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/custom_popup_selector.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../match/insights/match_insights.dart';
import '../../tournament/models/league.dart';
import '../week_awards.dart';
import '../widgets/week_awards_cards.dart';

/// Haftanın Enleri: kurucu başkan / bölge sorumlusu bir haftanın 11'ini ve
/// enlerini seçip tek bülten haberi olarak yayınlar. Hangi enlerin
/// bültende yer alacağına her hafta kendisi karar verir; seçim bir sonraki
/// haftaya hatırlanır. Adaylar maç puanından önerilir (week_award_pool).
class WeekAwardsScreen extends StatefulWidget {
  const WeekAwardsScreen({super.key, required this.tournaments});

  /// Kullanıcının yönetebildiği turnuvalar.
  final List<League> tournaments;

  @override
  State<WeekAwardsScreen> createState() => _WeekAwardsScreenState();
}

const _card = Color(0xFF1E293B);
const _kEleven = 'eleven';

/// Havuzdaki bir oyuncu: o haftaki maçı ve maç istatistiği.
class _P {
  const _P({
    required this.id,
    required this.teamId,
    required this.matchId,
    required this.line,
    required this.goals,
    required this.assists,
    required this.cards,
    required this.conceded,
    required this.rating,
    required this.number,
  });

  final String id;
  final String teamId;
  final String matchId;
  final int line;
  final int goals;
  final int assists;
  final int cards;
  final int conceded;
  final double rating;
  final String number;
}

class _M {
  const _M(this.id, this.homeId, this.awayId, this.hs, this.as);
  final String id;
  final String homeId;
  final String awayId;
  final int hs;
  final int as;
}

class _G {
  const _G({
    required this.id,
    required this.matchId,
    required this.teamId,
    required this.playerId,
    required this.label,
    required this.clip,
  });
  final String id;
  final String matchId;
  final String teamId;
  final String playerId;
  final String label;
  final Map<String, dynamic>? clip;
}

/// Seçim penceresindeki satır.
class _Option {
  const _Option(
    this.key,
    this.title,
    this.sub, {
    this.trailing = '',
    this.logo = '',
  });
  final String key;
  final String title;
  final String sub;
  final String trailing;
  final String logo;
}

class _WeekAwardsScreenState extends State<WeekAwardsScreen> {
  final _sb = Supabase.instance.client;
  final _shotKey = GlobalKey();
  final _scroll = ScrollController();

  String? _leagueId;
  String? _seasonId;
  Map<String, String> _regions = const {};
  String? _regionId;
  List<({String id, int week, String regionId})> _finished = const [];
  int? _week;
  bool _loading = false;
  bool _saving = false;
  bool _uploading = false;

  // Haftanın verisi.
  List<_P> _pool = const [];
  Map<String, _P> _byId = const {};
  List<_M> _matches = const [];
  List<_G> _goals = const [];
  Map<String, AwardTeam> _teams = const {};
  Map<String, AwardPerson> _people = const {};
  Map<String, List<String>> _moments = const {};
  Map<String, Map<String, List<String>>> _teamPhotos = const {};
  bool _exists = false;

  // Seçimler.
  Set<String> _enabled = {
    _kEleven,
    for (final k in AwardKind.values)
      if (k != AwardKind.fair) k.key,
  };
  String _formation = '4-3-3';
  int _outfield = 10;
  List<String?> _eleven = const [];
  final Map<AwardKind, String?> _pick = {};
  final Map<AwardKind, String> _photo = {};

  @override
  void initState() {
    super.initState();
    if (widget.tournaments.isNotEmpty) _pickLeague(widget.tournaments.first.id);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  bool get _fullAccess =>
      AppSession.of(context).value.canManageLeague(_leagueId);

  /// Yayınlanan bülten değiştirilmez (yalnız admin düzeltebilir).
  bool get _locked => _exists && !AppSession.of(context).value.isAdmin;

  League? get _league =>
      widget.tournaments.where((l) => l.id == _leagueId).firstOrNull;

  bool get _ratingsForEditor => matchInsightsVisible(context);

  // ---- Turnuva / bölge / hafta ------------------------------------------

  Future<void> _pickLeague(String leagueId) async {
    setState(() {
      _leagueId = leagueId;
      _seasonId = null;
      _regions = const {};
      _regionId = null;
      _finished = const [];
      _week = null;
      _pool = const [];
      _loading = true;
    });
    try {
      final seasons = await _sb
          .from('seasons')
          .select('id, is_active, start_date')
          .eq('league_id', leagueId)
          .isFilter('deleted_at', null)
          .order('start_date', ascending: false);
      if (seasons.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      final season = seasons.firstWhere(
        (s) => s['is_active'] == true,
        orElse: () => seasons.first,
      );
      final sid = season['id'].toString();
      final (regions, groups, matches) = await (
        _sb
            .from('season_regions')
            .select('id, name, sort_order')
            .eq('season_id', sid)
            .order('sort_order', ascending: true),
        _sb.from('groups').select('id, region_id').eq('season_id', sid),
        _sb
            .from('matches')
            .select('id, week, group_id')
            .eq('season_id', sid)
            .eq('status', 'finished')
            .isFilter('deleted_at', null)
            .not('week', 'is', null),
      ).wait;
      if (!mounted || _leagueId != leagueId) return;
      final session = AppSession.of(context).value;
      final full = session.canManageLeague(leagueId);
      final mine = {for (final r in session.ownedRegions) r.id};
      final regionOfGroup = {
        for (final g in groups)
          g['id'].toString(): (g['region_id'] ?? '').toString(),
      };
      setState(() {
        _seasonId = sid;
        _regions = {
          for (final r in regions)
            if (full || mine.contains(r['id'].toString()))
              r['id'].toString(): (r['name'] ?? '').toString(),
        };
        // Bölge sorumlusu tüm turnuva adına yayınlayamaz.
        _regionId = !full && _regions.isNotEmpty ? _regions.keys.first : null;
        _finished = [
          for (final m in matches)
            (
              id: m['id'].toString(),
              week: (m['week'] as num).toInt(),
              regionId: regionOfGroup[(m['group_id'] ?? '').toString()] ?? '',
            ),
        ];
        _loading = false;
      });
      final weeks = _weeks;
      if (weeks.isNotEmpty) _pickWeek(weeks.last);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Turnuva okunamadı: $e');
    }
  }

  List<int> get _weeks => {
    for (final m in _finished)
      if (_regionId == null || m.regionId == _regionId) m.week,
  }.toList()..sort();

  Future<void> _pickWeek(int week) async {
    final sid = _seasonId;
    if (sid == null) return;
    setState(() {
      _week = week;
      _pool = const [];
      _loading = true;
    });
    final ids = [
      for (final m in _finished)
        if (m.week == week && (_regionId == null || m.regionId == _regionId))
          m.id,
    ];
    try {
      final (pool, matches, goals, clips, media, news) = await (
        _sb.rpc(
          'week_award_pool',
          params: {
            'p_season_id': sid,
            'p_region_id': _regionId,
            'p_week': week,
          },
        ),
        _sb
            .from('matches')
            .select('id, home_team_id, away_team_id, home_score, away_score')
            .inFilter('id', ids),
        _sb
            .from('match_events')
            .select(
              'id, match_id, team_id, player_id, minute, added_minute, is_own_goal',
            )
            .inFilter('match_id', ids)
            .eq('event_type', 'goal'),
        _sb
            .from('match_highlights')
            .select(
              'match_event_id, video_id, start_sec, end_sec, clip_url, story_url',
            )
            .inFilter('match_id', ids)
            .eq('status', 'approved')
            .not('match_event_id', 'is', null),
        _sb
            .from('match_media')
            .select('match_id, team_id, media_type, url')
            .inFilter('match_id', ids)
            .inFilter('media_type', ['Önemli An', 'Takım Fotosu']),
        _sb
            .from('news')
            .select('week, region_id, auto_kind, auto_data')
            .eq('season_id', sid)
            .inFilter('auto_kind', ['week_awards', 'goal_of_week'])
            .order('week', ascending: false),
      ).wait;
      final poolRows = [
        for (final r in (pool as List? ?? const []))
          if (r is Map) r,
      ];
      final teamIds = <String>{
        for (final m in matches) ...[
          m['home_team_id'].toString(),
          m['away_team_id'].toString(),
        ],
      };
      final personIds = <String>{
        for (final r in poolRows) r['player_id'].toString(),
        for (final g in goals)
          if (g['player_id'] != null) g['player_id'].toString(),
      };
      final (teams, people) = await (
        _sb
            .from('teams')
            .select('id, name, logo_url, first_color')
            .inFilter('id', teamIds.toList()),
        personIds.isEmpty
            ? Future.value(const <Map<String, dynamic>>[])
            : _sb
                  .from('players')
                  .select('id, name, surname, photo_url')
                  .inFilter('id', personIds.toList()),
      ).wait;
      if (!mounted || _week != week) return;

      // Bir oyuncu haftada iki maç oynadıysa puanı yüksek olan.
      final byId = <String, _P>{};
      for (final r in poolRows) {
        final p = _P(
          id: r['player_id'].toString(),
          teamId: r['team_id'].toString(),
          matchId: r['match_id'].toString(),
          line: (r['line'] as num?)?.toInt() ?? 2,
          goals: (r['goals'] as num?)?.toInt() ?? 0,
          assists: (r['assists'] as num?)?.toInt() ?? 0,
          cards:
              ((r['yellows'] as num?)?.toInt() ?? 0) +
              ((r['reds'] as num?)?.toInt() ?? 0),
          conceded: (r['conceded'] as num?)?.toInt() ?? 0,
          rating: (r['rating'] as num?)?.toDouble() ?? 0,
          number: (r['number'] ?? '').toString(),
        );
        final prev = byId[p.id];
        if (prev == null || p.rating > prev.rating) byId[p.id] = p;
      }
      final list = byId.values.toList()
        ..sort((a, b) {
          final c = b.rating.compareTo(a.rating);
          return c != 0 ? c : b.goals.compareTo(a.goals);
        });

      final clipOf = {
        for (final c in clips)
          c['match_event_id'].toString(): <String, dynamic>{
            'video_id': c['video_id'],
            'start': c['start_sec'],
            'end': c['end_sec'],
            if ((c['clip_url'] ?? '').toString().isNotEmpty)
              'clip_url': c['clip_url'],
            if ((c['story_url'] ?? '').toString().isNotEmpty)
              'story_url': c['story_url'],
          },
      };
      final moments = <String, List<String>>{};
      final teamPhotos = <String, Map<String, List<String>>>{};
      for (final m in media) {
        final url = (m['url'] ?? '').toString().trim();
        if (url.isEmpty) continue;
        final mid = m['match_id'].toString();
        if (m['media_type'] == 'Önemli An') {
          (moments[mid] ??= []).add(url);
        } else {
          ((teamPhotos[mid] ??= {})[(m['team_id'] ?? '').toString()] ??= [])
              .add(url);
        }
      }
      bool sameRegion(Map n) =>
          (n['region_id'] ?? '').toString() == (_regionId ?? '');
      Map? thisWeek;
      Map? lastBulletin;
      String? goalOfWeek;
      for (final n in news) {
        if (!sameRegion(n)) continue;
        final d = n['auto_data'] is Map ? n['auto_data'] as Map : null;
        if (n['auto_kind'] == 'goal_of_week') {
          if (n['week'] == week) goalOfWeek = d?['event_id']?.toString();
          continue;
        }
        lastBulletin ??= d;
        if (n['week'] == week) thisWeek = d;
      }

      setState(() {
        _pool = list;
        _byId = byId;
        _matches = [
          for (final m in matches)
            _M(
              m['id'].toString(),
              m['home_team_id'].toString(),
              m['away_team_id'].toString(),
              (m['home_score'] as num?)?.toInt() ?? 0,
              (m['away_score'] as num?)?.toInt() ?? 0,
            ),
        ];
        _teams = {
          for (final t in teams)
            t['id'].toString(): AwardTeam(
              id: t['id'].toString(),
              name: (t['name'] ?? '').toString(),
              logo: (t['logo_url'] ?? '').toString().trim(),
              color: t['first_color']?.toString(),
            ),
        };
        _people = {
          for (final p in people)
            p['id'].toString(): AwardPerson(
              id: p['id'].toString(),
              name: [
                (p['name'] ?? '').toString().trim(),
                (p['surname'] ?? '').toString().trim(),
              ].where((e) => e.isNotEmpty).join(' '),
              photo: (p['photo_url'] ?? '').toString().trim(),
            ),
        };
        _goals = [
          for (final g in goals)
            if (g['is_own_goal'] != true && g['player_id'] != null)
              _G(
                id: g['id'].toString(),
                matchId: g['match_id'].toString(),
                teamId: (g['team_id'] ?? '').toString(),
                playerId: g['player_id'].toString(),
                label: _minute(g['minute'], g['added_minute']),
                clip: clipOf[g['id'].toString()],
              ),
        ];
        _moments = moments;
        _teamPhotos = teamPhotos;
        _exists = thisWeek != null;
        _applyDefaults(
          thisWeek ?? lastBulletin,
          restore: thisWeek != null,
          goalOfWeek: goalOfWeek,
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final msg = e is PostgrestException ? e.message : '$e';
      _snack('Hafta okunamadı: $msg');
    }
  }

  static String _minute(Object? m, Object? added) {
    final n = (m as num?)?.toInt() ?? 0;
    final a = (added as num?)?.toInt() ?? 0;
    if (n <= 0) return '';
    return a > 0 ? "$n+$a'" : "$n'";
  }

  // ---- Varsayılanlar ----------------------------------------------------

  /// Öneriler; bu haftanın bülteni varsa onun seçimleri geri yüklenir.
  /// [prev] önceki bültense yalnız hangi enlerin açık olduğu alınır.
  void _applyDefaults(Map? prev, {required bool restore, String? goalOfWeek}) {
    final en = prev?['enabled'];
    if (en is List && en.isNotEmpty) {
      _enabled = {for (final e in en) e.toString()};
    }

    // Maçlarda sahaya çıkan oyuncu sayısı (en sık görülen).
    final starters = <String, int>{};
    for (final p in _pool) {
      starters['${p.matchId}|${p.teamId}'] =
          (starters['${p.matchId}|${p.teamId}'] ?? 0) + 1;
    }
    final freq = <int, int>{};
    for (final n in starters.values) {
      freq[n] = (freq[n] ?? 0) + 1;
    }
    var size = 11;
    if (freq.isNotEmpty) {
      size = (freq.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .first
          .key;
    }
    _outfield = (size - 1).clamp(4, 10);
    _formation = formationOptions(_outfield).first;

    _pick.clear();
    _photo.clear();
    if (restore && prev != null) {
      final saved = WeekAwards.fromJson(prev);
      if (saved.hasEleven) {
        _formation = saved.formation;
        _outfield = saved.eleven.length - 1;
        _eleven = [
          for (final s in saved.eleven)
            _byId.containsKey(s.person.id) ? s.person.id : null,
        ];
      } else {
        _autoEleven();
      }
      for (final a in saved.awards) {
        _pick[a.kind] = switch (a.kind) {
          AwardKind.goal =>
            _goals
                .where(
                  (g) => g.playerId == a.person?.id && g.matchId == a.matchId,
                )
                .firstOrNull
                ?.id,
          AwardKind.match => a.matchId,
          AwardKind.team => '${a.matchId}|${a.team.id}',
          _ => a.person?.id,
        };
        _photo[a.kind] = a.photo;
      }
    } else {
      _autoEleven();
    }
    for (final k in AwardKind.values) {
      if (_pick[k] != null) continue;
      final opts = _options(k);
      if (k == AwardKind.fair || opts.isEmpty) continue;
      var key = opts.first.key;
      if (k == AwardKind.goal &&
          goalOfWeek != null &&
          opts.any((o) => o.key == goalOfWeek)) {
        key = goalOfWeek;
      }
      _setPick(k, key);
    }
  }

  /// 11'i boş başlatır: sorumlu her yere dokunup seçer (liste o mevkinin
  /// en yüksek puanlısından başlar).
  void _autoEleven() {
    final total = formationCounts(_formation).fold<int>(0, (a, b) => a + b) + 1;
    _eleven = List<String?>.filled(total, null);
  }

  void _setFormation(String f) {
    setState(() {
      // Aynı hattaki oyuncular yerinde kalır; açılan yerler puandan dolar.
      final byLine = <int, List<String>>{};
      for (var i = 0; i < _eleven.length; i++) {
        final id = _eleven[i];
        if (id != null) (byLine[formationLineOf(_formation, i)] ??= []).add(id);
      }
      _formation = f;
      final total = formationCounts(f).fold<int>(0, (a, b) => a + b) + 1;
      final out = List<String?>.filled(total, null);
      for (var i = 0; i < total; i++) {
        final l = byLine[formationLineOf(f, i)];
        if (l != null && l.isNotEmpty) out[i] = l.removeAt(0);
      }
      final used = out.whereType<String>().toSet();
      final rest = [for (final l in byLine.values) ...l];
      for (var i = 0; i < total; i++) {
        if (out[i] != null) continue;
        final line = formationLineOf(f, i);
        // Açılan yer boş kalır; yalnız önceden seçilmiş oyuncular yer değiştirir.
        final pick = rest
            .where(
              (id) =>
                  !used.contains(id) && (line == 0) == (_byId[id]?.line == 0),
            )
            .firstOrNull;
        if (pick != null) {
          out[i] = pick;
          used.add(pick);
          rest.remove(pick);
        }
      }
      _eleven = out;
    });
  }

  // ---- Adaylar ----------------------------------------------------------

  AwardTeam _team(String id) => _teams[id] ?? AwardTeam(id: id, name: 'Takım');
  AwardPerson _person(String id) =>
      _people[id] ?? AwardPerson(id: id, name: 'Oyuncu');
  _M? _match(String id) => _matches.where((m) => m.id == id).firstOrNull;

  String _scoreLine(_M m) =>
      '${_team(m.homeId).short} ${m.hs}-${m.as} ${_team(m.awayId).short}';

  String _rating(double r) => _ratingsForEditor ? r.toStringAsFixed(1) : '';

  static const _lineShort = ['KL', 'DF', 'OS', 'FV'];

  String _pSub(_P p) => [
    _team(p.teamId).short,
    if (p.goals > 0) '${p.goals} gol',
    if (p.assists > 0) '${p.assists} asist',
    if (p.cards > 0) '${p.cards} kart',
  ].join(' · ');

  List<_Option> _options(AwardKind k) {
    switch (k) {
      case AwardKind.player:
        return [
          for (final p in _pool)
            _Option(
              p.id,
              _person(p.id).name,
              _pSub(p),
              trailing: _rating(p.rating),
              logo: _team(p.teamId).logo,
            ),
        ];
      case AwardKind.keeper:
        final gks = _pool.where((p) => p.line == 0).toList()
          ..sort((a, b) {
            final c = a.conceded.compareTo(b.conceded);
            return c != 0 ? c : b.rating.compareTo(a.rating);
          });
        return [
          for (final p in gks)
            _Option(
              p.id,
              _person(p.id).name,
              '${_team(p.teamId).short} · ${p.conceded == 0 ? 'gol yemedi' : '${p.conceded} gol yedi'}',
              trailing: _rating(p.rating),
              logo: _team(p.teamId).logo,
            ),
        ];
      case AwardKind.fair:
        return [
          for (final p in _pool)
            if (p.cards == 0)
              _Option(
                p.id,
                _person(p.id).name,
                _team(p.teamId).short,
                trailing: _rating(p.rating),
                logo: _team(p.teamId).logo,
              ),
        ];
      case AwardKind.goal:
        final gs = [..._goals]
          ..sort((a, b) {
            if ((a.clip != null) != (b.clip != null)) {
              return a.clip != null ? -1 : 1;
            }
            return (_byId[b.playerId]?.rating ?? 0).compareTo(
              _byId[a.playerId]?.rating ?? 0,
            );
          });
        return [
          for (final g in gs)
            if (_match(g.matchId) case final m?)
              _Option(
                g.id,
                [
                  _person(g.playerId).name,
                  g.label,
                ].where((e) => e.isNotEmpty).join(' · '),
                '${_scoreLine(m)}${g.clip == null ? '' : ' · ▶ video'}',
                logo: _team(g.teamId).logo,
              ),
        ];
      case AwardKind.match:
        final ms = [..._matches]
          ..sort((a, b) {
            final c = (b.hs + b.as).compareTo(a.hs + a.as);
            return c != 0
                ? c
                : (a.hs - a.as).abs().compareTo((b.hs - b.as).abs());
          });
        return [
          for (final m in ms)
            _Option(m.id, _scoreLine(m), '${m.hs + m.as} gol'),
        ];
      case AwardKind.team:
        final rows = <(_Option, int)>[];
        for (final m in _matches) {
          for (final home in [true, false]) {
            final id = home ? m.homeId : m.awayId;
            final f = home ? m.hs : m.as;
            final a = home ? m.as : m.hs;
            rows.add((
              _Option(
                '${m.id}|$id',
                _team(id).short,
                '$f-$a ${_team(home ? m.awayId : m.homeId).short}',
                logo: _team(id).logo,
              ),
              (f - a) * 100 + f,
            ));
          }
        }
        rows.sort((a, b) => b.$2.compareTo(a.$2));
        return [for (final r in rows) r.$1];
    }
  }

  /// Ödüle uygun hazır fotoğraflar (ilki varsayılan).
  List<String> _photosFor(AwardKind k) {
    final key = _pick[k];
    if (key == null) return const [];
    switch (k) {
      case AwardKind.match:
        return const [];
      case AwardKind.team:
        final parts = key.split('|');
        return [
          ...?_teamPhotos[parts.first]?[parts.last],
          ...?_teamPhotos[parts.first]?[''],
        ];
      case AwardKind.goal:
        final g = _goals.where((g) => g.id == key).firstOrNull;
        if (g == null) return const [];
        return [
          if (_person(g.playerId).photo.isNotEmpty) _person(g.playerId).photo,
          ...?_moments[g.matchId],
        ];
      default:
        final p = _byId[key];
        return [
          if (_person(key).photo.isNotEmpty) _person(key).photo,
          if (p != null) ...?_moments[p.matchId],
        ];
    }
  }

  void _setPick(AwardKind k, String key) {
    _pick[k] = key;
    final photos = _photosFor(k);
    _photo[k] = photos.isEmpty ? '' : photos.first;
  }

  // ---- Bülten verisi ----------------------------------------------------

  ElevenSlot? _slot(String? id) {
    if (id == null) return null;
    final p = _byId[id];
    return ElevenSlot(
      person: _person(id),
      team: _team(p?.teamId ?? ''),
      rating: p?.rating,
      number: p?.number ?? '',
    );
  }

  WeekAward? _award(AwardKind k) {
    final key = _pick[k];
    if (key == null) return null;
    final photo = _photo[k] ?? '';
    switch (k) {
      case AwardKind.goal:
        final g = _goals.where((g) => g.id == key).firstOrNull;
        if (g == null) return null;
        final m = _match(g.matchId);
        return WeekAward(
          kind: k,
          team: _team(g.teamId),
          person: _person(g.playerId),
          photo: photo,
          stats: [
            if (g.label.isNotEmpty) g.label,
            if (m != null) '${m.hs}-${m.as}',
          ],
          home: m == null ? null : _team(m.homeId),
          away: m == null ? null : _team(m.awayId),
          hs: m?.hs,
          as: m?.as,
          matchId: m?.id,
          clip: g.clip,
        );
      case AwardKind.match:
        final m = _match(key);
        if (m == null) return null;
        return WeekAward(
          kind: k,
          team: _team(m.homeId),
          stats: ['${m.hs + m.as} GOL'],
          home: _team(m.homeId),
          away: _team(m.awayId),
          hs: m.hs,
          as: m.as,
          matchId: m.id,
        );
      case AwardKind.team:
        final parts = key.split('|');
        final m = _match(parts.first);
        if (m == null) return null;
        final home = m.homeId == parts.last;
        final f = home ? m.hs : m.as;
        final a = home ? m.as : m.hs;
        return WeekAward(
          kind: k,
          team: _team(parts.last),
          photo: photo,
          stats: ['$f GOL', if (a == 0) 'GOL YEMEDİ'],
          home: _team(m.homeId),
          away: _team(m.awayId),
          hs: m.hs,
          as: m.as,
          matchId: m.id,
        );
      default:
        final p = _byId[key];
        if (p == null) return null;
        final m = _match(p.matchId);
        return WeekAward(
          kind: k,
          team: _team(p.teamId),
          person: _person(key),
          photo: photo,
          stats: switch (k) {
            AwardKind.keeper => [
              if (p.conceded == 0) 'GOL YEMEDİ',
              if (m != null) '${m.hs}-${m.as}',
            ],
            AwardKind.fair => ['FAIR PLAY'],
            _ => [
              if (p.goals > 0) '${p.goals} GOL',
              if (p.assists > 0) '${p.assists} ASİST',
              if (m != null) '${m.hs}-${m.as}',
            ],
          },
          rating: k == AwardKind.fair ? null : p.rating,
          home: m == null ? null : _team(m.homeId),
          away: m == null ? null : _team(m.awayId),
          hs: m?.hs,
          as: m?.as,
          matchId: m?.id,
        );
    }
  }

  WeekAwards _bulletin() {
    final l = _league;
    final eleven = _enabled.contains(_kEleven)
        ? [for (final id in _eleven) _slot(id)]
        : const <ElevenSlot?>[];
    return WeekAwards(
      week: _week ?? 0,
      leagueName: l?.name ?? '',
      leagueLogo: l?.logoUrl ?? '',
      formation: eleven.isEmpty ? '' : _formation,
      eleven: eleven.whereType<ElevenSlot>().toList(),
      awards: [
        for (final k in AwardKind.values)
          if (_enabled.contains(k.key)) ?_award(k),
      ],
    );
  }

  /// Yayın öncesi eksik: açık olup seçimi yapılmamış enler.
  String? get _missing {
    if (_enabled.isEmpty) return 'Bültene en az bir en ekle.';
    if (_enabled.contains(_kEleven) && _eleven.any((e) => e == null)) {
      return "Haftanın 11'inde boş yer var.";
    }
    for (final k in AwardKind.values) {
      if (_enabled.contains(k.key) && _award(k) == null) {
        return '${k.full} seçilmedi.';
      }
    }
    return null;
  }

  // ---- Etkileşim --------------------------------------------------------

  Future<String?> _choose(
    String title,
    List<_Option> options,
    String? current,
  ) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: options.isEmpty
                  ? const Center(
                      child: Text(
                        'Bu hafta aday yok.',
                        style: TextStyle(color: kAdminMuted),
                      ),
                    )
                  : ListView.builder(
                      controller: scroll,
                      itemCount: options.length,
                      itemBuilder: (ctx, i) {
                        final o = options[i];
                        final on = o.key == current;
                        return ListTile(
                          onTap: () => Navigator.pop(ctx, o.key),
                          leading: SizedBox(
                            width: 32,
                            height: 32,
                            child: o.logo.isEmpty
                                ? const Icon(
                                    Icons.shield_outlined,
                                    color: Colors.white38,
                                  )
                                : WebSafeImage(
                                    url: o.logo,
                                    fit: BoxFit.contain,
                                  ),
                          ),
                          title: Text(
                            o.title,
                            style: TextStyle(
                              color: on ? kAdminAccent : Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            o.sub,
                            style: const TextStyle(
                              color: kAdminMuted,
                              fontSize: 12,
                            ),
                          ),
                          trailing: o.trailing.isEmpty
                              ? (on
                                    ? const Icon(
                                        Icons.check_rounded,
                                        color: kAdminAccent,
                                      )
                                    : null)
                              : Text(
                                  o.trailing,
                                  style: const TextStyle(
                                    color: kAdminAmber,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeSlot(int i) async {
    final line = formationLineOf(_formation, i);
    final used = {
      for (var j = 0; j < _eleven.length; j++)
        if (j != i && _eleven[j] != null) _eleven[j]!,
    };
    final list = _pool.where((p) => !used.contains(p.id)).toList()
      ..sort((a, b) {
        final la = a.line == line ? 0 : 1, lb = b.line == line ? 0 : 1;
        if (la != lb) return la.compareTo(lb);
        return b.rating.compareTo(a.rating);
      });
    final key = await _choose(
      '${const ['Kaleci', 'Defans', 'Orta saha', 'Forvet'][line]} seç',
      [
        for (final p in list)
          _Option(
            p.id,
            _person(p.id).name,
            '${_lineShort[p.line.clamp(0, 3)]} · ${_pSub(p)}',
            trailing: _rating(p.rating),
            logo: _team(p.teamId).logo,
          ),
      ],
      _eleven[i],
    );
    if (key == null || !mounted) return;
    setState(() {
      final next = [..._eleven];
      next[i] = key;
      _eleven = next;
    });
  }

  Future<void> _changeAward(AwardKind k) async {
    final key = await _choose(k.full, _options(k), _pick[k]);
    if (key == null || !mounted) return;
    setState(() => _setPick(k, key));
  }

  Future<void> _uploadPhoto(AwardKind k) async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (f == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final url = await SupabaseImageUploadService().uploadImage(
        f,
        folder: MediaFolder.news,
      );
      if (url == null) throw Exception('Fotoğraf yüklenemedi.');
      if (!mounted) return;
      setState(() => _photo[k] = url);
    } catch (e) {
      if (mounted) _snack('Fotoğraf yüklenemedi: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ---- Yayın ------------------------------------------------------------

  Future<void> _publish() async {
    final sid = _seasonId;
    final week = _week;
    final missing = _missing;
    if (sid == null || week == null) return;
    if (missing != null) {
      _snack(missing);
      return;
    }
    setState(() => _saving = true);
    try {
      final b = _bulletin();
      // Eski sürümler haberi düz gösterir: kapak olarak ortak kapak görseli.
      String? image;
      try {
        // Önizleme henüz çizilmediyse sayfanın sonuna inip çizilmesini bekle.
        for (var i = 0; i < 3 && _shotKey.currentContext == null; i++) {
          if (!_scroll.hasClients) break;
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        final png = await captureCard(_shotKey);
        image = await SupabaseImageUploadService().uploadImage(
          XFile.fromData(
            png,
            name: 'hafta-$week-bulten.png',
            mimeType: 'image/png',
          ),
          folder: MediaFolder.news,
        );
      } catch (_) {}
      final lines = <String>[
        if (b.hasEleven)
          "Haftanın 11'i: ${b.eleven.map((s) => s.person.name).join(', ')}",
        for (final a in b.awards)
          '${a.kind.full}: ${switch (a.kind) {
            AwardKind.match => '${a.home?.short} ${a.score} ${a.away?.short}',
            AwardKind.team => a.team.short,
            _ => '${a.person?.name} (${a.team.short})',
          }}',
      ];
      await _sb.rpc(
        'publish_week_awards',
        params: {
          'p_season_id': sid,
          'p_region_id': _regionId,
          'p_week': week,
          'p_content':
              '$week. Hafta Bülteni: Haftanın Enleri\n\n${lines.join('\n')}',
          'p_image_url': image,
          'p_data': {...b.toJson(), 'enabled': _enabled.toList()},
        },
      );
      if (!mounted) return;
      _snack('Bülten yayınlandı.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e is PostgrestException ? e.message : '$e';
      _snack('Yayınlanamadı: $msg');
    }
  }

  // ---- Görünüm ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final weeks = _weeks;
    final ready = !_loading && _pool.isNotEmpty;
    return AdminPageScaffold(
      title: 'Haftanın Enleri',
      bottomBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: AdminPrimaryButton(
          label: _exists ? 'Bülteni güncelle' : 'Bülteni yayınla',
          busy: _saving,
          onPressed: !ready || _saving || _uploading || _locked
              ? null
              : _publish,
        ),
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (widget.tournaments.length > 1)
            CustomPopupSelector<String>(
              label: 'Turnuva',
              selectedValue: _leagueId,
              items: [for (final l in widget.tournaments) l.id],
              labelBuilder: (id) => widget.tournaments
                  .firstWhere(
                    (l) => l.id == id,
                    orElse: () => widget.tournaments.first,
                  )
                  .name,
              onChanged: (v) {
                if (v != null && v != _leagueId) _pickLeague(v);
              },
            ),
          if (_regions.isNotEmpty)
            CustomPopupSelector<String>(
              label: 'Bölge',
              selectedValue: _regionId ?? '',
              items: [if (_fullAccess) '', ..._regions.keys],
              labelBuilder: (id) =>
                  (id ?? '').isEmpty ? 'Tüm turnuva' : (_regions[id] ?? ''),
              onChanged: (v) {
                setState(() => _regionId = (v ?? '').isEmpty ? null : v);
                final w = _weeks;
                if (w.isNotEmpty) {
                  _pickWeek(w.contains(_week) ? _week! : w.last);
                } else {
                  setState(() => _pool = const []);
                }
              },
            ),
          if (weeks.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: weeks.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final w = weeks[weeks.length - 1 - i];
                  final on = w == _week;
                  return ChoiceChip(
                    label: Text('$w. Hafta'),
                    selected: on,
                    showCheckmark: false,
                    onSelected: (_) => _pickWeek(w),
                    backgroundColor: _card,
                    selectedColor: kAdminAccent.withValues(alpha: 0.18),
                    side: BorderSide(
                      color: on
                          ? kAdminAccent
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                    labelStyle: TextStyle(
                      color: on ? const Color(0xFF34D399) : kAdminMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(color: kAdminAccent),
              ),
            )
          else if (_seasonId != null && weeks.isEmpty)
            const _Empty('Bu turnuvada henüz biten maç yok.')
          else if (_week != null && _pool.isEmpty)
            const _Empty('Bu hafta esamesi girilmiş maç yok.')
          else if (ready) ...[
            if (_exists)
              _Hint(
                _locked
                    ? 'Bu haftanın bülteni yayınlandı; yayınlanan bülten değiştirilmez.'
                    : 'Bu haftanın bülteni yayınlandı. Değiştirip yeniden yayınlarsan haber güncellenir.',
                color: kAdminAmber,
              ),
            const _Hint(
              'Adaylar maç puanından önerildi. Dokunup değiştirebilirsin.',
            ),
            const SizedBox(height: 12),
            _section('BÜLTENDE YER ALACAKLAR'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _toggle(
                  _kEleven,
                  "11'i",
                  Icons.groups_rounded,
                  const Color(0xFF34D399),
                ),
                for (final k in AwardKind.values)
                  _toggle(k.key, k.title, k.icon, k.color),
              ],
            ),
            if (_enabled.contains(_kEleven)) ...[
              const SizedBox(height: 18),
              _section("HAFTANIN 11'İ"),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: formationOptions(_outfield).length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final f = formationOptions(_outfield)[i];
                    final on = f == _formation;
                    return ChoiceChip(
                      label: Text(f),
                      selected: on,
                      showCheckmark: false,
                      onSelected: (_) => _setFormation(f),
                      backgroundColor: _card,
                      selectedColor: kAdminAccent.withValues(alpha: 0.18),
                      side: BorderSide(
                        color: on
                            ? kAdminAccent
                            : Colors.white.withValues(alpha: 0.08),
                      ),
                      labelStyle: TextStyle(
                        color: on ? const Color(0xFF34D399) : kAdminMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: WeekElevenCard(
                    league: _league?.name ?? '',
                    leagueLogo: _league?.logoUrl ?? '',
                    week: _week ?? 0,
                    formation: _formation,
                    slots: [for (final id in _eleven) _slot(id)],
                    showRatings: weekAwardsShowRatings(),
                    onTapSlot: _changeSlot,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Boş yere dokun: liste o mevkinin en yüksek puanlısından başlar, sonra diğer mevkiler gelir.',
                style: TextStyle(color: kAdminMuted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 18),
            _section('ENLER'),
            for (final k in AwardKind.values)
              if (_enabled.contains(k.key)) _awardRow(k),
            const SizedBox(height: 18),
            _section('ÖNİZLEME'),
            _preview(),
          ],
        ],
      ),
    );
  }

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: kAdminMuted,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    ),
  );

  Widget _toggle(String key, String label, IconData icon, Color color) {
    final on = _enabled.contains(key);
    return FilterChip(
      selected: on,
      showCheckmark: false,
      avatar: Icon(icon, size: 16, color: on ? color : kAdminMuted),
      label: Text(label),
      onSelected: (v) => setState(() {
        _enabled = {..._enabled};
        v ? _enabled.add(key) : _enabled.remove(key);
      }),
      backgroundColor: _card,
      selectedColor: color.withValues(alpha: 0.16),
      side: BorderSide(
        color: on ? color : Colors.white.withValues(alpha: 0.08),
      ),
      labelStyle: TextStyle(
        color: on ? Colors.white : kAdminMuted,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _awardRow(AwardKind k) {
    final key = _pick[k];
    final opts = _options(k);
    final o = opts.where((e) => e.key == key).firstOrNull;
    final photos = _photosFor(k);
    final photo = _photo[k] ?? '';
    final canPhoto = k != AwardKind.match && key != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: k.color,
                child: Icon(k.icon, size: 19, color: const Color(0xFF0C1424)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      k.full.toUpperCase(),
                      style: const TextStyle(
                        color: kAdminMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      o?.title ??
                          (k == AwardKind.fair ? 'Sen seç' : 'Seçilmedi'),
                      style: TextStyle(
                        color: o == null ? kAdminAmber : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (o != null)
                      Text(
                        [
                          o.sub,
                          if (o.trailing.isNotEmpty) '${o.trailing} puan',
                        ].join(' · '),
                        style: const TextStyle(
                          color: kAdminMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => _changeAward(k),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kAdminAccent,
                  side: const BorderSide(color: Color(0xFF2D6B55)),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(key == null ? 'Seç' : 'Değiştir'),
              ),
            ],
          ),
          if (k == AwardKind.fair && key == null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Centilmen puanla seçilmez. Kart görmeyen oyuncular listelenir.',
                style: TextStyle(color: kAdminMuted, fontSize: 12),
              ),
            ),
          if (canPhoto) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final p in {...photos, if (photo.isNotEmpty) photo})
                    _thumb(
                      on: photo == p,
                      onTap: () => setState(() => _photo[k] = p),
                      child: WebSafeImage(url: p, fit: BoxFit.cover),
                    ),
                  _thumb(
                    on: false,
                    onTap: _uploading ? null : () => _uploadPhoto(k),
                    child: _uploading
                        ? const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: kAdminMuted,
                          ),
                  ),
                  _thumb(
                    on: photo.isEmpty,
                    onTap: () => setState(() => _photo[k] = ''),
                    child: const Center(
                      child: Text(
                        'Fotosuz',
                        style: TextStyle(
                          color: kAdminMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _thumb({
    required bool on,
    required VoidCallback? onTap,
    required Widget child,
  }) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF111A2E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: on ? kAdminAccent : Colors.white.withValues(alpha: 0.08),
            width: on ? 2 : 1,
          ),
        ),
        child: child,
      ),
    ),
  );

  /// Kapak ve kartların yayınlanacak hâli; kapak eski sürümlerin görseli.
  Widget _preview() {
    final b = _bulletin();
    final ratings = weekAwardsShowRatings();
    final cards = <Widget>[
      if (b.hasEleven)
        WeekElevenCard(
          league: b.leagueName,
          leagueLogo: b.leagueLogo,
          week: b.week,
          formation: b.formation,
          slots: b.eleven,
          showRatings: ratings,
        ),
      for (final a in b.awards)
        WeekAwardCard(
          award: a,
          league: b.leagueName,
          leagueLogo: b.leagueLogo,
          week: b.week,
          showRatings: ratings,
        ),
    ];
    if (cards.isEmpty) return const _Empty('Bültende henüz kart yok.');
    // Önde haberin ortak kapağı; eski sürümler bunu görsel olarak görür.
    final cover = RepaintBoundary(
      key: _shotKey,
      child: AspectRatio(
        aspectRatio: 5 / 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: WeekAwardsCover(data: b),
        ),
      ),
    );
    return SizedBox(
      height: 300,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cards.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) => i == 0
            ? Center(child: SizedBox(width: 340, child: cover))
            : SizedBox(width: 240, child: cards[i - 1]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Center(
      child: Text(text, style: const TextStyle(color: Colors.white54)),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.color = const Color(0xFFFCD34D)});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      border: Border.all(color: color.withValues(alpha: 0.3)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 12)),
  );
}
