import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/active_tournament.dart';
import '../../../core/services/app_session.dart';
import '../../../core/utils/team_colors.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../match/models/match.dart';
import '../../match/screens/match_details_screen.dart';
import '../../tournament/models/league_extras.dart';

const _card = Color(0xFF1E293B);
const _center = Color(0xFF111827);
const _muted = Color(0xFF94A3B8);
const _soft = Color(0xFFE2E8F0);
const _heart = Color(0xFFF87171);

Color _accent() =>
    ActiveTournament.theme.value?.secondary ?? const Color(0xFF10B981);

/// Otomatik haberdeki bir takım (auto_data.home / away).
class _Team {
  _Team(Map? m)
    : id = (m?['id'] ?? '').toString(),
      name = (m?['name'] ?? '').toString(),
      logo = (m?['logo'] ?? '').toString().trim(),
      color = m?['color']?.toString();

  final String id;
  final String name;
  final String logo;
  final String? color;

  /// Bant rengi: takım renginin koyu, her zaman okunur hali.
  Color get band => TeamPalette.of(color, null).background;
}

/// Golcü satırı (auto_data.scorers.home / away).
class _Scorer {
  _Scorer(Map m)
    : name = (m['name'] ?? '').toString(),
      n = (m['n'] as num?)?.toInt() ?? 1,
      pen = (m['pen'] as num?)?.toInt() ?? 0,
      og = m['og'] == true,
      minutes = [
        for (final v in (m['minutes'] as List? ?? const []))
          if (v is num) v.toInt(),
      ];

  final String name;
  final int n;
  final int pen;
  final bool og;
  final List<int> minutes;

  /// "Ali Can (2)", "Veli Er (P)", "Mehmet Ak (K.K.)"
  String get label {
    final b = StringBuffer(name);
    if (og) b.write(' (K.K.)');
    if (n > 1) b.write(' ($n)');
    if (!og && pen > 0) b.write(n == 1 ? ' (P)' : ' ($pen P)');
    return b.toString();
  }

  String get minuteText =>
      minutes.isEmpty ? '' : minutes.map((m) => "$m'").join(', ');
}

/// Bir maçın sonucu (auto_data veya week_results.matches öğesi).
class _Result {
  _Result(Map<String, dynamic> d)
    : matchId = (d['match_id'] ?? '').toString(),
      home = _Team(d['home'] as Map?),
      away = _Team(d['away'] as Map?),
      hs = (d['hs'] as num?)?.toInt() ?? 0,
      as = (d['as'] as num?)?.toInt() ?? 0,
      homeScorers = _list(d, 'home'),
      awayScorers = _list(d, 'away');

  static List<_Scorer> _list(Map d, String side) {
    final s = d['scorers'];
    final l = s is Map ? s[side] : null;
    return [
      for (final m in (l as List? ?? const []))
        if (m is Map) _Scorer(m),
    ];
  }

  final String matchId;
  final _Team home;
  final _Team away;
  final int hs;
  final int as;
  final List<_Scorer> homeScorers;
  final List<_Scorer> awayScorers;
}

Future<void> _openMatch(BuildContext context, String matchId) async {
  if (matchId.isEmpty) return;
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final isAdmin = AppSession.of(context).value.isAdmin;
  try {
    final row = await Supabase.instance.client
        .from('matches')
        .select()
        .eq('id', matchId)
        .single();
    await nav.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'MatchDetailsScreen'),
        builder: (_) => MatchDetailsScreen(
          match: MatchModel.fromMap(row, matchId),
          isAdmin: isAdmin,
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Maç açılamadı: $e')));
  }
}

class _Crest extends StatelessWidget {
  const _Crest(this.team, {this.size = 46});

  final _Team team;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.85),
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: team.logo.isEmpty
          ? Icon(Icons.shield_rounded, size: size * 0.6, color: team.band)
          : WebSafeImage(
              url: team.logo,
              width: size,
              height: size,
              fit: BoxFit.contain,
              isCircle: true,
            ),
    );
  }
}

/// Kartın üst satırı: "Maç sonucu" etiketi, hafta, zaman.
class _Header extends StatelessWidget {
  const _Header({required this.label, required this.meta});

