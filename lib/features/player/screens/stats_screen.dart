import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/player_stats.dart';
import '../widgets/player_card.dart';
import '../../team/models/team.dart';
import '../../match/services/interfaces/i_match_service.dart';
import '../../team/services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/web_safe_image.dart';

// ORTAK BİLEŞEN
import '../../../core/utils/string_utils.dart';
import '../../../core/utils/team_colors.dart';
import '../../../core/services/app_session.dart';

/// Bir sezonun oyuncu istatistikleri (gol, asist, maçın oyuncusu, kartlar).
/// Başlık çubuğu yok; Turnuva Sayfası'nın İstatistik sekmesinde gösterilir.
class StatsView extends StatefulWidget {
  const StatsView({super.key, required this.seasonId});

  final String seasonId;

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  final IMatchService _matchService = ServiceLocator.matchService;
  final ITeamService _teamService = ServiceLocator.teamService;
  late final Stream<List<Team>> _teamsStream = _teamService.watchAllTeams();

  // İstatistikteki oyuncuların ad + fotoğrafı tek sorguda okunur (önceden
  // her satır ayrı sorgu atıyordu). Aynı oyuncu kümesi için tekrar okunmaz.
  String? _playersKey;
  Future<Map<String, _PlayerLite>>? _playersFuture;

  /// Şimdiye kadar okunan oyuncular (ekran yeniden çizilince isimler
  /// bir an kaybolup geri gelmesin).
  static final Map<String, _PlayerLite> _playersKnown = {};

