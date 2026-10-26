import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/active_tournament.dart';
import '../../../core/services/app_session.dart';
import '../../../core/utils/team_colors.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../match/models/match.dart';
import '../../match/widgets/match_weather.dart';
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
      // Uygulamanın her yerindeki kural: "Masterler / Masterlar" eki
      // gösterilmez, "Spor Kulübü" → SK.
      name = shortTeamName((m?['name'] ?? '').toString()),
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
      ],
      // Uzatmalı etiketler (30+2'); eski haberlerde yok.
      labels = [
        for (final v in (m['labels'] as List? ?? const []))
          if (v != null) v.toString(),
      ];

  final String name;
  final int n;
  final int pen;
  final bool og;
  final List<int> minutes;
  final List<String> labels;

  /// "Ali Can (2)", "Mehmet Ak (K.K.)"; penaltı ayrıca yazılmaz.
  String get label {
    final b = StringBuffer(name);
    if (og) b.write(' (K.K.)');
    if (n > 1) b.write(' ($n)');
    return b.toString();
  }

  String get minuteText => labels.isNotEmpty
      ? labels.join(', ')
      : minutes.isEmpty
      ? ''
      : minutes.map((m) => "$m'").join(', ');
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
                      Expanded(
                        child: _ScorerColumn(
                          r.homeScorers,
                          goals: r.hs,
                          end: false,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _ScorerColumn(
                          r.awayScorers,
                          goals: r.as,
                          end: true,
                        ),
                      ),
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
  const _ScorerColumn(this.scorers, {required this.goals, required this.end});

  final List<_Scorer> scorers;

  /// Takımın skoru.
  final int goals;
  final bool end;

  @override
  Widget build(BuildContext context) {
    // Golcü yoksa boş kalır ("Gol yok" yazılmaz).
    if (scorers.isEmpty) return const SizedBox.shrink();
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

// ---------------------------------------------------------------------------
// Maç günü haberleri (maç öncesi): A tek maç kartı, C günün programı.
// ---------------------------------------------------------------------------

/// Maç kartındaki takım: sonuç kartındaki takıma ek olarak puan, sıra, form.
class _PreviewTeam extends _Team {
  _PreviewTeam(super.m)
    : points = (m?['points'] as num?)?.toInt(),
      rank = (m?['rank'] as num?)?.toInt(),
      form = [for (final f in (m?['form'] as List? ?? const [])) '$f'];

  final int? points;
  final int? rank;
  final List<String> form;

  /// "3. sıra · 10 puan" (eşit puanlı takım varsa yalnız puan).
  String get standing => [
    if (rank != null) '$rank. sıra',
    if (points != null) '$points puan',
  ].join(' · ');
}

/// "BUGÜN", "YARIN" ya da "24.10".
String _dayLabel(String? date, String? status) {
  if (status == 'live' || status == 'halftime') return 'CANLI';
  final d = DateTime.tryParse(date ?? '');
  if (d == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = DateTime(d.year, d.month, d.day).difference(today).inDays;
  if (diff == 0) return 'BUGÜN';
  if (diff == 1) return 'YARIN';
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
}

String _windLabel(num kmh) => kmh < 12
    ? 'rüzgâr hafif'
    : kmh < 29
    ? 'rüzgâr orta'
    : 'rüzgâr sert';

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});

  final Widget icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _soft,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Son maçlar: G yeşil, B gri, M kırmızı.
class _FormRow extends StatelessWidget {
  const _FormRow(this.form, {required this.end});

  final List<String> form;
  final bool end;

  @override
  Widget build(BuildContext context) {
    Color c(String r) => switch (r) {
      'G' => const Color(0xFF22C55E),
      'M' => const Color(0xFFEF4444),
      _ => const Color(0xFF64748B),
    };
    return Row(
      mainAxisAlignment: end ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        for (final r in form)
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c(r),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              r,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
      ],
    );
  }
}