  final String label;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final accent = _accent();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                color: accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Beğeni / paylaş / sağda bağlantı.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.loggedIn,
    required this.liked,
    required this.likeCount,
    required this.onToggleLike,
    required this.onShare,
    this.linkText,
    this.onLink,
  });

  final bool loggedIn;
  final bool liked;
  final int likeCount;
  final VoidCallback onToggleLike;
  final VoidCallback onShare;
  final String? linkText;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    final accent = _accent();
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(4, 0, 6, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: loggedIn
                ? (liked ? 'Beğeniyi geri al' : 'Beğen')
                : 'Beğenmek için giriş yap',
            onPressed: loggedIn ? onToggleLike : null,
            icon: Icon(
              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: liked ? _heart : Colors.white,
              size: 22,
            ),
          ),
          Text(
            '$likeCount',
            style: const TextStyle(
              color: _soft,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          IconButton(
            tooltip: 'Paylaş',
            onPressed: onShare,
            icon: const Icon(
              Icons.send_outlined,
              color: Colors.white,
              size: 20,
            ),
          ),
          const Spacer(),
          if (linkText != null)
            TextButton(
              onPressed: onLink,
              child: Text(
                '$linkText →',
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

BoxDecoration _cardDecoration() => BoxDecoration(
  color: _card,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
);

/// A: maç bitince oluşan skor kartı. Takım renkli bant + iki sütun golcüler.
class MatchResultNewsCard extends StatelessWidget {
  const MatchResultNewsCard({
    super.key,
    required this.item,
    required this.meta,
    required this.loggedIn,
    required this.liked,
    required this.likeCount,
    required this.onToggleLike,
    required this.onShare,
  });

  final NewsItem item;

  /// "4. Hafta · 2 saat önce"
  final String meta;
  final bool loggedIn;
  final bool liked;
  final int likeCount;
  final VoidCallback onToggleLike;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final r = _Result(item.autoData!);
    final matchId = r.matchId.isEmpty ? (item.matchId ?? '') : r.matchId;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _cardDecoration(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openMatch(context, matchId),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(label: 'Maç sonucu', meta: meta),
              _Band(result: r),
              if (r.homeScorers.isNotEmpty || r.awayScorers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _ScorerColumn(r.homeScorers, end: false)),
                      const SizedBox(width: 14),
                      Expanded(child: _ScorerColumn(r.awayScorers, end: true)),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              _Actions(
                loggedIn: loggedIn,
                liked: liked,
                likeCount: likeCount,
                onToggleLike: onToggleLike,
                onShare: onShare,
                linkText: 'Maç detayı',
                onLink: () => _openMatch(context, matchId),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({required this.result});

  final _Result result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    Widget team(_Team t) => Column(
      children: [
        _Crest(t),
        const SizedBox(height: 6),
        Text(
          t.name.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [r.home.band, _center, _center, r.away.band],
          stops: const [0, 0.42, 0.58, 1],
        ),
      ),
      child: Row(
        children: [
          Expanded(child: team(r.home)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                Text(
                  '${r.hs} - ${r.as}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'MAÇ BİTTİ',
                  style: TextStyle(
                    color: _soft,
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: team(r.away)),
        ],
      ),
    );
  }
}

class _ScorerColumn extends StatelessWidget {
  const _ScorerColumn(this.scorers, {required this.end});

  final List<_Scorer> scorers;
  final bool end;

  @override
  Widget build(BuildContext context) {
    if (scorers.isEmpty) {
      return Text(
        'Gol yok',
        textAlign: end ? TextAlign.right : TextAlign.left,
        style: const TextStyle(color: _muted, fontSize: 12.5),
      );
    }
    final ball = Icon(
      Icons.sports_soccer_rounded,
      size: 13,
      color: Colors.white.withValues(alpha: 0.9),
    );
    return Column(
      crossAxisAlignment: end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        for (final s in scorers)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: end
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                if (!end) ...[ball, const SizedBox(width: 6)],
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      text: s.label,
                      children: [
                        if (s.minuteText.isNotEmpty)
                          TextSpan(
                            text: '  ${s.minuteText}',
                            style: const TextStyle(color: _muted, fontSize: 11),
                          ),
                      ],
                    ),
                    textAlign: end ? TextAlign.right : TextAlign.left,
                    style: const TextStyle(color: _soft, fontSize: 12.5),
                  ),
                ),
                if (end) ...[const SizedBox(width: 6), ball],
              ],
            ),
          ),
      ],
    );
  }
}

/// C: haftanın tüm maçları bitince oluşan toplu sonuç haberi. Satıra
/// dokununca o maçın detayı açılır.
class WeekResultsNewsCard extends StatelessWidget {
  const WeekResultsNewsCard({
    super.key,
    required this.item,
    required this.meta,
    required this.loggedIn,
    required this.liked,
    required this.likeCount,
    required this.onToggleLike,
    required this.onShare,
  });

  final NewsItem item;
  final String meta;
  final bool loggedIn;
  final bool liked;
  final int likeCount;
  final VoidCallback onToggleLike;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final d = item.autoData!;
    final week = (d['week'] as num?)?.toInt() ?? item.week;
    final results = [
      for (final m in (d['matches'] as List? ?? const []))
        if (m is Map) _Result(Map<String, dynamic>.from(m)),
    ];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(label: week == null ? 'Hafta' : '$week. Hafta', meta: meta),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(
              week == null ? 'Haftanın sonuçları' : '$week. Hafta sonuçları',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          for (final r in results) _WeekRow(result: r),
          _Actions(
            loggedIn: loggedIn,
            liked: liked,
            likeCount: likeCount,
            onToggleLike: onToggleLike,
            onShare: onShare,
          ),
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.result});

  final _Result result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final homeWin = r.hs > r.as;
    final awayWin = r.as > r.hs;
    Widget name(_Team t, bool win, bool end) => Expanded(
      child: Row(
        mainAxisAlignment: end
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!end) ...[_Crest(t, size: 26), const SizedBox(width: 8)],
          Flexible(
            child: Text(
              t.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: end ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                color: win ? Colors.white : _muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (end) ...[const SizedBox(width: 8), _Crest(t, size: 26)],
        ],
      ),
    );
    final goals = [
      if (r.homeScorers.isNotEmpty)
        r.homeScorers.map((s) => s.label).join(', '),
      if (r.awayScorers.isNotEmpty)
        r.awayScorers.map((s) => s.label).join(', '),
    ].join(' · ');
    return InkWell(
      onTap: () => _openMatch(context, r.matchId),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                name(r.home, homeWin, false),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    '${r.hs} - ${r.as}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                name(r.away, awayWin, true),
              ],
            ),
            if (goals.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                goals,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
