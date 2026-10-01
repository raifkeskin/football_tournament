import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tournament/models/league.dart';
import '../../../core/widgets/web_safe_image.dart';

// Uygulamanın ortak renkleri
const _bgDark = Color(0xFF0F172A);
const _surface = Color(0xFF1E293B);
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

/// Oyuncu kartını popup olarak açar. [playerKey] oyuncu id'si ya da telefonu
/// (istatistik ekranları telefonla tanımlar). Diğer bilgiler buradan okunur.
Future<void> showPlayerCard(
  BuildContext context, {
  required String playerKey,
  String number = '',
}) {
  final key = playerKey.trim();
  final isId = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(key);
  final future = Supabase.instance.client
      .from('players')
      .select(
        'id, name, surname, photo_url, birth_date, height, weight, '
        'main_position, sub_position',
      )
      .eq(isId ? 'id' : 'phone', key)
      .limit(1);
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator(color: _accent)),
            );
          }
          final rows = snap.data ?? const [];
          if (rows.isEmpty) {
            return Container(
              color: _bgDark,
              padding: const EdgeInsets.all(24),
              child: const Text(
                'Oyuncu bulunamadı.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            );
          }
          final r = rows.first;
          String str(String k) => (r[k] ?? '').toString().trim();
          return PlayerCard(
            playerPhone: key,
            name: [str('name'), str('surname')]
                .where((e) => e.isNotEmpty)
                .join(' '),
            number: number,
            photoUrl: str('photo_url'),
            position: _positionLabel(str('main_position'), str('sub_position')),
            birthDate: str('birth_date'),
            height: (r['height'] as num?)?.toInt(),
            weight: (r['weight'] as num?)?.toInt(),
            seasons: const [],
            initialSeasonId: '',
          );
        },
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
    required this.birthDate,
    required this.height,
    required this.weight,
    required this.seasons,
    required this.initialSeasonId,
  });

  final String playerPhone;
  final String name;
  final String number;
  final String photoUrl;
  final String position;
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

  String _birthYear() {
    final s = widget.birthDate.trim();
    if (s.isEmpty) return '-';
    final any = RegExp(r'(\d{4})').firstMatch(s);
    return any?.group(1) ?? '-';
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
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
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
  /// Kart telefon ya da id ile açılabiliyor; id'ye çevirir.
  Future<String?> _resolvePlayerId(String key) async {
    if (_uuidLike.hasMatch(key)) return key;
    try {
      final r = await _sb.from('players').select('id').eq('phone', key).limit(1);
      return r.isEmpty ? null : (r.first['id'] ?? '').toString();
    } catch (_) {
      return null;
    }
  }

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
            add(mid, const _StatTotals(yellow: 1));
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
      final teamIds = {
        for (final l in links) (l['team_id'] ?? '').toString(),
      }..remove('');
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

    final seasonIds = totalsBySeason.keys.toList();

    final seasonById = <String, Map<String, dynamic>>{};
    final leagueById = <String, Map<String, dynamic>>{};
    if (seasonIds.isNotEmpty) {
      try {
        final res = await _sb
            .from('seasons')
            .select('id, name, league_id, start_date')
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
    for (final entry in totalsBySeason.entries) {
      overall = overall + entry.value;
      final seasonRow = seasonById[entry.key];
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SectionTitle(
                      icon: Icons.insights_rounded,
                      title: 'Kariyer Özeti',
                    ),
                    const SizedBox(height: 10),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      _summaryGrid(data.overall),
                    const SizedBox(height: 22),
                    const _SectionTitle(
                      icon: Icons.emoji_events_outlined,
                      title: 'Turnuva Geçmişi',
                    ),
                    const SizedBox(height: 10),
                    if (!loading && data.tournaments.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: _panel(),
                        child: const Text(
                          'Henüz turnuva verisi yok.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _mid),
                        ),
                      )
                    else if (!loading)
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
    final name = widget.name.trim().isEmpty ? '-' : widget.name.trim();
    final age = _ageFromBirthDate(widget.birthDate);
    final photoHeight = (MediaQuery.of(context).size.height * 0.34).clamp(
      230.0,
      320.0,
    );

    Widget info(IconData icon, String label, String value) => Expanded(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                Icon(icon, size: 13, color: _accent),
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
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_surface, _forest],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
              tooltip: 'Kapat',
            ),
          ),
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
                            color: _accent.withValues(alpha: 0.6),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _accent.withValues(alpha: 0.18),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: photo.isEmpty
                            ? Center(
                                child: Text(
                                  _initials(name),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 56,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              )
                            : WebSafeImage(
                                url: photo,
                                fit: BoxFit.cover,
                                fallbackIconSize: 48,
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
                              color: _accent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '#$number',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
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
                      info(
                        Icons.cake_outlined,
                        'Yaş',
                        age == null ? '-' : '$age',
                      ),
                      const SizedBox(height: 8),
                      info(
                        Icons.height_rounded,
                        'Boy',
                        widget.height == null ? '-' : '${widget.height} cm',
                      ),
                      const SizedBox(height: 8),
                      info(
                        Icons.monitor_weight_outlined,
                        'Kilo',
                        widget.weight == null ? '-' : '${widget.weight} kg',
                      ),
                      const SizedBox(height: 8),
                      info(Icons.event_outlined, 'Doğum', _birthYear()),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          if (pos.isNotEmpty && pos != '-') ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  pos,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
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
                fontWeight: FontWeight.w900,
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
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
            ),
          ),
        );

    Widget header() => Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Turnuva – Sezon',
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

    final children = <Widget>[header()];
    var first = true;
    for (final t in tournaments) {
      for (final sn in t.seasons) {
        final x = sn.totals;
        children.add(
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(
              border: first
                  ? null
                  : Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${t.name} – ${sn.name}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (sn.teams.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(
                              Icons.shield_outlined,
                              size: 12,
                              color: _accent,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                sn.teams.join(', '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _accent,
                                  fontSize: 12,
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
        );
        first = false;
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _accent, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ],
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
