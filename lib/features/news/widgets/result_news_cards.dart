import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/active_tournament.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/instagram_share.dart';
import '../../../core/utils/team_colors.dart';
import '../../../core/utils/team_name.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../../../core/widgets/youtube_player_page.dart';
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

  /// "Ali Can (2)", "Mehmet Ak (K.K.)"; penaltı ayrıca yazılmaz. Dakikalar
  /// yazılıysa gol sayısı zaten görünür, "(2)" eklenmez.
  String get label {
    final b = StringBuffer(name);
    if (og) b.write(' (K.K.)');
    if (n > 1 && minuteText.isEmpty) b.write(' ($n)');
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
    this.onInstagram,
  });

  final bool loggedIn;
  final bool liked;
  final int likeCount;
  final VoidCallback onToggleLike;
  final VoidCallback onShare;
  final String? linkText;
  final VoidCallback? onLink;

  /// Varsa (Android, Instagram yüklü) kart görseli Instagram'da açılır.
  final VoidCallback? onInstagram;

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
          if (onInstagram != null)
            IconButton(
              tooltip: 'Instagram\'da paylaş',
              onPressed: onInstagram,
              icon: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (b) => const LinearGradient(
                  colors: [
                    Color(0xFFF58529),
                    Color(0xFFDD2A7B),
                    Color(0xFF8134AF),
                  ],
                ).createShader(b),
                child: const Icon(Icons.camera_alt_outlined, size: 21),
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
class MatchResultNewsCard extends StatefulWidget {
  const MatchResultNewsCard({
    super.key,
    required this.item,
    required this.meta,
    required this.loggedIn,
    required this.liked,
    required this.likeCount,
    required this.onToggleLike,
    required this.onShare,
    this.onOpenPhoto,
  });

  /// Takım fotoğrafına dokununca tam ekran galeri.
  final ValueChanged<int>? onOpenPhoto;

  final NewsItem item;

  /// "4. Hafta · 2 saat önce"
  final String meta;
  final bool loggedIn;
  final bool liked;
  final int likeCount;
  final VoidCallback onToggleLike;
  final VoidCallback onShare;

  @override
  State<MatchResultNewsCard> createState() => _MatchResultNewsCardState();
}

class _MatchResultNewsCardState extends State<MatchResultNewsCard> {
  /// Instagram'a giden görsel: fotoğraf (o an görünen) + skor + golcüler.
  final _shotKey = GlobalKey();
  late final Future<bool> _instagram = InstagramShare.isAvailable();
  bool _busy = false;

  Future<void> _shareInstagram() async {
    if (_busy) return;
    final story = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: _card,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Instagram\'da paylaş',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Instagram\'da o an açık olan hesaptan paylaşılır.',
                style: TextStyle(color: _muted, fontSize: 12.5),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.grid_on_rounded, color: Colors.white),
              title: const Text(
                'Gönderi',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Açıklama yazarak',
                style: TextStyle(color: _muted),
              ),
              onTap: () => Navigator.pop(ctx, false),
            ),
            ListTile(
              leading: const Icon(
                Icons.amp_stories_outlined,
                color: Colors.white,
              ),
              title: const Text(
                'Hikâye',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Müzik, çıkartma ekleyerek',
                style: TextStyle(color: _muted),
              ),
              onTap: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (story == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final boundary =
          _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      // 1080 piksel genişlik.
      final image = await boundary.toImage(
        pixelRatio: 1080 / boundary.size.width,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('Görsel oluşturulamadı.');
      final ok = await InstagramShare.share(
        data.buffer.asUint8List(),
        story: story,
      );
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Instagram açılamadı.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Instagram\'a aktarılamadı: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
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
              _Header(label: 'Maç sonucu', meta: widget.meta),
              // Takım fotoğrafları varsa (kazananınki önce, sunucu sıralar)
              // skor ve golcüler fotoğrafın altında; kaydırınca diğer takım.
              RepaintBoundary(
                key: _shotKey,
                child: ColoredBox(
                  color: _card,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (item.imageUrls.isNotEmpty)
                        _PhotoResult(
                          result: r,
                          urls: item.imageUrls,
                          onOpen: widget.onOpenPhoto,
                        )
                      else ...[
                        _Band(result: r),
                        if (r.homeScorers.isNotEmpty ||
                            r.awayScorers.isNotEmpty)
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
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              FutureBuilder<bool>(
                future: _instagram,
                builder: (context, snap) => _Actions(
                  loggedIn: widget.loggedIn,
                  liked: widget.liked,
                  likeCount: widget.likeCount,
                  onToggleLike: widget.onToggleLike,
                  onShare: widget.onShare,
                  linkText: 'Maç detayı',
                  onLink: () => _openMatch(context, matchId),
                  onInstagram: snap.data == true && !_busy
                      ? _shareInstagram
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Takım fotoğrafı tam kart: fotoğraflar kaydırılır, alttaki koyu geçişin
/// üstünde armalar + skor ve golcüler sabit durur; sağ üstte "1/2".
class _PhotoResult extends StatefulWidget {
  const _PhotoResult({required this.result, required this.urls, this.onOpen});

  final _Result result;
  final List<String> urls;
  final ValueChanged<int>? onOpen;

  @override
  State<_PhotoResult> createState() => _PhotoResultState();
}

class _PhotoResultState extends State<_PhotoResult> {
  /// Fotoğrafların en/boy oranı (bellekte); takım fotoğrafı kırpılmadan
  /// tam görünsün diye alan bu orana göre açılır.
  static final Map<String, double> _aspects = {};

  final _streams = <ImageStream, ImageStreamListener>{};

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _PhotoResult old) {
    super.didUpdateWidget(old);
    if (old.urls.join() != widget.urls.join()) _resolve();
  }

  void _resolve() {
    for (final url in widget.urls) {
      if (_aspects.containsKey(url)) continue;
      final stream = NetworkImage(url).resolve(const ImageConfiguration());
      late final ImageStreamListener l;
      l = ImageStreamListener(
        (info, _) {
          final w = info.image.width, h = info.image.height;
          if (w > 0 && h > 0) _aspects[url] = w / h;
          stream.removeListener(l);
          _streams.remove(stream);
          if (mounted) setState(() {});
        },
        onError: (_, _) {
          stream.removeListener(l);
          _streams.remove(stream);
        },
      );
      _streams[stream] = l;
      stream.addListener(l);
    }
  }

  @override
  void dispose() {
    _streams.forEach((s, l) => s.removeListener(l));
    super.dispose();
  }

  /// En dik fotoğrafın oranı (hepsi kırpılmadan sığar); yatay–dikey
  /// arası sınırlı, bilinmeyen için takım fotoğraflarına uygun 4:3.
  double get _aspect {
    final known = [
      for (final u in widget.urls)
        if (_aspects[u] != null) _aspects[u]!,
    ];
    if (known.isEmpty) return 4 / 3;
    final a = known.reduce((x, y) => x < y ? x : y);
    return a.clamp(0.8, 1.9);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final urls = widget.urls;
    Widget crest(_Team t) => Container(
      width: 36,
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: t.logo.isEmpty
            ? Icon(Icons.shield_rounded, size: 22, color: t.band)
            : WebSafeImage(url: t.logo, fit: BoxFit.contain),
      ),
    );
    Widget teamName(String name, {required bool end}) => Text(
      name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: end ? TextAlign.right : TextAlign.left,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12.5,
        height: 1.15,
        fontWeight: FontWeight.w800,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: _aspect),
          duration: const Duration(milliseconds: 220),
          builder: (context, a, child) =>
              AspectRatio(aspectRatio: a, child: child),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: const Color(0xFF0B1220),
                child: PageView.builder(
                  itemCount: urls.length,
                  itemBuilder: (context, i) => GestureDetector(
                    onTap: widget.onOpen == null
                        ? null
                        : () => widget.onOpen!(i),
                    // Kırpılmaz: takımın tamamı görünür.
                    child: WebSafeImage(url: urls[i], fit: BoxFit.contain),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Skor ve golcüler fotoğrafın altında, olabildiğince dar: maç
        // detayı başlığındaki gibi ev sahibi rengi → koyu → deplasman rengi.
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                r.home.band,
                const Color(0xFF0B1220),
                const Color(0xFF0B1220),
                r.away.band,
              ],
              stops: const [0, 0.42, 0.58, 1],
            ),
          ),
          child: Row(
            children: [
              crest(r.home),
              const SizedBox(width: 8),
              Expanded(child: teamName(r.home.name, end: false)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${r.hs} - ${r.as}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'MS',
                      style: TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: teamName(r.away.name, end: true)),
              const SizedBox(width: 8),
              crest(r.away),
            ],
          ),
        ),
        if (r.homeScorers.isNotEmpty || r.awayScorers.isNotEmpty)
          Container(
            color: const Color(0xFF0B1220),
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _CompactScorers(r.homeScorers, end: true)),
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                  Expanded(child: _CompactScorers(r.awayScorers, end: false)),
                ],
              ),
            ),
          ),
      ],
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

/// Fotoğraflı sonuç kartında dar golcü listesi: ad + yeşil dakika,
/// ortadaki çizgiye yaslı.
class _CompactScorers extends StatelessWidget {
  const _CompactScorers(this.scorers, {required this.end});

  final List<_Scorer> scorers;
  final bool end;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      for (final s in scorers)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Text.rich(
            TextSpan(
              text: s.label,
              children: [
                if (s.minuteText.isNotEmpty)
                  TextSpan(
                    text: ' ${s.minuteText}',
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
            textAlign: end ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              color: _soft,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
    ],
  );
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
              week == null ? 'Haftanın Sonuçları' : '$week. Hafta Sonuçları',
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
              textAlign: end ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                color: win ? Colors.white : _muted,
                fontSize: 12.5,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (end) ...[const SizedBox(width: 8), _Crest(t, size: 26)],
        ],
      ),
    );
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
    // Golcüler Haberler'de; burada yalnız skor, arkada ilk takım fotoğrafı.
    final r = _Result(d);
    return _DuelStrip(
      home: r.home,
      away: r.away,
      center: '${r.hs} – ${r.as}',
      sub: 'MAÇ BİTTİ',
      caption: week == null ? 'Maç Sonucu' : '$week. Hafta · Maç Sonucu',
      photo: item.imageUrls.firstOrNull,
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
        week == null ? 'Hafta Sonuçları' : '$week. Hafta Sonuçları',
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
        'BUGÜN' => 'Bugünün Maçları',
        'YARIN' => 'Yarının Maçları',
        _ => 'Günün Maçları',
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

const _shadow = [Shadow(color: Colors.black87, blurRadius: 8)];

/// Fotoğraflı bant: fotoğraf arkada (soluk); üstünde kenarlarda takım
/// rengi, ortada koyu örtü, armalar ve skor okunur kalsın.
BoxDecoration _photoBand(String url) => BoxDecoration(
  color: _center,
  image: DecorationImage(
    image: NetworkImage(url),
    fit: BoxFit.cover,
    alignment: const Alignment(0, -0.2),
    colorFilter: ColorFilter.mode(
      Colors.black.withValues(alpha: 0.35),
      BlendMode.darken,
    ),
  ),
);

BoxDecoration _photoOverlay(Color home, Color away) => BoxDecoration(
  gradient: LinearGradient(
    colors: [
      home.withValues(alpha: 0.82),
      _center.withValues(alpha: 0.45),
      _center.withValues(alpha: 0.45),
      away.withValues(alpha: 0.82),
    ],
    stops: const [0, 0.38, 0.62, 1],
  ),
);

/// Tek maç: armalar, büyük harfli tam ad, ortada skor ya da saat.
class _DuelStrip extends StatelessWidget {
  const _DuelStrip({
    required this.home,
    required this.away,
    required this.center,
    required this.sub,
    required this.caption,
    this.highlight = false,
    this.photo,
  });

  final _Team home;
  final _Team away;
  final String center;
  final String sub;
  final String caption;

  /// Takım fotoğrafı: bandın arkasında, üstü takım renkli koyu örtüyle.
  final String? photo;

  /// Maç öncesi: ortadaki saat sarı.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final url = (photo ?? '').trim();
    final hasPhoto = url.isNotEmpty;
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
              shadows: hasPhoto ? _shadow : null,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Container(
          height: newsStripBandHeight,
          decoration: hasPhoto
              ? _photoBand(url)
              : _stripBand(home.band, away.band),
          child: DecoratedBox(
            decoration: hasPhoto
                ? _photoOverlay(home.band, away.band)
                : const BoxDecoration(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
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
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              shadows: hasPhoto ? _shadow : null,
                            ),
                          ),
                        ),
                        if (sub.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            sub,
                            style: TextStyle(
                              color: _soft,
                              fontSize: 10,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                              shadows: hasPhoto ? _shadow : null,
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

// ---------------------------------------------------------------------------
// Haftanın Seçimi: haftanın golü / oyuncusu / takımı. Kapak: seçilen fotoğraf
// (Önemli An, profil, Takım Fotosu ya da yüklenen); yoksa takım renginde
// otomatik kart. Gol kesiti varsa kapaktaki ▶ ile oynar.
// ---------------------------------------------------------------------------

/// Kesit (auto_data.clip / clips öğesi).
class _Clip {
  _Clip(Map m)
    : videoId = (m['video_id'] ?? '').toString(),
      start = (m['start'] as num?)?.toInt() ?? 0,
      end = (m['end'] as num?)?.toInt() ?? 0,
      label = (m['label'] ?? '').toString();

  final String videoId;
  final int start;
  final int end;
  final String label;

  bool get ok => videoId.isNotEmpty && end > start;

  Future<void> play(BuildContext context, String title) => openYoutubeClip(
    context,
    videoId: videoId,
    startSec: start,
    endSec: end,
    title: title,
  );
}

TextStyle _cond(double size, {Color color = Colors.white}) => TextStyle(
  fontFamily: 'BarlowCondensed',
  fontSize: size,
  height: 1,
  color: color,
  fontWeight: FontWeight.w800,
);

class WeeklyPickNewsCard extends StatelessWidget {
  const WeeklyPickNewsCard({
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

  static const _lime = Color(0xFFA3E635);
  static const _gold = Color(0xFFFBBF24);
  static const _sky = Color(0xFF38BDF8);
  static const _ink = Color(0xFF0B1220);

  @override
  Widget build(BuildContext context) {
    final d = item.autoData!;
    final kind = item.autoKind;
    final week = (d['week'] as num?)?.toInt() ?? item.week;
    final home = _Team(d['home'] as Map?);
    final away = _Team(d['away'] as Map?);
    final team = _Team(d['team'] as Map?);
    final player = d['player'] is Map ? d['player'] as Map : const {};
    final playerName = (player['name'] ?? '').toString().trim();
    final playerPhoto = (player['photo'] ?? '').toString().trim();
    final hs = (d['hs'] as num?)?.toInt() ?? 0;
    final as = (d['as'] as num?)?.toInt() ?? 0;
    final score = '${home.name} $hs-$as ${away.name}';
    final note = (d['note'] ?? '').toString().trim();
    final matchId = (d['match_id'] ?? item.matchId ?? '').toString();
    final clip = d['clip'] is Map ? _Clip(d['clip'] as Map) : null;
    final clips = [
      for (final c in (d['clips'] as List? ?? const []))
        if (c is Map && _Clip(c).ok) _Clip(c),
    ];

    final (label, badge, badgeColor) = switch (kind) {
      'goal_of_week' => ('Haftanın Golü', 'HAFTANIN GOLÜ', _lime),
      'player_of_week' => ('Haftanın Oyuncusu', 'HAFTANIN OYUNCUSU', _gold),
      _ => ('Haftanın Takımı', 'HAFTANIN TAKIMI', _sky),
    };
    final title = kind == 'team_of_week' ? team.name : playerName;
    final minute = (d['minute_label'] ?? '').toString();
    final canPlay = kind == 'goal_of_week' && clip != null && clip.ok;
    final photo = (item.imageUrl ?? '').trim();
    final teamColor = TeamPalette.of(team.color, null).background;

    void openCover() {
      if (canPlay) {
        clip.play(context, '$playerName $minute');
      } else {
        _openMatch(context, matchId);
      }
    }

    final cover = AspectRatio(
      aspectRatio: kind == 'team_of_week' ? 4 / 3 : 1.05,
      child: GestureDetector(
        onTap: openCover,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photo.isNotEmpty) ...[
              WebSafeImage(url: photo, fit: BoxFit.cover),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.45, 1],
                    colors: [Color(0x000B1220), Color(0xF20B1220)],
                  ),
                ),
              ),
            ] else
              // Otomatik kart: takım rengi, silik dakika / MVP, oyuncu
              // fotoğrafı ya da arma.
              ColoredBox(
                color: teamColor,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      left: -6,
                      bottom: 70,
                      child: Text(
                        kind == 'goal_of_week'
                            ? minute
                            : kind == 'player_of_week'
                            ? 'MVP'
                            : '$hs-$as',
                        style: _cond(
                          150,
                          color: Colors.black.withValues(alpha: 0.14),
                        ),
                      ),
                    ),
                    Align(
                      alignment: const Alignment(0.75, -0.35),
                      child: kind == 'team_of_week' || playerPhoto.isEmpty
                          ? _Crest(team, size: 120)
                          : Container(
                              width: 160,
                              height: 160,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _ink,
                                border: Border.all(color: _ink, width: 5),
                              ),
                              child: WebSafeImage(
                                url: playerPhoto,
                                fit: BoxFit.cover,
                                isCircle: true,
                              ),
                            ),
                    ),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 96,
                      child: ColoredBox(color: _ink),
                    ),
                  ],
                ),
              ),
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(badge, style: _cond(16, color: _ink)),
              ),
            ),
            if (canPlay)
              Align(
                alignment: const Alignment(0, -0.15),
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _ink.withValues(alpha: 0.72),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 5,
                    ),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          title.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _cond(32),
                        ),
                      ),
                      if (kind == 'goal_of_week' && minute.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Text(minute, style: _cond(26, color: _lime)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (kind != 'team_of_week') ...[
                        _Crest(team, size: 18),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          kind == 'player_of_week'
                              ? '${team.name} · $score'
                              : score,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _cardDecoration(),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              label: label,
              meta: [if (week != null) '$week. Hafta', meta].join(' · '),
            ),
            cover,
            if (kind == 'player_of_week')
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Row(
                  children: [
                    _StatBox('${d['goals'] ?? 0}', 'Gol'),
                    const SizedBox(width: 8),
                    _StatBox('${d['assists'] ?? 0}', 'Asist'),
                    if (d['motm'] == true) ...[
                      const SizedBox(width: 8),
                      const _StatBox(null, 'Maçın Adamı'),
                    ],
                  ],
                ),
              ),
            if (kind == 'player_of_week' && clips.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in clips)
                      _ClipButton(
                        label: c.label.isEmpty ? 'Gol' : c.label,
                        onTap: () => c.play(context, '$playerName ${c.label}'),
                      ),
                  ],
                ),
              ),
            if (kind == 'team_of_week')
              _TeamPickScorers(
                scorers: [
                  for (final m in (d['scorers'] as List? ?? const []))
                    if (m is Map) _Scorer(m),
                ],
              ),
            if (note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Text(
                  note,
                  style: const TextStyle(
                    color: _soft,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
              ),
            const SizedBox(height: 8),
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
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox(this.value, this.label);

  /// null: yıldız (Maçın Adamı).
  final String? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final star = value == null;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: star
              ? WeeklyPickNewsCard._gold.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            if (star)
              const Icon(
                Icons.star_rounded,
                color: WeeklyPickNewsCard._gold,
                size: 28,
              )
            else
              Text(value!, style: _cond(28)),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: star ? const Color(0xFFFDE68A) : _muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClipButton extends StatelessWidget {
  const _ClipButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _accent();
    return Material(
      color: accent.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow_rounded, color: accent, size: 18),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamPickScorers extends StatelessWidget {
  const _TeamPickScorers({required this.scorers});

  final List<_Scorer> scorers;

  @override
  Widget build(BuildContext context) {
    if (scorers.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final s in scorers)
            Text(
              [s.label, s.minuteText].where((e) => e.isNotEmpty).join(' '),
              style: const TextStyle(color: _soft, fontSize: 12.5),
            ),
        ],
      ),
    );
  }
}