  Future<Map<String, _PlayerLite>> _playersFor(Set<String> ids) {
    final key = (ids.toList()..sort()).join(',');
    if (key == _playersKey && _playersFuture != null) return _playersFuture!;
    _playersKey = key;
    return _playersFuture = () async {
      if (ids.isEmpty) return const <String, _PlayerLite>{};
      // İstatistik anahtarı oyuncunun telefonu, telefonu yoksa id'si.
      final uuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false,
      );
      final byId = ids.where(uuid.hasMatch).toList();
      final byPhone = ids.where((k) => !uuid.hasMatch(k)).toList();
      final client = Supabase.instance.client;
      final rows = [
        if (byId.isNotEmpty)
          ...await client
              .from('players')
              .select('id, phone, name, surname, photo_url')
              .inFilter('id', byId),
        if (byPhone.isNotEmpty)
          ...await client
              .from('players')
              .select('id, phone, name, surname, photo_url')
              .inFilter('phone', byPhone),
      ];
      final out = <String, _PlayerLite>{};
      for (final r in rows) {
        final p = _PlayerLite(
          name: [
            (r['name'] ?? '').toString().trim(),
            (r['surname'] ?? '').toString().trim(),
          ].where((e) => e.isNotEmpty).join(' '),
          photoUrl: (r['photo_url'] ?? '').toString().trim(),
        );
        for (final k in [r['id'], r['phone']]) {
          final key = (k ?? '').toString().trim();
          if (key.isNotEmpty) out[key] = p;
        }
      }
      _playersKnown.addAll(out);
      return out;
    }();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: StreamBuilder<List<Team>>(
        stream: _teamsStream,
        builder: (context, teamsSnap) {
          if (!teamsSnap.hasData &&
              teamsSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final teams = (teamsSnap.data ?? const <Team>[])
              .where((t) => t.id != 'free_agent_pool')
              .toList();
          final teamById = {for (final t in teams) t.id: t};

          return StreamBuilder<List<PlayerStats>>(
            stream: _matchService.watchPlayerStats(
              tournamentId: widget.seasonId,
            ),
            builder: (context, statsSnap) {
              if (!statsSnap.hasData &&
                  statsSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              // Sadece golü, asisti, ödülü ya da kartı olan oyuncular.
              final stats = (statsSnap.data ?? const <PlayerStats>[])
                  .where(
                    (s) =>
                        s.goals > 0 ||
                        s.assists > 0 ||
                        s.manOfTheMatch > 0 ||
                        s.yellowCards > 0 ||
                        s.redCards > 0,
                  )
                  .toList();

              if (stats.isEmpty) {
                return Center(
                  child: Text(
                    'Bu sezon için istatistik bulunmuyor.',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }

              final ids = stats.map((s) => s.playerPhone).toSet();
              return FutureBuilder<Map<String, _PlayerLite>>(
                future: _playersFor(ids),
                initialData: ids.every(_playersKnown.containsKey)
                    ? _playersKnown
                    : null,
                builder: (context, pSnap) {
                  // İsimler gelmeden ham anahtarlar gösterilmez.
                  if (!pSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _StatsTabs(
                    stats: stats,
                    teamById: teamById,
                    players: pSnap.data!,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _MiniTeamLogo extends StatelessWidget {
  const _MiniTeamLogo({required this.logoUrl, required this.fallbackText});
  final String logoUrl;
  final String fallbackText;

  String _normalizeUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return 'https://$url';
  }

  @override
  Widget build(BuildContext context) {
    final url = _normalizeUrl(logoUrl);
    return WebSafeImage(
      url: url,
      width: 16,
      height: 16,
      fit: BoxFit.contain,
      fallbackIconSize: 12,
    );
  }
}

// ---------------------------------------------------------------------------
// Krallıklar: kategori düğmeleri, lider kartı ve çubuklu sıralama listesi.
// ---------------------------------------------------------------------------

const _accent = Color(0xFF10B981);
const _card = Color(0xFF1E293B);
const _muted = Color(0xFF94A3B8);
const _gold = Color(0xFFFBBF24);

class _PlayerLite {
  const _PlayerLite({required this.name, required this.photoUrl});
  final String name;
  final String photoUrl;
}

/// Sıralanmış satır: eşit değerdekiler aynı sırayı paylaşır (1, 2, 2, 4).
class _Ranked {
  const _Ranked(this.rank, this.stats, this.value);
  final int rank;
  final PlayerStats stats;
  final int value;
}

List<_Ranked> _rank(
  List<PlayerStats> all,
  int Function(PlayerStats) value, {
  bool tieRed = false,
}) {
  final list = all.where((s) => value(s) > 0).toList()
    ..sort((a, b) {
      final c = value(b).compareTo(value(a));
      if (c != 0) return c;
      // Kartlarda eşitlikte kırmızısı çok olan önde.
      if (tieRed && a.redCards != b.redCards) {
        return b.redCards.compareTo(a.redCards);
      }
      // Eşitlikte daha az maçta yapan önde.
      return a.matchesPlayed.compareTo(b.matchesPlayed);
    });
  final out = <_Ranked>[];
  for (var i = 0; i < list.length && i < 20; i++) {
    final v = value(list[i]);
    final rank = i > 0 && value(list[i - 1]) == v ? out[i - 1].rank : i + 1;
    out.add(_Ranked(rank, list[i], v));
  }
  return out;
}

/// İstatistik kategorisi: sıralama değeri, birimi ve satırdaki ek bilgi.
class _Category {
  const _Category({
    required this.label,
    required this.unit,
    required this.crown,
    required this.icon,
    required this.value,
    this.perMatch = true,
    this.detail,
  });

  final String label;
  final String unit;

  /// Lider kartındaki unvan (GOL KRALI…).
  final String crown;
  final IconData icon;
  final int Function(PlayerStats) value;

  /// Maç başı ortalama gösterilsin mi (kartlarda anlamsız).
  final bool perMatch;

  /// Değerin altındaki küçük yazı (ör. "2 sarı · 1 kırmızı").
  final String Function(PlayerStats)? detail;
}

final _categories = <_Category>[
  _Category(
    label: 'Gol',
    unit: 'gol',
    crown: 'GOL KRALI',
    icon: Icons.sports_soccer_rounded,
    value: (s) => s.goals,
  ),
  _Category(
    label: 'Asist',
    unit: 'asist',
    crown: 'ASİST KRALI',
    icon: Icons.assistant_rounded,
    value: (s) => s.assists,
  ),
  _Category(
    label: 'Maçın Adamı',
    unit: 'kez',
    crown: 'EN ÇOK MAÇIN ADAMI',
    icon: Icons.star_rounded,
    value: (s) => s.manOfTheMatch,
  ),
  _Category(
    label: 'Kartlar',
    unit: 'kart',
    crown: 'EN ÇOK KART',
    icon: Icons.style_rounded,
    // Kırmızı kart sarıdan ağır sayılır; ekranda toplam kart görünür.
    value: (s) => s.yellowCards + s.redCards,
    perMatch: false,
    detail: (s) => '${s.yellowCards} sarı · ${s.redCards} kırmızı',
  ),
];

/// "1,50" biçiminde maç başı ortalama; maç sayısı yoksa null.
String? _perMatch(int value, int matches) {
  if (matches <= 0) return null;
  return (value / matches).toStringAsFixed(2).replaceAll('.', ',');
}

Color _teamColor(Team? team) =>
    parseHexColor(team?.firstColor) ?? const Color(0xFF15803D);

class _StatsTabs extends StatefulWidget {
  const _StatsTabs({
    required this.stats,
    required this.teamById,
    required this.players,
  });

  final List<PlayerStats> stats;
  final Map<String, Team> teamById;
  final Map<String, _PlayerLite> players;

  @override
  State<_StatsTabs> createState() => _StatsTabsState();
}

class _StatsTabsState extends State<_StatsTabs> {
  int _cat = 0;

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;
    final mine = {
      if ((session.playerId ?? '').isNotEmpty) session.playerId!,
      if (session.phone.isNotEmpty) session.phone,
    };
    final cat = _categories[_cat];
    final rows = _rank(widget.stats, cat.value, tieRed: _cat == 4);
    return Column(
      children: [
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final on = i == _cat;
              return GestureDetector(
                onTap: () => setState(() => _cat = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    color: on ? Colors.white : _card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: on
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    _categories[i].label,
                    style: TextStyle(
                      color: on ? const Color(0xFF0B1220) : _muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: _Board(
            key: ValueKey(_cat),
            category: cat,
            rows: rows,
            teamById: widget.teamById,
            players: widget.players,
            mine: mine,
          ),
        ),
      ],
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({
    super.key,
    required this.category,
    required this.rows,
    required this.teamById,
    required this.players,
    required this.mine,
  });

  final _Category category;
  final List<_Ranked> rows;
  final Map<String, Team> teamById;
  final Map<String, _PlayerLite> players;

  /// Giriş yapan futbolcunun istatistik anahtarları (id / telefon).
  final Set<String> mine;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.icon, size: 48, color: Colors.white24),
            const SizedBox(height: 10),
            Text(
              'Henüz ${category.label.toLowerCase()} kaydı yok.',
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }
    final leader = rows.first;
    final top = leader.value;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
      children: [
        _LeaderCard(
          row: leader,
          category: category,
          team: teamById[leader.stats.teamId],
          player: players[leader.stats.playerPhone],
        ),
        const SizedBox(height: 12),
        for (final r in rows.skip(1))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _RankRow(
              row: r,
              category: category,
              ratio: top <= 0 ? 0 : r.value / top,
              team: teamById[r.stats.teamId],
              player: players[r.stats.playerPhone],
              isMe: mine.contains(r.stats.playerPhone),
            ),
          ),
      ],
    );
  }
}

/// Lider kartı: takım renginden koyu zemine geçiş, sağda oyuncunun silik
/// fotoğrafı (avatarla aynı dosya, ek indirme yok), solda yuvarlak profil.
class _LeaderCard extends StatelessWidget {
  const _LeaderCard({
    required this.row,
    required this.category,
    required this.team,
    required this.player,
  });

  final _Ranked row;
  final _Category category;
  final Team? team;
  final _PlayerLite? player;

  static const _dark = Color(0xFF0F172A);

  @override
  Widget build(BuildContext context) {
    final name = (player?.name ?? '').isEmpty ? 'Oyuncu' : player!.name;
    final photo = player?.photoUrl ?? '';
    final color = _teamColor(team);
    final s = row.stats;
    final avg = category.perMatch
        ? _perMatch(row.value, s.matchesPlayed)
        : null;
    return GestureDetector(
      onTap: () => showPlayerCard(context, playerKey: s.playerPhone),
      child: Container(
        // En az 156: takım satırı da olunca içerik taşmasın, kart uzasın.
        constraints: const BoxConstraints(minHeight: 156),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: _dark,
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            if (photo.isNotEmpty)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 190,
                child: WebSafeImage(
                  url: photo,
                  width: 190,
                  height: 156,
                  fit: BoxFit.cover,
                ),
              ),
            // Takım rengi soldan gelir, fotoğrafın üstünü örterek silikleştirir.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      color,
                      Color.lerp(color, _dark, 0.55)!,
                      Color.lerp(
                        color,
                        _dark,
                        0.7,
                      )!.withValues(alpha: photo.isEmpty ? 1 : 0.55),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.35),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: _gold,
                    ),
                    child: _PlayerAvatar(name: name, photoUrl: photo, size: 72),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '♛ ${category.crown}',
                          style: const TextStyle(
                            color: _gold,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (team != null)
                          Row(
                            children: [
                              _MiniTeamLogo(
                                logoUrl: team!.logoUrl,
                                fallbackText: team!.name,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  team!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '${row.value}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 40,
                                height: 1,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              category.unit,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            '${s.matchesPlayed} maç',
                            if (avg != null) '$avg maç başı',
                            if (category.detail != null) category.detail!(s),
                          ].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Liste satırı: sıra, avatar, ad + lidere göre takım renginde çubuk, değer
/// ve maç başı ortalama. Giriş yapan futbolcunun satırı vurgulanır.
class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.row,
    required this.category,
    required this.ratio,
    required this.team,
    required this.player,
    required this.isMe,
  });

  final _Ranked row;
  final _Category category;
  final double ratio;
  final Team? team;
  final _PlayerLite? player;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final name = (player?.name ?? '').isEmpty ? 'Oyuncu' : player!.name;
    final s = row.stats;
    final color = _teamColor(team);
    final sub =
        category.detail?.call(s) ??
        (category.perMatch
            ? (_perMatch(row.value, s.matchesPlayed) ?? '-')
            : null);
    return Material(
      color: isMe ? Color.lerp(_card, _accent, 0.14) : _card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showPlayerCard(context, playerKey: s.playerPhone),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isMe ? _accent : Colors.white.withValues(alpha: 0.07),
              width: isMe ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${row.rank}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _PlayerAvatar(
                name: name,
                photoUrl: player?.photoUrl ?? '',
                size: 36,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (team != null) ...[
                          _MiniTeamLogo(
                            logoUrl: team!.logoUrl,
                            fallbackText: team!.name,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(
                        children: [
                          Container(
                            height: 5,
                            color: Colors.white.withValues(alpha: 0.07),
                          ),
                          FractionallySizedBox(
                            widthFactor: ratio.clamp(0.04, 1.0),
                            child: Container(
                              height: 5,
                              color: Color.lerp(color, Colors.white, 0.15),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${row.value}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      category.detail != null ? sub : '$sub/maç',
                      style: const TextStyle(color: _muted, fontSize: 10.5),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Oyuncu fotoğrafı; yoksa baş harfler.
class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({
    required this.name,
    required this.photoUrl,
    required this.size,
  });

  final String name;
  final String photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.characters.first)
        .join()
        .trUpper;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF064E3B),
      ),
      child: photoUrl.isNotEmpty
          ? WebSafeImage(
              url: photoUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              isCircle: true,
              fallbackIconSize: size * 0.4,
            )
          : Text(
              initials,
              style: TextStyle(
                color: const Color(0xFF6EE7B7),
                fontSize: size * 0.34,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}
