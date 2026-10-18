import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/utils/table_feed.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/team_crest.dart';
import '../../match/models/match.dart';
import '../../match/screens/match_details_screen.dart';
import '../../match/widgets/penalty_badge.dart';
import '../../team/models/team.dart';
import '../../team/utils/standings.dart';
import '../models/league_format.dart';

/// Oluşturulmuş kupa eşleşmeleri (`cup_brackets`).
class CupBracket {
  const CupBracket({
    required this.id,
    required this.cupName,
    required this.groupId,
    required this.firstRound,
  });

  final String id;
  final String cupName;
  final String? groupId;

  /// İlk tur, ağaç sırasıyla: (ev sahibi, deplasman, sıraları); null bay.
  final List<({String? h, String? a, int? hr, int? ar})> firstRound;

  factory CupBracket.fromMap(Map<String, dynamic> m) {
    int? asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    String? asId(dynamic v) {
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    return CupBracket(
      id: m['id'].toString(),
      cupName: (m['cup_name'] ?? '').toString(),
      groupId: asId(m['group_id']),
      firstRound: [
        for (final e in (m['first_round'] as List? ?? const []))
          if (e is Map)
            (
              h: asId(e['h']),
              a: asId(e['a']),
              hr: asInt(e['hr']),
              ar: asInt(e['ar']),
            ),
      ],
    );
  }
}

/// Sezonun (grubun) oluşturulmuş eşleşmeleri.
Future<List<CupBracket>> loadCupBrackets(String seasonId) async {
  try {
    final rows = await Supabase.instance.client
        .from('cup_brackets')
        .select('id, cup_name, group_id, first_round')
        .eq('season_id', seasonId);
    return [for (final r in rows) CupBracket.fromMap(r)];
  } catch (_) {
    // Tablo yoksa (migration öncesi) eşleşme yok sayılır.
    return const [];
  }
}

/// Ağaçtaki bir taraf: belli takım ya da yer tutucu ("1. sıra",
/// "YF 1 galibi"); [bye] rakipsiz tur atlama.
class _Side {
  const _Side({this.teamId, this.rank, this.hint, this.bye = false});

  final String? teamId;
  final int? rank;
  final String? hint;
  final bool bye;
}

class _Tie {
  _Tie({
    required this.label,
    required this.short,
    required this.home,
    required this.away,
    this.match,
    this.isFinal = false,
  });

  final String label;
  final String short;
  final _Side home;
  final _Side away;
  final Map<String, dynamic>? match;
  final bool isFinal;

  /// Galip ve mağlup (bitmediyse null; bayda galip rakipsiz taraf).
  String? winner;
  String? loser;
}

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

/// Bitmiş maçın galibi ([loser]: mağlubu); bitmediyse / berabereyse null.
String? _sideOf(Map<String, dynamic> m, {bool loser = false}) {
  if (m['status'] != 'finished') return null;
  final hs = _int(m['home_score']), as = _int(m['away_score']);
  final hp = _int(m['home_pens']), ap = _int(m['away_pens']);
  final homeWins = hs != as ? hs > as : (hp != ap ? hp > ap : null);
  if (homeWins == null) return null;
  final home = (m['home_team_id'] ?? '').toString();
  final away = (m['away_team_id'] ?? '').toString();
  return homeWins != loser ? home : away;
}

String _shortRound(String name) => switch (name) {
  'Yarı Final' => 'YF',
  'Çeyrek Final' => 'ÇF',
  'Final' => 'Final',
  _ => name,
};

/// Turnuva Sayfası "Play-Off" sekmesi: lig formatındaki her kupanın ağacı.
/// Eşleşmeler oluşturulmadıysa sıralar puan tablosundan canlı yer tutucu;
/// oluşturulduysa maçlar (sonraki turlar sunucuda kendiliğinden açılır).
class PlayoffView extends StatefulWidget {
  const PlayoffView({
    super.key,
    required this.leagueId,
    required this.seasonId,
    required this.groupId,
    required this.groupName,
    required this.format,
    required this.canManage,
    this.onBracketsChanged,
  });

  final String leagueId;
  final String seasonId;
  final String groupId;
  final String groupName;
  final LeagueFormat format;

  /// Admin / turnuva sahibi: eşleşmeleri oluşturur, geri alır.
  final bool canManage;

