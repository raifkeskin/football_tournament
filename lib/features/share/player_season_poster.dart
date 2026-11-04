import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/app_session.dart';
import '../../core/services/app_settings.dart';
import '../../core/services/image_upload_service.dart';
import '../../core/services/photo_cutouts.dart';
import '../../core/utils/string_utils.dart';
import '../../core/utils/team_colors.dart';
import '../../core/utils/team_name.dart';
import '../news/week_awards.dart';
import 'poster_background.dart';
import 'poster_share.dart';

/// Bireysel sezon afişi ("Sezon vitrini"): oyuncunun fotoğrafı, sezonun
/// sayıları (maç, gol, asist, maçın oyuncusu) ve Haftanın Enleri'nde
/// aldığı ödüller. Futbolcu yalnız kendi afişini, admin / kurucu başkan /
/// bölge sorumlusu herkesinkini çıkarır.

/// Profilde paylaş ikonu görünsün mü? Yeni özellik: ayar kapalıyken yalnız
/// admin; açıkken futbolcu kendi profilinde, yöneticiler her profilde.
bool canShowPlayerPoster(BuildContext context, String playerId) {
  if (playerId.isEmpty) return false;
  final s = AppSession.of(context).value;
  if (s.isAdmin) return true;
  if (!playerPosterAllowed(s)) return false;
  return s.playerId == playerId || s.isLeagueOwner || s.isRegionOwner;
}

/// Afiş ve "Bu benim" yıldızı bu hesaba açık mı: admin, ayar açıksa
/// herkes, kapalıyken deneme hesapları (player_poster_users).
bool playerPosterAllowed(AppSessionState s) {
  final u = s.user;
  if (u == null || u.isAnonymous) return false;
  if (s.isAdmin || AppSettings.playerPosterEnabled.value) return true;
  return AppSettings.playerPosterUsers.value.contains(u.id);
}

/// Afişteki bir ödül satırı: "HAFTANIN OYUNCUSU" · "2. HAFTA".
class PosterAward {
  const PosterAward({
    required this.title,
    required this.weeks,
    required this.color,
    required this.mark,
  });

  final String title;
  final List<int> weeks;
  final Color color;

  /// Rozetteki kısa işaret ("★", "11").
  final String mark;

  String get weekText {
    final w = [...weeks]..sort();
    final list = '${w.join(', ')}. HAFTA';
    return w.length > 1 ? '×${w.length} · $list' : list;
  }
}

class PlayerPosterData {
  const PlayerPosterData({
    required this.name,
    required this.number,
    required this.teamName,
    required this.teamLogo,
    required this.teamColor,
    required this.leagueName,
    required this.leagueLogo,
    required this.matches,
    required this.goals,
    required this.assists,
    required this.motm,
    required this.awards,
  });

  final String name;
  final String number;
  final String teamName;
  final String teamLogo;
  final Color teamColor;
  final String leagueName;
  final String leagueLogo;
  final int matches;
  final int goals;
  final int assists;
  final int motm;
  final List<PosterAward> awards;

  /// "İbrahim" + "AÇAN": son kelime soyad.
  (String, String) get split {
    final w = name.trim().split(RegExp(r'\s+'));
    if (w.length < 2) return ('', name.trUpper);
    return (w.sublist(0, w.length - 1).join(' ').trUpper, w.last.trUpper);
  }
}

const _bg = Color(0xFF060B14);
const _muted = Color(0xFF94A3B8);
const _gold = Color(0xFFE2B845);

TextStyle _cond(
  double size, {
  Color color = Colors.white,
  double spacing = 0,
  bool italic = false,
}) => GoogleFonts.barlowCondensed(
  fontSize: size,
  color: color,
  fontWeight: FontWeight.w800,
  letterSpacing: spacing,
  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
  height: 1,
);

class PlayerSeasonPoster extends StatelessWidget {
  const PlayerSeasonPoster({
    super.key,
    required this.data,
    this.photo,
    this.frame = const PhotoFrame(),
  });