/// A: maç günü sabah oluşan tek maç kartı. Maç bitince sistem gizler (yerine
/// sonuç kartı gelir).
class MatchPreviewNewsCard extends StatelessWidget {
  const MatchPreviewNewsCard({
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
    final home = _PreviewTeam(d['home'] as Map?);
    final away = _PreviewTeam(d['away'] as Map?);
    final matchId = (d['match_id'] ?? item.matchId ?? '').toString();
    final time = (d['time'] ?? '').toString().trim();
    final day = _dayLabel(d['date']?.toString(), d['status']?.toString());
    final pitch = (d['pitch'] ?? '').toString().trim();
    final cup = (d['cup'] ?? '').toString().trim();
    final w = d['weather'] is Map ? d['weather'] as Map : null;
    final h2h = d['h2h'] is Map ? d['h2h'] as Map : null;

    Widget team(_PreviewTeam t) => Column(
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
        if (t.standing.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            t.standing,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _soft, fontSize: 10.5),
          ),
        ],
      ],
    );

    String? h2hText;
    if (h2h != null) {
      final homeFirst = (h2h['home_id'] ?? '').toString() == home.id;
      final a = homeFirst ? home.name : away.name;
      final b = homeFirst ? away.name : home.name;
      final year = h2h['year'];
      h2hText =
          '$a ${h2h['hs'] ?? 0}–${h2h['as'] ?? 0} $b'
          '${year == null ? '' : ' ($year)'}';
    }

    final chips = <Widget>[
      if (pitch.isNotEmpty)
        _Chip(
          icon: const Icon(Icons.stadium_rounded, size: 14, color: _muted),
          text: pitch,
        ),
      if (w != null && w['temp'] != null)
        _Chip(
          icon: WeatherGlyph(
            code: (w['code'] as num?)?.toInt() ?? 800,
            isDay: w['day'] != false,
            size: 16,
          ),
          text: [
            '${w['temp']}°',
            if ((w['pop'] as num? ?? 0) >= 20) '%${w['pop']} yağmur',
            if (w['wind'] is num) _windLabel(w['wind'] as num),
          ].join(' · '),
        ),
    ];

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
              _Header(
                label: 'Maç günü',
                meta: [if (cup.isNotEmpty) cup, meta].join(' · '),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 16, 10, 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [home.band, _center, _center, away.band],
                    stops: const [0, 0.42, 0.58, 1],
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: team(home)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Column(
                        children: [
                          Text(
                            time.isEmpty ? '–' : time,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            day,
                            style: TextStyle(
                              color: day == 'CANLI'
                                  ? const Color(0xFFF87171)
                                  : _soft,
                              fontSize: 10,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: team(away)),
                  ],
                ),
              ),
              if (chips.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: Wrap(spacing: 6, runSpacing: 6, children: chips),
                ),
              if (home.form.isNotEmpty || away.form.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: Row(
                    children: [
                      Expanded(child: _FormRow(home.form, end: false)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'Son maçlar',
                          style: TextStyle(color: _muted, fontSize: 11),
                        ),
                      ),
                      Expanded(child: _FormRow(away.form, end: true)),
                    ],
                  ),
                ),
              if (h2hText != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: Text.rich(
                    TextSpan(
                      text: 'Aralarındaki son maç: ',
                      children: [
                        TextSpan(
                          text: h2hText,
                          style: const TextStyle(
                            color: _soft,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 10),
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

/// C: o gün bölgede 2+ maç varsa günün programı. Satıra dokununca maç açılır.
class DayPreviewNewsCard extends StatelessWidget {
  const DayPreviewNewsCard({
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
    final day = _dayLabel(d['date']?.toString(), null);
    final matches = [
      for (final m in (d['matches'] as List? ?? const []))
        if (m is Map) m,
    ];
    final title = switch (day) {
      'BUGÜN' => 'Bugünün Maçları',
      'YARIN' => 'Yarının Maçları',
      _ => 'Günün Maçları',
    };
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            label: week == null ? 'Maç günü' : '$week. Hafta',
            meta: meta,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${matches.length} maç',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          for (final m in matches) _DayRow(m),
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

class _DayRow extends StatelessWidget {
  const _DayRow(this.m);

  final Map m;

  @override
  Widget build(BuildContext context) {
    final home = _Team(m['home'] as Map?);
    final away = _Team(m['away'] as Map?);
    final time = (m['time'] ?? '').toString().trim();
    final pitch = (m['pitch'] ?? '').toString().trim();
    final status = (m['status'] ?? '').toString();
    final live = status == 'live' || status == 'halftime';
    final done = status == 'finished';
    return InkWell(
      onTap: () => _openMatch(context, (m['match_id'] ?? '').toString()),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                live ? 'CANLI' : (done ? 'Bitti' : (time.isEmpty ? '–' : time)),
                style: TextStyle(
                  color: live ? const Color(0xFFF87171) : Colors.white,
                  fontSize: live || done ? 11.5 : 15,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${home.name} – ${away.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: done ? _muted : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (pitch.isNotEmpty)
                    Text(
                      pitch,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 11.5),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white24),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ana sayfa haber kartı: otomatik haberin tek satırlık skor görünümü
// (iki takım + skor/saat, altında kısa bilgi). Yükseklik sabit (68).
// ---------------------------------------------------------------------------

/// Ana sayfa haber kartındaki bandın yüksekliği (alt yazı hariç).
const double newsStripBandHeight = 138;

/// Bant + alt yazının toplam yüksekliği; ana sayfa kartı bu kadar yer ayırır.
const double newsStripHeight = newsStripBandHeight + 30;

/// Otomatik haber için ana sayfa bandı; kart türü değilse null.
Widget? autoNewsStrip(NewsItem item) {
  final d = item.autoData;
  if (d == null) return null;
  final week = (d['week'] as num?)?.toInt() ?? item.week;

  if (item.isMatchResult) {
    final r = _Result(d);
    final scorers = [...r.homeScorers, ...r.awayScorers]
      ..sort((a, b) => b.n.compareTo(a.n));
    final shown = scorers.take(2).map((s) => s.short).join(', ');
    return _DuelStrip(
      home: r.home,
      away: r.away,
      center: '${r.hs} – ${r.as}',
      sub: 'MAÇ BİTTİ',
      caption: [
        if (week != null) '$week. hafta',
        if (shown.isNotEmpty)
          '⚽ $shown${scorers.length > 2 ? ' +${scorers.length - 2}' : ''}',
      ].join(' · '),
    );
  }
  if (item.isWeekResults) {
    final results = [
      for (final m in (d['matches'] as List? ?? const []))
        if (m is Map) _Result(Map<String, dynamic>.from(m)),
    ];
    if (results.isEmpty) return null;
    final goals = results.fold<int>(0, (a, x) => a + x.hs + x.as);
    return _ListStrip(
      rows: [for (final r in results) (r.home, '${r.hs} – ${r.as}', r.away)],
      caption: [
        week == null ? 'Hafta sonuçları' : '$week. hafta sonuçları',
        '$goals gol',
      ].join(' · '),
    );
  }
  if (item.isMatchPreview) {
    final status = d['status']?.toString();
    final live = status == 'live' || status == 'halftime';
    final time = (d['time'] ?? '').toString().trim();
    final pitch = (d['pitch'] ?? '').toString().trim();
    final w = d['weather'] is Map ? d['weather'] as Map : null;
    return _DuelStrip(
      home: _Team(d['home'] as Map?),
      away: _Team(d['away'] as Map?),
      center: live ? 'CANLI' : (time.isEmpty ? '-' : time),
      sub: live ? '' : _dayLabel(d['date']?.toString(), status),
      highlight: true,
      caption: [
        if (week != null) '$week. hafta',
        if (pitch.isNotEmpty) pitch,
        if (w != null && w['temp'] != null) '${w['temp']}°',
      ].join(' · '),
    );
  }
  if (item.isDayPreview) {
    final matches = [
      for (final m in (d['matches'] as List? ?? const []))
        if (m is Map) m,
    ];
    if (matches.isEmpty) return null;
    final day = _dayLabel(d['date']?.toString(), null);
    return _ListStrip(
      highlight: true,
      rows: [
        for (final m in matches)
          (
            _Team(m['home'] as Map?),
            () {
              final t = (m['time'] ?? '').toString().trim();
              return t.isEmpty ? '-' : t;
            }(),
            _Team(m['away'] as Map?),
          ),
      ],
      caption: switch (day) {
        'BUGÜN' => 'Bugünün maçları',
        'YARIN' => 'Yarının maçları',
        _ => 'Günün maçları',
      },
    );
  }
  return null;
}

/// Bandın altındaki tek satırlık açıklama.
class _StripCaption extends StatelessWidget {
  const _StripCaption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: newsStripHeight - newsStripBandHeight,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
      ),
    ),
  );
}

/// Takım renginden ortadaki koyu alana geçen bant (Haberler sekmesiyle aynı).
BoxDecoration _stripBand(Color home, Color away, {double tint = 1}) =>
    BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Color.lerp(_center, home, tint)!,
          _center,
          _center,
          Color.lerp(_center, away, tint)!,
        ],
        stops: const [0, 0.42, 0.58, 1],
      ),
    );

extension on _Scorer {
  /// "K. Kahya 2" (ana sayfa satırı için kısa).
  String get short {
    final parts = name.trim().split(RegExp(r'\s+'));
    final n0 = parts.length > 1
        ? '${parts.first.characters.first}. ${parts.sublist(1).join(' ')}'
        : name.trim();
    return n > 1 ? '$n0 $n' : n0;
  }
}

/// Tek maç: armalar, büyük harfli tam ad, ortada skor ya da saat.
class _DuelStrip extends StatelessWidget {
  const _DuelStrip({
    required this.home,
    required this.away,
    required this.center,
    required this.sub,
    required this.caption,
    this.highlight = false,
  });

  final _Team home;
  final _Team away;
  final String center;
  final String sub;
  final String caption;

  /// Maç öncesi: ortadaki saat sarı.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    Widget team(_Team t) {
      final name = t.name.toUpperCase();
      // Ad kelime bütün kalarak alt satıra iner; sütuna sığmayacak kadar
      // uzun tek kelime varsa yazı küçülür.
      final long = name.split(' ').any((w) => w.characters.length > 11);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Crest(t, size: 54),
          const SizedBox(height: 7),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: long ? 11 : 12,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Container(
          height: newsStripBandHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: _stripBand(home.band, away.band),
          child: Row(
            children: [
              Expanded(child: team(home)),
              SizedBox(
                width: 100,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        center,
                        maxLines: 1,
                        style: TextStyle(
                          color: highlight
                              ? const Color(0xFFFBBF24)
                              : Colors.white,
                          fontSize: highlight ? 30 : 36,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        sub,
                        style: const TextStyle(
                          color: _soft,
                          fontSize: 10,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(child: team(away)),
            ],
          ),
        ),
        _StripCaption(caption),
      ],
    );
  }
}

/// Birden çok maç (hafta sonuçları, günün maçları): en çok 3 satır.
class _ListStrip extends StatelessWidget {
  const _ListStrip({
    required this.rows,
    required this.caption,
    this.highlight = false,
  });

  final List<(_Team, String, _Team)> rows;
  final String caption;

  /// Maç öncesi: saatler sarı.
  final bool highlight;

  static const _max = 3;

  @override
  Widget build(BuildContext context) {
    final shown = rows.take(_max).toList();
    final more = rows.length - shown.length;
    Widget name(_Team t, bool end) => Expanded(
      child: Text(
        t.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: end ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    return Column(
      children: [
        Container(
          height: newsStripBandHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: _stripBand(
            shown.first.$1.band,
            shown.first.$3.band,
            tint: 0.55,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (h, c, a) in shown)
                SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      name(h, true),
                      const SizedBox(width: 7),
                      _Crest(h, size: 24),
                      Container(
                        width: 56,
                        margin: const EdgeInsets.symmetric(horizontal: 7),
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          c,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: highlight
                                ? const Color(0xFFFBBF24)
                                : Colors.white,
                            fontSize: highlight ? 13.5 : 15,
                            fontWeight: FontWeight.w900,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      _Crest(a, size: 24),
                      const SizedBox(width: 7),
                      name(a, false),
                    ],
                  ),
                ),
              if (more > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '+$more maç daha',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        _StripCaption(caption),
      ],
    );
  }
}
