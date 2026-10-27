import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/custom_popup_selector.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/widgets/youtube_player_page.dart';
import '../../tournament/models/league.dart';

/// Haftanın Seçimi: kurucu başkan / bölge sorumlusu bir haftanın golünü,
/// oyuncusunu ya da takımını seçer; seçim Haberler'de kendi kartıyla
/// yayınlanır. Aynı hafta yeniden seçilirse haber güncellenir.
class WeeklyPickScreen extends StatefulWidget {
  const WeeklyPickScreen({super.key, required this.tournaments});

  /// Kullanıcının yönetebildiği turnuvalar.
  final List<League> tournaments;

  @override
  State<WeeklyPickScreen> createState() => _WeeklyPickScreenState();
}

enum _Kind { goal, player, team }

extension on _Kind {
  String get dbKind => switch (this) {
    _Kind.goal => 'goal_of_week',
    _Kind.player => 'player_of_week',
    _Kind.team => 'team_of_week',
  };
  String get tab => switch (this) {
    _Kind.goal => 'Gol',
    _Kind.player => 'Oyuncu',
    _Kind.team => 'Takım',
  };
  String get title => switch (this) {
    _Kind.goal => 'Haftanın Golü',
    _Kind.player => 'Haftanın Oyuncusu',
    _Kind.team => 'Haftanın Takımı',
  };
}

class _TeamLite {
  const _TeamLite(this.id, this.name, this.logo, this.color);
  final String id;
  final String name;
  final String logo;
  final String? color;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'logo': logo,
    'color': color,
  };
}

class _MatchLite {
  const _MatchLite({
    required this.id,
    required this.homeId,
    required this.awayId,
    required this.hs,
    required this.as,
  });
  final String id;
  final String homeId;
  final String awayId;
  final int hs;
  final int as;
}

class _ClipRef {
  const _ClipRef(this.videoId, this.start, this.end);
  final String videoId;
  final int start;
  final int end;
}

class _Goal {
  const _Goal({
    required this.eventId,
    required this.matchId,
    required this.teamId,
    required this.playerId,
    required this.assistId,
    required this.minute,
    required this.added,
    required this.pen,
    required this.og,
    required this.clip,
  });
  final String eventId;
  final String matchId;
  final String teamId;
  final String playerId;
  final String assistId;
  final int? minute;
  final int added;
  final bool pen;
  final bool og;
  final _ClipRef? clip;

  /// "12'", "45+2'"; dakika tutulmayan sezonda boş.
  String get label => minute == null || minute! <= 0
      ? ''
      : added > 0
      ? "$minute+$added'"
      : "$minute'";
}

class _Person {
  const _Person(this.name, this.photo);
  final String name;
  final String photo;
}

/// Listedeki bir aday (gol, oyuncu ya da takım).
class _Candidate {
  const _Candidate({
    required this.key,
    required this.title,
    required this.sub,
    required this.team,
    required this.match,
    this.goal,
    this.playerId,
    this.goals = 0,
    this.assists = 0,
    this.motm = false,
  });
  final String key;
  final String title;
  final String sub;
  final _TeamLite team;
  final _MatchLite match;
  final _Goal? goal;
  final String? playerId;
  final int goals;
  final int assists;
  final bool motm;
}

/// Haftanın verisi: maçlar, goller, oyuncular, fotoğraflar.
class _WeekData {
  const _WeekData({
    required this.matches,
    required this.teams,
    required this.goals,
    required this.motm,
    required this.people,
    required this.moments,
    required this.teamPhotos,
    required this.teamOfPlayer,
  });
  final List<_MatchLite> matches;
  final Map<String, _TeamLite> teams;
  final List<_Goal> goals;

  /// Maçın adamı: maç → oyuncu.
  final Map<String, String> motm;
  final Map<String, _Person> people;

  /// Maçın "Önemli An" fotoğrafları.
  final Map<String, List<String>> moments;