  final PlayerPosterData data;
  final ImageProvider? photo;
  final PhotoFrame frame;

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    final size = st.format.size;
    final w = size.width;
    final h = size.height;
    final accent = _accent(data.teamColor);
    final deep = Color.lerp(data.teamColor, _bg, 0.55)!;
    final (first, last) = data.split;
    final awards = data.awards.take(st.isPost ? 2 : 3).toList();
    final photoW = w * 0.78;
    final photoH = st.pick(h * 0.66, h * 0.8);
    final stats = <(String, String)>[
      ('${data.matches}', 'MAÇ'),
      ('${data.goals}', 'GOL'),
      ('${data.assists}', 'ASİST'),
      if (data.motm > 0) ('${data.motm}', 'MAÇIN OYUNCUSU'),
    ];

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [deep, _bg],
          stops: const [0, 0.62],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -w * 0.1,
            top: h * 0.14,
            width: w * 0.9,
            height: w * 0.9,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [accent.withValues(alpha: 0.28), Colors.transparent],
                ),
              ),
            ),
          ),
          if (data.number.trim().isNotEmpty)
            Positioned(
              left: 4,
              top: st.pick(52, 40),
              child: Text(
                data.number.trim(),
                style: _cond(
                  st.pick(130, 100),
                  italic: true,
                  color: accent.withValues(alpha: 0.08),
                ),
              ),
            ),
          // Fotoğraf: alta ve sağa doğru zemine erir (dekupede kenar yok).
          Positioned(
            left: -w * 0.06,
            top: st.pick(64, 50),
            width: photoW,
            height: photoH,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: [0, 0.7, 1],
              ).createShader(r),
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.black, Colors.black, Colors.transparent],
                  stops: [0, 0.6, 1],
                ).createShader(r),
                child: photo == null
                    ? const SizedBox.shrink()
                    : ClipRect(
                        child: Transform.scale(
                          scale: frame.zoom,
                          alignment: frame.align,
                          child: Image(
                            image: photo!,
                            width: photoW,
                            height: photoH,
                            fit: BoxFit.cover,
                            alignment: frame.align,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          if (photo == null)
            Positioned(
              left: w * 0.08,
              top: st.pick(120, 80),
              child: PosterLogo(
                url: data.teamLogo,
                name: data.teamName,
                size: st.pick(170, 130),
                shadow: true,
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            top: st.pick(18, 14),
            child: Row(
              children: [
                PosterLogo(
                  url: data.leagueLogo,
                  name: data.leagueName,
                  size: st.pick(28, 24),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.leagueName.trUpper,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _cond(st.pick(13, 12)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SEZON KARNESİ',
                        style: _cond(st.pick(10, 9), color: _gold, spacing: 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 16,
            top: st.pick(78, 58),
            width: w * 0.36,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0) SizedBox(height: st.pick(10, 6)),
                  Text(
                    stats[i].$1,
                    style: _cond(
                      i == 0 ? st.pick(32, 26) : st.pick(50, 38),
                      color: i == 0 ? Colors.white : accent,
                    ).copyWith(shadows: _shadow),
                  ),
                  Text(
                    stats[i].$2,
                    textAlign: TextAlign.right,
                    style: _cond(
                      st.pick(10.5, 9.5),
                      color: const Color(0xFFCBD5E1),
                      spacing: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: st.pick(40, 34),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    PosterLogo(
                      url: data.teamLogo,
                      name: data.teamName,
                      size: st.pick(30, 24),
                      shadow: true,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        shortTeamName(data.teamName).trUpper,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _cond(
                          st.pick(12.5, 11),
                          color: accent,
                          spacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: st.pick(4, 2)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (first.isNotEmpty) TextSpan(text: '$first '),
                        TextSpan(
                          text: last,
                          style: TextStyle(color: accent),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    style: _cond(st.pick(40, 32)).copyWith(shadows: _shadow),
                  ),
                ),
                if (awards.isNotEmpty) SizedBox(height: st.pick(12, 8)),
                for (final a in awards) ...[
                  _AwardRow(award: a),
                  SizedBox(height: st.pick(6, 4)),
                ],
              ],
            ),
          ),
          Positioned(
            left: 16,
            bottom: st.pick(12, 10),
            child: const PosterAppMark(),
          ),
        ],
      ),
    );
  }
}

const _shadow = [Shadow(color: Colors.black87, blurRadius: 10)];

/// Takım rengi koyu ya da soluksa okunur bir vurgu.
Color _accent(Color c) {
  final hsl = HSLColor.fromColor(c);
  if (hsl.lightness < 0.45 || hsl.saturation < 0.2) return _gold;
  return c;
}

class _AwardRow extends StatelessWidget {
  const _AwardRow({required this.award});

  final PosterAward award;

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    final badge = st.pick(26.0, 22.0);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: st.pick(6, 4)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: award.color, width: 3)),
      ),
      child: Row(
        children: [
          Container(
            width: badge,
            height: badge,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: award.color,
              shape: BoxShape.circle,
            ),
            child: Text(
              award.mark,
              style: _cond(badge * 0.5, color: const Color(0xFF0B1424)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(award.title, style: _cond(st.pick(13, 12))),
                const SizedBox(height: 2),
                Text(
                  award.weekText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _cond(st.pick(10, 9), color: _muted, spacing: 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Oyuncunun o sezonki Haftanın Enleri ödülleri (yayınlanmış bültenlerden).
Future<List<PosterAward>> _loadAwards(String playerId, String seasonId) async {
  final byKind = <AwardKind, List<int>>{};
  final eleven = <int>[];
  try {
    final rows = await Supabase.instance.client
        .from('news')
        .select('week, auto_data')
        .eq('season_id', seasonId)
        .eq('auto_kind', 'week_awards')
        .eq('is_published', true);
    for (final r in rows) {
      final d = r['auto_data'];
      if (d is! Map) continue;
      final w = WeekAwards.fromJson(d);
      final week = w.week > 0 ? w.week : ((r['week'] as num?)?.toInt() ?? 0);
      if (week <= 0) continue;
      if (w.hasEleven && w.eleven.any((s) => s.person.id == playerId)) {
        eleven.add(week);
      }
      for (final a in w.awards) {
        if (a.person?.id == playerId) {
          byKind.putIfAbsent(a.kind, () => []).add(week);
        }
      }
    }
  } catch (_) {}
  return [
    for (final k in AwardKind.values)
      if (byKind[k] != null)
        PosterAward(
          title: k.full.trUpper,
          weeks: byKind[k]!,
          color: k.color,
          mark: switch (k) {
            AwardKind.player => '★',
            AwardKind.keeper => 'K',
            AwardKind.fair => 'C',
            AwardKind.goal => 'G',
            _ => '•',
          },
        ),
    if (eleven.isNotEmpty)
      PosterAward(
        title: "HAFTANIN 11'İ",
        weeks: eleven,
        color: const Color(0xFF34D399),
        mark: '11',
      ),
  ];
}

/// Oyuncunun yıldızladığı ("Bu benim") maç fotoğrafları, en yeni önde.
Future<List<String>> loadStarredPhotos(String playerId) async {
  try {
    final rows = await Supabase.instance.client
        .from('player_photo_stars')
        .select('created_at, match_media(url)')
        .eq('player_id', playerId)
        .order('created_at', ascending: false);
    return [
      for (final r in rows)
        if (r['match_media'] is Map)
          ((r['match_media'] as Map)['url'] ?? '').toString().trim(),
    ].where((u) => u.isNotEmpty).toList();
  } catch (_) {
    return const [];
  }
}

/// Sezon afişi penceresi. [stats]: profil kartının o sezon için hesapladığı
/// sayılar (maç, gol, asist, maçın oyuncusu).
Future<void> showPlayerSeasonPoster(
  BuildContext context, {
  required String playerId,
  required String name,
  required String number,
  required String photoUrl,
  required String seasonId,
  required String leagueName,
  required String leagueLogo,
  required String teamId,
  required String teamName,
  required String teamLogo,
  required ({int matches, int goals, int assists, int motm}) stats,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final sb = Supabase.instance.client;
  String? colorHex;
  final results = await Future.wait<Object?>([
    _loadAwards(playerId, seasonId),
    loadStarredPhotos(playerId),
    PhotoCutouts.ensureLoaded(),
    () async {
      try {
        final t = await sb
            .from('teams')
            .select('first_color')
            .eq('id', teamId)
            .maybeSingle();
        colorHex = t?['first_color']?.toString();
      } catch (_) {}
    }(),
  ]);
  if (!context.mounted) return;
  final awards = results[0] as List<PosterAward>;
  final starred = results[1] as List<String>;
  final data = PlayerPosterData(
    name: name,
    number: number,
    teamName: teamName,
    teamLogo: teamLogo,
    teamColor: TeamPalette.of(colorHex, null).primary,
    leagueName: leagueName,
    leagueLogo: leagueLogo,
    matches: stats.matches,
    goals: stats.goals,
    assists: stats.assists,
    motm: stats.motm,
    awards: awards,
  );
  // Profil fotoğrafının dekupesi varsa o; yoksa büyük kopyası.
  final profile = photoUrl.trim();
  final cutout = PhotoCutouts.map.value[profile] ?? '';
  final start = cutout.isNotEmpty
      ? cutout
      : profile.isEmpty
      ? ''
      : SupabaseImageUploadService.hdUrl(profile);
  final choices = [
    if (start.isNotEmpty) start,
    ...starred.where((u) => u != start),
  ];
  try {
    await showPosterPreview(
      context: context,
      title: 'Sezon Afişi',
      fileName: 'sezon_${name.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}',
      formats: const [PosterFormat.story, PosterFormat.post],
      imageUrls: [leagueLogo, teamLogo].where((u) => u.isNotEmpty).toList(),
      photoPoster: (photo, frame) =>
          PlayerSeasonPoster(data: data, photo: photo, frame: frame),
      photoUrl: start.isEmpty ? null : start,
      photoChoices: choices,
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Afiş açılamadı: $e')));
  }
}