  /// Eşleşmeler oluşturulunca / geri alınınca (sekmenin görünürlüğü için).
  final VoidCallback? onBracketsChanged;

  @override
  State<PlayoffView> createState() => _PlayoffViewState();
}

class _PlayoffViewState extends State<PlayoffView> {
  static const _card = Color(0xFF1E293B);
  static const _line = Color(0xFF334155);
  static const _muted = Color(0xFF94A3B8);
  static const _gold = Color(0xFFFBBF24);
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFF87171);

  late final Stream<List<Map<String, dynamic>>> _matches = watchTableRows(
    Supabase.instance.client,
    table: 'matches',
    column: 'season_id',
    value: widget.seasonId,
    orderBy: 'match_date',
  );
  late final Stream<List<Team>> _teams = ServiceLocator.teamService
      .watchAllTeams();

  List<CupBracket>? _brackets;
  int _cup = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await loadCupBrackets(widget.seasonId);
    if (mounted) setState(() => _brackets = list);
  }

  @override
  Widget build(BuildContext context) {
    final cups = widget.format.cups;
    if (cups.isEmpty) {
      return const Center(
        child: Text(
          'Bu sezonda play-off kupası yok.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _matches,
      builder: (context, mSnap) {
        return StreamBuilder<List<Team>>(
          stream: _teams,
          builder: (context, tSnap) {
            if (!mSnap.hasData || !tSnap.hasData || _brackets == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = mSnap.data!
                .where(
                  (m) =>
                      (m['league_id'] ?? '').toString() == widget.leagueId &&
                      (m['group_id'] ?? '').toString() == widget.groupId,
                )
                .toList();
            // Sunucuda oluşan eşleşmeyi henüz bilmiyorsak yeniden oku.
            final known = {for (final b in _brackets!) b.id};
            if (all.any(
              (m) =>
                  m['cup_bracket_id'] != null &&
                  !known.contains(m['cup_bracket_id'].toString()),
            )) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
            }
            return _content(all, tSnap.data!);
          },
        );
      },
    );
  }

  Widget _content(List<Map<String, dynamic>> matches, List<Team> teams) {
    final cups = widget.format.cups;
    final cupIndex = _cup.clamp(0, cups.length - 1);
    final cup = cups[cupIndex];
    final color = LeagueFormat.colors[cupIndex % LeagueFormat.colors.length];
    final rows = computeGroupStandings(
      leagueId: widget.leagueId,
      groupId: widget.groupId,
      groupName: widget.groupName,
      seasonMatches: matches,
      allTeams: teams,
    );
    final byId = {for (final t in teams) t.id: t};
    final remaining = matches
        .where((m) => m['tiebreak'] == null && m['status'] != 'finished')
        .length;
    final bracket = _brackets!
        .where((b) => b.cupName == cup.name && b.groupId == widget.groupId)
        .firstOrNull;
    final errors = widget.format.errorsOf(cupIndex, rows.length);

    final children = <Widget>[if (cups.length > 1) _cupChips(cups)];
    if (errors.isNotEmpty && bracket == null) {
      children.add(_note('Kupa ayarı bu grupla uyuşmuyor: ${errors.first}'));
    } else if (bracket == null &&
        !widget.format.showIfNow &&
        !widget.canManage) {
      children.add(_note('Eşleşmeler lig bitince açıklanacak.'));
    } else {
      final rounds = _buildRounds(cup, bracket, rows, matches);
      final third = _thirdPlace(cup, bracket, rounds, matches);
      final finalTie = rounds.last.first;
      if (finalTie.winner != null) {
        children.add(_champion(byId[finalTie.winner], cup.name));
      }
      children.add(_status(bracket, remaining, finalTie.winner != null, color));
      children.add(_tree(rounds, third, byId, rows, bracket == null));
    }
    if (widget.canManage && errors.isEmpty) {
      children.add(
        _adminCard(cup, cupIndex, bracket, rows, matches, remaining),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
      children: children,
    );
  }

  // ---------------------------------------------------------------------------
  // Ağaç modeli
  // ---------------------------------------------------------------------------

  List<List<_Tie>> _buildRounds(
    FormatCup cup,
    CupBracket? bracket,
    List<StandingEntry> rows,
    List<Map<String, dynamic>> matches,
  ) {
    Map<String, dynamic>? matchAt(int stage, int slot) {
      if (bracket == null) return null;
      return matches
          .where(
            (m) =>
                (m['cup_bracket_id'] ?? '').toString() == bracket.id &&
                _int(m['cup_stage']) == stage &&
                _int(m['cup_slot']) == slot,
          )
          .firstOrNull;
    }

    _Side rankSide(int? rank) {
      if (rank == null) return const _Side(bye: true);
      final team = rank <= rows.length ? rows[rank - 1].teamId : null;
      return _Side(teamId: team, rank: rank, hint: '$rank. sıra');
    }

    final first = bracket != null
        ? [
            for (final p in bracket.firstRound)
              (
                p.h == null
                    ? const _Side(bye: true)
                    : _Side(teamId: p.h, rank: p.hr),
                p.a == null
                    ? const _Side(bye: true)
                    : _Side(teamId: p.a, rank: p.ar),
              ),
          ]
        : [for (final (a, b) in cup.firstRound()) (rankSide(a), rankSide(b))];

    final rounds = <List<_Tie>>[];
    var count = first.length;
    var stage = 1;
    while (count >= 1) {
      final name = FormatCup.roundName(count * 2);
      final prev = rounds.lastOrNull;
      final ties = <_Tie>[];
      for (var s = 0; s < count; s++) {
        final _Side home, away;
        if (prev == null) {
          (home, away) = first[s];
        } else {
          _Side from(_Tie t) => t.winner != null
              ? _Side(teamId: t.winner)
              : _Side(hint: '${t.short} galibi');
          home = from(prev[2 * s]);
          away = from(prev[2 * s + 1]);
        }
        final label = count > 1 ? '$name ${s + 1}' : name;
        final tie = _Tie(
          label: label,
          short: count > 1 ? '${_shortRound(name)} ${s + 1}' : name,
          home: home,
          away: away,
          match: matchAt(stage, s),
          isFinal: count == 1,
        );
        // Placeholder ağaçta (eşleşme yok) kimse tur atlamaz; bayda rakipsiz
        // taraf yalnız eşleşmeler oluşturulduysa sonraki tura yazılır.
        if (bracket != null) {
          if (home.bye || away.bye) {
            tie.winner = home.bye ? away.teamId : home.teamId;
          } else if (tie.match != null) {
            tie.winner = _sideOf(tie.match!);
            tie.loser = _sideOf(tie.match!, loser: true);
          }
        }
        ties.add(tie);
      }
      rounds.add(ties);
      if (count == 1) break;
      count ~/= 2;
      stage++;
    }
    return rounds;
  }

  _Tie? _thirdPlace(
    FormatCup cup,
    CupBracket? bracket,
    List<List<_Tie>> rounds,
    List<Map<String, dynamic>> matches,
  ) {
    if (!cup.third || rounds.length < 2) return null;
    final semis = rounds[rounds.length - 2];
    _Side from(_Tie t) => t.loser != null
        ? _Side(teamId: t.loser)
        : _Side(hint: '${t.short} mağlubu');
    // 3.lük maçı final turunda slot 1.
    final match = bracket == null
        ? null
        : matches
              .where(
                (m) =>
                    (m['cup_bracket_id'] ?? '').toString() == bracket.id &&
                    _int(m['cup_stage']) == rounds.length &&
                    _int(m['cup_slot']) == 1,
              )
              .firstOrNull;
    final tie = _Tie(
      label: '3.lük Maçı',
      short: '3.lük',
      home: from(semis[0]),
      away: from(semis[1]),
      match: match,
    );
    if (match != null) tie.winner = _sideOf(match);
    return tie;
  }

  // ---------------------------------------------------------------------------
  // Görünüm
  // ---------------------------------------------------------------------------

  Widget _cupChips(List<FormatCup> cups) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          for (var i = 0; i < cups.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: _cupChip(cups[i], i)),
          ],
        ],
      ),
    );
  }

  Widget _cupChip(FormatCup c, int i) {
    final on = i == _cup;
    final color = LeagueFormat.colors[i % LeagueFormat.colors.length];
    return GestureDetector(
      onTap: () => setState(() => _cup = i),
      child: Container(
        height: 36,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: on ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? color : _line, width: 1.5),
        ),
        child: Text(
          '${c.name} · ${c.from}–${c.to}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: on ? const Color(0xFF04120C) : _muted,
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white60, fontSize: 13.5),
    ),
  );

  Widget _status(CupBracket? bracket, int remaining, bool done, Color color) {
    final String text;
    final Color dot;
    if (done) {
      text = 'Kupa tamamlandı';
      dot = _gold;
    } else if (bracket != null) {
      text = 'Eşleşmeler belli · sonraki tur maçları kendiliğinden oluşur';
      dot = color;
    } else if (remaining > 0) {
      text =
          'Lig sürüyor · $remaining maç kaldı · eşleşmeler puan '
          'tablosuna göre değişir';
      dot = _muted;
    } else {
      text = 'Lig bitti · eşleşmeler henüz oluşturulmadı';
      dot = _muted;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 4, right: 7),
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _champion(Team? team, String cupName) {
    if (team == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_gold.withValues(alpha: 0.18), Colors.transparent],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_rounded, color: _gold, size: 28),
          const SizedBox(width: 10),
          TeamCrest(name: team.name, logoUrl: team.logoUrl, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(
                  '$cupName şampiyonu',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _boxH = 82.0;
  static const _slotH = 96.0;
  static const _gapX = 24.0;
  static const _headH = 22.0;

  Widget _tree(
    List<List<_Tie>> rounds,
    _Tie? third,
    Map<String, Team> byId,
    List<StandingEntry> rows,
    bool placeholder,
  ) {
    final n1 = rounds.first.length;
    final cols = rounds.length;
    return LayoutBuilder(
      builder: (context, c) {
        final boxW = ((c.maxWidth - (cols - 1) * _gapX) / cols).clamp(
          150.0,
          210.0,
        );
        final width = cols * boxW + (cols - 1) * _gapX;
        final treeH = n1 * _slotH;
        final thirdH = third == null ? 0.0 : _headH + _boxH + 16;
        final height = _headH + treeH + thirdH;
        double x(int r) => r * (boxW + _gapX);
        double cy(int r, int k) => _headH + (k + 0.5) * _slotH * math.pow(2, r);

        final stack = <Widget>[
          Positioned.fill(
            child: CustomPaint(
              painter: _LinksPainter(
                rounds: [for (final r in rounds) r.length],
                x: x,
                cy: cy,
                boxW: boxW,
                color: rounds.last.first.winner != null
                    ? _gold.withValues(alpha: 0.7)
                    : const Color(0xFF475569),
              ),
            ),
          ),
          for (var r = 0; r < cols; r++)
            Positioned(
              left: x(r),
              top: 0,
              width: boxW,
              height: _headH,
              child: Text(
                FormatCup.roundName(rounds[r].length * 2).toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          for (var r = 0; r < cols; r++)
            for (var k = 0; k < rounds[r].length; k++)
              Positioned(
                left: x(r),
                top: cy(r, k) - _boxH / 2,
                width: boxW,
                height: _boxH,
                child: _box(rounds[r][k], byId, rows, placeholder),
              ),
          if (third != null) ...[
            Positioned(
              left: x(cols - 1),
              top: _headH + treeH + 8,
              width: boxW,
              height: _headH,
              child: const Text(
                '3.LÜK MAÇI',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            Positioned(
              left: x(cols - 1),
              top: _headH + treeH + 8 + _headH,
              width: boxW,
              height: _boxH,
              child: _box(third, byId, rows, placeholder),
            ),
          ],
        ];
        final tree = SizedBox(
          width: width,
          height: height,
          child: Stack(clipBehavior: Clip.none, children: stack),
        );
        if (width <= c.maxWidth) return tree;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: tree,
        );
      },
    );
  }

  String _statusText(Map<String, dynamic>? m) {
    if (m == null) return '';
    final status = (m['status'] ?? '').toString();
    if (status == 'live' || status == 'halftime') return 'CANLI';
    if (status == 'finished') {
      if (m['home_pens'] != null &&
          (_int(m['home_pens']) + _int(m['away_pens'])) > 0) {
        return 'MS · Pen.';
      }
      if (m['extra_time_at'] != null) return 'MS · Uzt.';
      return 'MS';
    }
    final d = DateTime.tryParse((m['match_date'] ?? '').toString());
    if (d == null) return 'Tarih yok';
    const months = [
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', //
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
    ];
    final t = (m['match_time'] ?? '').toString();
    final time = t.length >= 5 ? ' · ${t.substring(0, 5)}' : '';
    return '${d.day} ${months[d.month - 1]}$time';
  }

  Widget _box(
    _Tie tie,
    Map<String, Team> byId,
    List<StandingEntry> rows,
    bool placeholder,
  ) {
    final m = tie.match;
    final status = _statusText(m);
    final live = status == 'CANLI';
    final finished = m?['status'] == 'finished';
    final pens =
        finished &&
        m!['home_pens'] != null &&
        (_int(m['home_pens']) + _int(m['away_pens'])) > 0;

    Widget row(_Side side, bool home) {
      final team = side.teamId == null ? null : byId[side.teamId];
      final lose =
          tie.winner != null &&
          side.teamId != null &&
          side.teamId != tie.winner;
      final win = tie.winner != null && side.teamId == tie.winner;
      final showScore = m != null && (finished || live);
      final String title;
      String? sub;
      if (side.bye) {
        title = 'Bay';
      } else if (placeholder && side.rank != null) {
        // Eşleşme oluşmadı: sıra yer tutucu, altında şu anki takım.
        title = side.hint ?? '${side.rank}. sıra';
        sub = team == null ? null : 'şu an ${shortTeamName(team.name)}';
      } else if (team != null) {
        title = shortTeamName(team.name);
      } else {
        title = side.hint ?? '—';
      }
      final dim = side.bye || (team == null && !placeholder) || lose;
      return SizedBox(
        height: 28,
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                side.rank?.toString() ?? '–',
                style: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 5),
            if (team != null && !(placeholder && side.rank != null)) ...[
              TeamCrest(name: team.name, logoUrl: team.logoUrl, size: 16),
              const SizedBox(width: 5),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: dim ? _muted : Colors.white,
                      fontSize: 12.5,
                      fontWeight: win
                          ? FontWeight.w900
                          : (dim ? FontWeight.w600 : FontWeight.w700),
                    ),
                  ),
                  if (sub != null)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 9.5,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            if (showScore && pens) ...[
              PenaltyBadge(
                _int(m[home ? 'home_pens' : 'away_pens']),
                size: 9.5,
              ),
              const SizedBox(width: 4),
            ],
            if (showScore)
              Text(
                '${_int(m[home ? 'home_score' : 'away_score'])}',
                style: TextStyle(
                  color: lose ? _muted : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      );
    }

    final box = Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 2),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: tie.isFinal ? _gold : _line,
          width: tie.isFinal ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tie.isFinal ? 'FİNAL' : tie.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tie.isFinal ? _gold : _muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                status,
                style: TextStyle(
                  color: live ? _red : _muted,
                  fontSize: 10.5,
                  fontWeight: live ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          row(tie.home, true),
          row(tie.away, false),
        ],
      ),
    );
    if (m == null) return box;
    return GestureDetector(onTap: () => _openMatch(m), child: box);
  }

  void _openMatch(Map<String, dynamic> m) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'MatchDetailsScreen'),
        builder: (_) => MatchDetailsScreen(
          match: MatchModel.fromMap(m, m['id'].toString()),
          isAdmin: AppSession.of(context).value.isAdmin,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Yetkili
  // ---------------------------------------------------------------------------

  Widget _adminCard(
    FormatCup cup,
    int cupIndex,
    CupBracket? bracket,
    List<StandingEntry> rows,
    List<Map<String, dynamic>> matches,
    int remaining,
  ) {
    final started =
        bracket != null &&
        matches.any(
          (m) =>
              (m['cup_bracket_id'] ?? '').toString() == bracket.id &&
              m['status'] != 'notStarted',
        );
    final String text;
    Widget? action;
    if (bracket == null) {
      text = remaining > 0
          ? 'Yetkili: lig bitince ilk tur maçları fikstüre eklenir. '
                '$remaining lig maçı kaldı.'
          : 'Yetkili: lig bitti. İlk tur maçlarını fikstüre ekleyin; '
                'tarih ve saati sonra Maçı Düzenle\'den verin.';
      action = SizedBox(
        width: double.infinity,
        height: 42,
        child: ElevatedButton.icon(
          onPressed: _busy
              ? null
              : () => _create(cup, cupIndex, rows, remaining),
          icon: const Icon(Icons.account_tree_rounded, size: 18),
          label: const Text(
            'Eşleşmeleri Oluştur',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: remaining > 0 ? const Color(0xFF334155) : _green,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      );
    } else {
      text = started
          ? 'Yetkili: maçların tarihini fikstürden Maçı Düzenle ile '
                'değiştirebilirsiniz. Sonraki tur maçları kendiliğinden oluşur.'
          : 'Yetkili: eşleşmeler oluşturuldu. Maç tarihlerini fikstürden '
                'Maçı Düzenle ile verin.';
      if (!started) {
        action = TextButton.icon(
          onPressed: _busy ? null : () => _reset(bracket),
          icon: const Icon(Icons.undo_rounded, size: 18),
          label: const Text('Eşleşmeleri geri al'),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
        );
      }
    }
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 8), action],
        ],
      ),
    );
  }

  Future<void> _create(
    FormatCup cup,
    int cupIndex,
    List<StandingEntry> rows,
    int remaining,
  ) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: remaining > 0 ? 'Lig bitmedi' : 'Eşleşmeleri oluştur',
      message: remaining > 0
          ? '$remaining lig maçı oynanmadı. "${cup.name}" eşleşmeleri şu '
                'anki sıralamayla oluşturulsun mu? Sonradan sıralama değişse '
                'de eşleşmeler değişmez.'
          : '"${cup.name}" ilk tur maçları puan tablosuna göre fikstüre '
                'eklenecek.',
      confirmLabel: 'OLUŞTUR',
      destructive: false,
      icon: Icons.account_tree_rounded,
    );
    if (!ok || !mounted) return;
    String? teamAt(int? rank) =>
        rank == null || rank > rows.length ? null : rows[rank - 1].teamId;
    final firstRound = [
      for (final (a, b) in cup.firstRound())
        {'h': teamAt(a), 'a': teamAt(b), 'hr': a, 'ar': b},
    ];
    await _run(
      () => Supabase.instance.client.rpc(
        'create_cup_bracket',
        params: {
          'p_season_id': widget.seasonId,
          'p_group_id': widget.groupId,
          'p_cup_name': cup.name,
          'p_cup_index': cupIndex,
          'p_tiebreak': cup.tiebreak,
          'p_third': cup.third,
          'p_first_round': firstRound,
        },
      ),
      'Eşleşmeler oluşturuldu; maçlar fikstüre eklendi.',
    );
  }

  Future<void> _reset(CupBracket bracket) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Eşleşmeleri geri al',
      message:
          '"${bracket.cupName}" maçları fikstürden kaldırılacak. Daha sonra '
          'yeniden oluşturabilirsiniz.',
      confirmLabel: 'GERİ AL',
      icon: Icons.undo_rounded,
    );
    if (!ok || !mounted) return;
    await _run(
      () => Supabase.instance.client.rpc(
        'reset_cup_bracket',
        params: {'p_bracket_id': bracket.id},
      ),
      'Eşleşmeler geri alındı.',
    );
  }

  Future<void> _run(Future<dynamic> Function() call, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await call();
      await _reload();
      widget.onBracketsChanged?.call();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on PostgrestException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Turlar arası bağlantı çizgileri: her maçın sağından sonraki turdaki
/// maçın soluna dirsekli çizgi.
class _LinksPainter extends CustomPainter {
  _LinksPainter({
    required this.rounds,
    required this.x,
    required this.cy,
    required this.boxW,
    required this.color,
  });

  final List<int> rounds;
  final double Function(int r) x;
  final double Function(int r, int k) cy;
  final double boxW;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var r = 1; r < rounds.length; r++) {
      for (var k = 0; k < rounds[r]; k++) {
        final tx = x(r), ty = cy(r, k);
        for (final f in [2 * k, 2 * k + 1]) {
          final fx = x(r - 1) + boxW, fy = cy(r - 1, f);
          final mx = (fx + tx) / 2;
          canvas.drawPath(
            Path()
              ..moveTo(fx, fy)
              ..lineTo(mx, fy)
              ..lineTo(mx, ty)
              ..lineTo(tx, ty),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_LinksPainter old) =>
      old.rounds.length != rounds.length ||
      old.boxW != boxW ||
      old.color != color;
}