  /// Maçın "Takım Fotosu"ları (takım → url; takımsız olanlar '' altında).
  final Map<String, Map<String, List<String>>> teamPhotos;

  /// Oyuncunun sezondaki takımı (golü olmayan maçın adamı için).
  final Map<String, String> teamOfPlayer;
}

const _kAuto = '__auto__';
const _kUpload = '__upload__';
const _card = Color(0xFF1E293B);

class _WeeklyPickScreenState extends State<WeeklyPickScreen> {
  final _sb = Supabase.instance.client;
  final _note = TextEditingController();

  String? _leagueId;
  String? _seasonId;

  /// Bölgeler (id → ad); boşsa sezonda bölge yok.
  Map<String, String> _regions = const {};
  String? _regionId;

  /// Bitmiş maçların grubu → bölge, maç → (hafta, grup).
  List<({String id, int week, String regionId})> _finished = const [];
  int? _week;
  _Kind _kind = _Kind.goal;

  _WeekData? _data;
  bool _loading = false;
  String? _selected;
  String _cover = _kAuto;
  XFile? _upload;
  Uint8List? _uploadBytes;
  bool _saving = false;

  /// Bu hafta zaten yapılmış seçimler (tür → başlık).
  Map<String, String> _existing = const {};

  @override
  void initState() {
    super.initState();
    if (widget.tournaments.isNotEmpty) _pickLeague(widget.tournaments.first.id);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  bool get _fullAccess =>
      AppSession.of(context).value.canManageLeague(_leagueId);

  Future<void> _pickLeague(String leagueId) async {
    setState(() {
      _leagueId = leagueId;
      _seasonId = null;
      _regions = const {};
      _regionId = null;
      _finished = const [];
      _week = null;
      _data = null;
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
        // Bölge sorumlusu tüm turnuva adına seçemez.
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

  /// Bitmiş maçı olan haftalar (seçili bölgede).
  List<int> get _weeks {
    final out = {
      for (final m in _finished)
        if (_regionId == null || m.regionId == _regionId) m.week,
    }.toList()..sort();
    return out;
  }

  Future<void> _pickWeek(int week) async {
    final sid = _seasonId;
    if (sid == null) return;
    setState(() {
      _week = week;
      _data = null;
      _selected = null;
      _loading = true;
    });
    final ids = [
      for (final m in _finished)
        if (m.week == week && (_regionId == null || m.regionId == _regionId))
          m.id,
    ];
    try {
      final (matches, events, clips, media, picks) = await (
        _sb
            .from('matches')
            .select('id, home_team_id, away_team_id, home_score, away_score')
            .inFilter('id', ids),
        _sb
            .from('match_events')
            .select(
              'id, match_id, team_id, player_id, assist_player_id, '
              'event_type, minute, added_minute, is_penalty, is_own_goal',
            )
            .inFilter('match_id', ids)
            .inFilter('event_type', ['goal', 'man_of_the_match']),
        _sb
            .from('match_highlights')
            .select('match_event_id, video_id, start_sec, end_sec')
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
            .select('auto_kind, region_id, auto_data')
            .eq('season_id', sid)
            .eq('week', week)
            .inFilter('auto_kind', [for (final k in _Kind.values) k.dbKind]),
      ).wait;
      final teamIds = {
        for (final m in matches) ...[
          m['home_team_id'].toString(),
          m['away_team_id'].toString(),
        ],
      };
      final personIds = {
        for (final e in events) ...[
          (e['player_id'] ?? '').toString(),
          (e['assist_player_id'] ?? '').toString(),
        ],
      }..remove('');
      final motmIds = [
        for (final e in events)
          if (e['event_type'] == 'man_of_the_match' && e['player_id'] != null)
            e['player_id'].toString(),
      ];
      final (teams, people, roster) = await (
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
        motmIds.isEmpty
            ? Future.value(const <Map<String, dynamic>>[])
            : _sb
                  .from('season_team_players')
                  .select('player_id, team_id')
                  .eq('season_id', sid)
                  .inFilter('player_id', motmIds),
      ).wait;
      if (!mounted || _week != week) return;

      final clipOf = <String, _ClipRef>{
        for (final c in clips)
          c['match_event_id'].toString(): _ClipRef(
            (c['video_id'] ?? '').toString(),
            (c['start_sec'] as num?)?.toInt() ?? 0,
            (c['end_sec'] as num?)?.toInt() ?? 0,
          ),
      };
      final goals = <_Goal>[];
      final motm = <String, String>{};
      for (final e in events) {
        final matchId = e['match_id'].toString();
        final playerId = (e['player_id'] ?? '').toString();
        if (e['event_type'] == 'man_of_the_match') {
          if (playerId.isNotEmpty) motm[matchId] = playerId;
          continue;
        }
        goals.add(
          _Goal(
            eventId: e['id'].toString(),
            matchId: matchId,
            teamId: (e['team_id'] ?? '').toString(),
            playerId: playerId,
            assistId: (e['assist_player_id'] ?? '').toString(),
            minute: (e['minute'] as num?)?.toInt(),
            added: (e['added_minute'] as num?)?.toInt() ?? 0,
            pen: e['is_penalty'] == true,
            og: e['is_own_goal'] == true,
            clip: clipOf[e['id'].toString()],
          ),
        );
      }
      goals.sort((a, b) {
        final c = a.matchId.compareTo(b.matchId);
        if (c != 0) return c;
        return ((a.minute ?? 0) * 100 + a.added).compareTo(
          (b.minute ?? 0) * 100 + b.added,
        );
      });
      final moments = <String, List<String>>{};
      final teamPhotos = <String, Map<String, List<String>>>{};
      for (final m in media) {
        final url = (m['url'] ?? '').toString().trim();
        if (url.isEmpty) continue;
        final matchId = m['match_id'].toString();
        if (m['media_type'] == 'Önemli An') {
          (moments[matchId] ??= []).add(url);
        } else {
          final t = (m['team_id'] ?? '').toString();
          ((teamPhotos[matchId] ??= {})[t] ??= []).add(url);
        }
      }
      final existing = <String, String>{};
      for (final p in picks) {
        if ((p['region_id'] ?? '').toString() != (_regionId ?? '')) continue;
        final d = p['auto_data'] is Map ? p['auto_data'] as Map : const {};
        final title = p['auto_kind'] == 'team_of_week'
            ? ((d['team'] as Map?)?['name'] ?? '').toString()
            : ((d['player'] as Map?)?['name'] ?? '').toString();
        existing[p['auto_kind'].toString()] = title;
      }
      setState(() {
        _existing = existing;
        _data = _WeekData(
          matches: [
            for (final m in matches)
              _MatchLite(
                id: m['id'].toString(),
                homeId: m['home_team_id'].toString(),
                awayId: m['away_team_id'].toString(),
                hs: (m['home_score'] as num?)?.toInt() ?? 0,
                as: (m['away_score'] as num?)?.toInt() ?? 0,
              ),
          ],
          teams: {
            for (final t in teams)
              t['id'].toString(): _TeamLite(
                t['id'].toString(),
                shortTeamName((t['name'] ?? '').toString()),
                (t['logo_url'] ?? '').toString().trim(),
                t['first_color']?.toString(),
              ),
          },
          goals: goals,
          motm: motm,
          people: {
            for (final p in people)
              p['id'].toString(): _Person(
                [
                  (p['name'] ?? '').toString().trim(),
                  (p['surname'] ?? '').toString().trim(),
                ].where((e) => e.isNotEmpty).join(' '),
                (p['photo_url'] ?? '').toString().trim(),
              ),
          },
          moments: moments,
          teamPhotos: teamPhotos,
          teamOfPlayer: {
            for (final r in roster)
              if (teamIds.contains(r['team_id'].toString()))
                r['player_id'].toString(): r['team_id'].toString(),
          },
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Hafta okunamadı: $e');
    }
  }

  // ---- Adaylar ----------------------------------------------------------

  _TeamLite _team(String id) =>
      _data?.teams[id] ?? _TeamLite(id, 'Takım', '', null);

  String _name(String id) {
    final n = _data?.people[id]?.name ?? '';
    return n.isEmpty ? 'Oyuncu' : n;
  }

  String _score(_MatchLite m) =>
      '${_team(m.homeId).name} ${m.hs}-${m.as} ${_team(m.awayId).name}';

  List<_Candidate> get _candidates {
    final d = _data;
    if (d == null) return const [];
    final matchOf = {for (final m in d.matches) m.id: m};
    switch (_kind) {
      case _Kind.goal:
        return [
          for (final g in d.goals)
            if (!g.og && g.playerId.isNotEmpty && matchOf[g.matchId] != null)
              _Candidate(
                key: g.eventId,
                title: [
                  _name(g.playerId),
                  g.label,
                ].where((e) => e.isNotEmpty).join(' · '),
                sub: [
                  _score(matchOf[g.matchId]!),
                  if (g.pen) 'penaltı',
                ].join(' · '),
                team: _team(g.teamId),
                match: matchOf[g.matchId]!,
                goal: g,
                playerId: g.playerId,
              ),
        ];
      case _Kind.player:
        final stats =
            <String, ({int g, int a, bool m, String team, String match})>{};
        void bump(
          String pid,
          String team,
          String match, {
          int g = 0,
          int a = 0,
          bool m = false,
        }) {
          if (pid.isEmpty) return;
          final s = stats[pid];
          stats[pid] = (
            g: (s?.g ?? 0) + g,
            a: (s?.a ?? 0) + a,
            m: (s?.m ?? false) || m,
            team: s?.team ?? team,
            match: s?.match ?? match,
          );
        }
        for (final g in d.goals) {
          if (!g.og) bump(g.playerId, g.teamId, g.matchId, g: 1);
          if (g.assistId.isNotEmpty) {
            bump(g.assistId, g.teamId, g.matchId, a: 1);
          }
        }
        // Golü olmayan maçın adamının takımı kadrodan.
        for (final e in d.motm.entries) {
          final known = stats[e.value];
          bump(
            e.value,
            known?.team ?? d.teamOfPlayer[e.value] ?? '',
            known?.match ?? e.key,
            m: true,
          );
        }
        final list =
            stats.entries.where((e) => matchOf[e.value.match] != null).toList()
              ..sort((a, b) {
                if (a.value.m != b.value.m) return a.value.m ? -1 : 1;
                final c = b.value.g.compareTo(a.value.g);
                if (c != 0) return c;
                return b.value.a.compareTo(a.value.a);
              });
        return [
          for (final e in list)
            _Candidate(
              key: e.key,
              title: _name(e.key),
              sub: [
                if (e.value.g > 0) '${e.value.g} gol',
                if (e.value.a > 0) '${e.value.a} asist',
                if (e.value.m) 'Maçın Adamı',
              ].join(' · '),
              team: _team(e.value.team),
              match: matchOf[e.value.match]!,
              playerId: e.key,
              goals: e.value.g,
              assists: e.value.a,
              motm: e.value.m,
            ),
        ];
      case _Kind.team:
        final rows = <(_Candidate, int)>[];
        for (final m in d.matches) {
          for (final home in [true, false]) {
            final id = home ? m.homeId : m.awayId;
            final opp = _team(home ? m.awayId : m.homeId).name;
            final f = home ? m.hs : m.as;
            final a = home ? m.as : m.hs;
            final result = f > a
                ? 'galibiyet'
                : f == a
                ? 'beraberlik'
                : 'mağlubiyet';
            final photos = d.teamPhotos[m.id];
            final hasPhoto =
                (photos?[id]?.isNotEmpty ?? false) ||
                (photos?['']?.isNotEmpty ?? false);
            rows.add((
              _Candidate(
                key: '${m.id}|$id',
                title: _team(id).name,
                sub: [
                  '$f-$a $opp $result',
                  hasPhoto ? 'takım fotoğrafı var' : 'fotoğraf yok',
                ].join(' · '),
                team: _team(id),
                match: m,
              ),
              (f - a) * 100 + f,
            ));
          }
        }
        rows.sort((a, b) => b.$2.compareTo(a.$2));
        return [for (final r in rows) r.$1];
    }
  }

  _Candidate? get _current {
    for (final c in _candidates) {
      if (c.key == _selected) return c;
    }
    return null;
  }

  /// Seçilen adaya uygun hazır fotoğraflar.
  List<String> _photosFor(_Candidate c) {
    final d = _data!;
    return switch (_kind) {
      _Kind.goal => d.moments[c.match.id] ?? const [],
      _Kind.player => [
        if ((d.people[c.playerId]?.photo ?? '').isNotEmpty)
          d.people[c.playerId]!.photo,
        ...?d.moments[c.match.id],
      ],
      _Kind.team => [
        ...?d.teamPhotos[c.match.id]?[c.team.id],
        ...?d.teamPhotos[c.match.id]?[''],
      ],
    };
  }

  void _select(_Candidate c) {
    final photos = _photosFor(c);
    setState(() {
      _selected = c.key;
      _cover = photos.isNotEmpty ? photos.first : _kAuto;
    });
  }

  Future<void> _pickUpload() async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 82,
    );
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    setState(() {
      _upload = f;
      _uploadBytes = bytes;
      _cover = _kUpload;
    });
  }

  // ---- Yayın ------------------------------------------------------------

  Future<void> _publish() async {
    final c = _current;
    final d = _data;
    final sid = _seasonId;
    final week = _week;
    if (c == null || d == null || sid == null || week == null) {
      _snack('Önce listeden bir seçim yap.');
      return;
    }
    if (_cover == _kUpload && _upload == null) {
      _snack('Yüklenecek fotoğrafı seç.');
      return;
    }
    setState(() => _saving = true);
    try {
      String? image;
      if (_cover == _kUpload) {
        image = await SupabaseImageUploadService().uploadImage(
          _upload!,
          folder: MediaFolder.news,
        );
        if (image == null) throw Exception('Fotoğraf yüklenemedi.');
      } else if (_cover != _kAuto) {
        image = _cover;
      }
      final m = c.match;
      final note = _note.text.trim();
      final score = _score(m);
      final person = c.playerId == null ? null : d.people[c.playerId];
      final data = <String, dynamic>{
        'week': week,
        'match_id': m.id,
        'home': _team(m.homeId).toJson(),
        'away': _team(m.awayId).toJson(),
        'hs': m.hs,
        'as': m.as,
        'team': c.team.toJson(),
        if (c.playerId != null)
          'player': {
            'id': c.playerId,
            'name': _name(c.playerId!),
            'photo': person?.photo ?? '',
          },
        if (note.isNotEmpty) 'note': note,
      };
      final String content;
      switch (_kind) {
        case _Kind.goal:
          final g = c.goal!;
          data['event_id'] = g.eventId;
          data['minute_label'] = g.label;
          if (g.clip != null) {
            data['clip'] = {
              'video_id': g.clip!.videoId,
              'start': g.clip!.start,
              'end': g.clip!.end,
            };
          }
          content = [
            '$week. haftanın golü: ${_name(g.playerId)} (${c.team.name})'
                '${g.label.isEmpty ? '' : ' ${g.label}'}',
            score,
          ].join(' · ');
        case _Kind.player:
          data['goals'] = c.goals;
          data['assists'] = c.assists;
          data['motm'] = c.motm;
          data['clips'] = [
            for (final g in d.goals)
              if (g.playerId == c.playerId && !g.og && g.clip != null)
                {
                  'label': g.label,
                  'video_id': g.clip!.videoId,
                  'start': g.clip!.start,
                  'end': g.clip!.end,
                },
          ];
          content = [
            '$week. haftanın oyuncusu: ${_name(c.playerId!)} '
                '(${c.team.name})',
            if (c.sub.isNotEmpty) c.sub,
          ].join(' · ');
        case _Kind.team:
          final byPlayer = <String, List<String>>{};
          for (final g in d.goals) {
            if (g.matchId == m.id && g.teamId == c.team.id && !g.og) {
              (byPlayer[g.playerId] ??= []).add(g.label);
            }
          }
          data['scorers'] = [
            for (final e in byPlayer.entries)
              {
                'name': _name(e.key),
                'n': e.value.length,
                'labels': e.value.where((l) => l.isNotEmpty).toList(),
              },
          ];
          content = '$week. haftanın takımı: ${c.team.name} · $score';
      }
      await _sb.rpc(
        'publish_weekly_pick',
        params: {
          'p_season_id': sid,
          'p_region_id': _regionId,
          'p_week': week,
          'p_kind': _kind.dbKind,
          'p_match_id': m.id,
          'p_content': note.isEmpty ? content : '$content\n\n$note',
          'p_image_url': image,
          'p_data': data,
        },
      );
      if (!mounted) return;
      _snack('${_kind.title} yayınlandı.');
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
    final candidates = _candidates;
    final current = _current;
    final weeks = _weeks;
    return AdminPageScaffold(
      title: 'Haftanın Seçimi',
      bottomBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: AdminPrimaryButton(
          label: '${_kind.title} olarak yayınla',
          busy: _saving,
          onPressed: current == null || _saving ? null : _publish,
        ),
      ),
      body: ListView(
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
                  setState(() => _data = null);
                }
              },
            ),
          const SizedBox(height: 8),
          _KindTabs(
            value: _kind,
            onChanged: (k) => setState(() {
              _kind = k;
              _selected = null;
              _cover = _kAuto;
            }),
          ),
          const SizedBox(height: 12),
          if (weeks.isNotEmpty)
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
          if (_existing[_kind.dbKind] case final prev?)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kAdminAmber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Bu haftanın seçimi yapıldı${prev.isEmpty ? '' : ': $prev'}. '
                'Yeniden seçersen haber güncellenir.',
                style: const TextStyle(color: kAdminAmber, fontSize: 12.5),
              ),
            ),
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
          else if (_data != null && candidates.isEmpty)
            _Empty(switch (_kind) {
              _Kind.goal => 'Bu hafta gol kaydı yok.',
              _Kind.player => 'Bu hafta gol, asist ya da maçın adamı yok.',
              _Kind.team => 'Bu hafta biten maç yok.',
            })
          else ...[
            if (_data != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  switch (_kind) {
                    _Kind.goal =>
                      '$_week. haftanın golleri · ▶ ile kesiti izle',
                    _Kind.player =>
                      '$_week. hafta · maçın adamları, gol ve asist yapanlar',
                    _Kind.team => '$_week. haftanın takımları',
                  },
                  style: const TextStyle(
                    color: kAdminMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            for (final c in candidates)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CandidateRow(
                  candidate: c,
                  selected: c.key == _selected,
                  showClip: _kind == _Kind.goal,
                  onTap: () => _select(c),
                  onPlay: c.goal?.clip == null
                      ? null
                      : () => openYoutubeClip(
                          context,
                          videoId: c.goal!.clip!.videoId,
                          startSec: c.goal!.clip!.start,
                          endSec: c.goal!.clip!.end,
                          title: c.title,
                        ),
                ),
              ),
          ],
          if (current != null) ...[
            const SizedBox(height: 8),
            _CoverPicker(
              photos: _photosFor(current),
              photoLabel: switch (_kind) {
                _Kind.goal => 'Önemli An',
                _Kind.player => 'Fotoğraf',
                _Kind.team => 'Takım Fotosu',
              },
              value: _cover,
              uploadBytes: _uploadBytes,
              onChanged: (v) => setState(() => _cover = v),
              onUpload: _pickUpload,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 3,
              maxLength: 280,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Not (isteğe bağlı)',
                hintText: 'ör. Ceza sahası dışından, uzak köşeye.',
                labelStyle: const TextStyle(color: kAdminMuted),
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: _card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ],
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

class _KindTabs extends StatelessWidget {
  const _KindTabs({required this.value, required this.onChanged});

  final _Kind value;
  final ValueChanged<_Kind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF111A2E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final k in _Kind.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(k),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: k == value ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    k.tab,
                    style: TextStyle(
                      color: k == value ? const Color(0xFF0B1220) : kAdminMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.selected,
    required this.showClip,
    required this.onTap,
    required this.onPlay,
  });

  final _Candidate candidate;
  final bool selected;
  final bool showClip;
  final VoidCallback onTap;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    return Material(
      color: selected ? kAdminAccent.withValues(alpha: 0.08) : _card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? kAdminAccent
                  : Colors.white.withValues(alpha: 0.06),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? kAdminAccent : Colors.white38,
                size: 22,
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 34,
                height: 34,
                child: c.team.logo.isEmpty
                    ? const Icon(Icons.shield_outlined, color: Colors.white38)
                    : WebSafeImage(url: c.team.logo, fit: BoxFit.contain),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kAdminMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (showClip)
                onPlay == null
                    ? const SizedBox(
                        width: 48,
                        child: Text(
                          'kesit yok',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Kesiti izle',
                        onPressed: onPlay,
                        style: IconButton.styleFrom(
                          backgroundColor: kAdminAccent.withValues(alpha: 0.15),
                        ),
                        icon: const Icon(
                          Icons.play_arrow_rounded,
                          color: Color(0xFF34D399),
                        ),
                      ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kapak: hazır fotoğraflar, yükleme ya da otomatik kart.
class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.photos,
    required this.photoLabel,
    required this.value,
    required this.uploadBytes,
    required this.onChanged,
    required this.onUpload,
  });

  final List<String> photos;
  final String photoLabel;
  final String value;
  final Uint8List? uploadBytes;
  final ValueChanged<String> onChanged;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    Widget tile({
      required bool on,
      required VoidCallback onTap,
      required Widget child,
      String? label,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 92,
          height: 92,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: on ? kAdminAccent : Colors.white.withValues(alpha: 0.06),
              width: on ? 2 : 1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              if (label != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    color: Colors.black54,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    Widget iconTile(IconData icon, String text) => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: kAdminMuted, size: 22),
        const SizedBox(height: 6),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFE2E8F0),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'KAPAK FOTOĞRAFI',
          style: TextStyle(
            color: kAdminMuted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in photos)
              tile(
                on: value == p,
                onTap: () => onChanged(p),
                label: photoLabel,
                child: WebSafeImage(url: p, fit: BoxFit.cover),
              ),
            tile(
              on: value == _kUpload,
              onTap: onUpload,
              child: uploadBytes == null
                  ? iconTile(Icons.upload_rounded, 'Fotoğraf yükle')
                  : Image.memory(uploadBytes!, fit: BoxFit.cover),
              label: uploadBytes == null ? null : 'Yüklenen',
            ),
            tile(
              on: value == _kAuto,
              onTap: () => onChanged(_kAuto),
              child: iconTile(Icons.style_rounded, 'Otomatik kart'),
            ),
          ],
        ),
      ],
    );
  }
}
