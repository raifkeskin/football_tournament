import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/app_session.dart';
import '../../core/services/image_upload_service.dart';
import '../../core/utils/string_utils.dart';
import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../../core/widgets/app_name_band.dart';
import '../../core/widgets/picked_image.dart';
import '../../core/widgets/web_safe_image.dart';
import 'instagram_embed.dart';

/// Turnuva videoları ve maç röportajları: Instagram gönderisi / Reels
/// bağlantısı (videos tablosu). Video Instagram'da kalır, uygulamada gömülü
/// oynatılır. Ekleme/silme: admin, kurucu başkan, bölge sorumlusu.
enum VideoKind {
  tournament('tournament', 'Turnuva', Color(0xFFFBBF24)),
  pre('pre', 'Maç öncesi', Color(0xFF38BDF8)),
  live('live', 'Maç anı', Color(0xFFF59E0B)),
  post('post', 'Maç sonrası', Color(0xFFA78BFA));

  const VideoKind(this.code, this.label, this.color);
  final String code;
  final String label;
  final Color color;

  static VideoKind of(String? code) => VideoKind.values.firstWhere(
    (k) => k.code == code,
    orElse: () => VideoKind.tournament,
  );

  static const interviews = [pre, live, post];
}

/// Videoda etiketlenen futbolcu (röportaj yapılan).
class VideoTag {
  const VideoTag({required this.id, required this.name, this.photo = ''});
  final String id;
  final String name;
  final String photo;

  factory VideoTag.fromMap(Map m) => VideoTag(
    id: (m['id'] ?? m['player_id'] ?? '').toString(),
    name: (m['name'] ?? '').toString().trim(),
    photo: (m['photo'] ?? m['photo_url'] ?? '').toString().trim(),
  );
}

/// Etiketlenebilecek futbolcu: maçın iki takımının kadrosu.
class VideoTagCandidate {
  const VideoTagCandidate(this.tag, this.teamId, this.teamName);
  final VideoTag tag;
  final String teamId;
  final String teamName;
}

class VideoItem {
  const VideoItem({
    required this.id,
    required this.url,
    required this.kind,
    this.seasonId = '',
    this.matchId,
    this.title = '',
    this.teamName = '',
    this.teamLogo = '',
    this.pinned = false,
    this.matchLabel = '',
    this.week,
    this.coverUrl = '',
    this.logoUrl = '',
    this.teamId,
    this.players = const [],
  });

  final String? teamId;

  /// Etiketlenen futbolcular (haber verisinden; listelerde boş).
  final List<VideoTag> players;

  final String id;
  final String url;
  final VideoKind kind;
  final String seasonId;
  final String? matchId;
  final String title;
  final String teamName;
  final String teamLogo;
  final bool pinned;

  /// Röportajın maçı: "Ev – Deplasman".
  final String matchLabel;
  final int? week;

  /// Yüklenen kapak fotoğrafı; yoksa turnuva videosunda [logoUrl].
  final String coverUrl;

  /// Turnuva logosu (kapaksız turnuva videosunun görseli).
  final String logoUrl;

  /// Kutucukta görsel var mı (kapak ya da turnuva videosunda logo).
  bool get hasImage =>
      coverUrl.isNotEmpty ||
      (kind == VideoKind.tournament && logoUrl.isNotEmpty);

  /// Kutucukta ve oynatıcıda görünen ad.
  String get label {
    if (title.isNotEmpty) return title;
    if (teamName.isNotEmpty) return teamName;
    return kind.label;
  }

  factory VideoItem.fromRow(Map<String, dynamic> r) {
    final team = r['teams'] is Map ? r['teams'] as Map : const {};
    final m = r['matches'] is Map ? r['matches'] as Map : const {};
    final home = m['home'] is Map ? (m['home'] as Map)['name'] : null;
    final away = m['away'] is Map ? (m['away'] as Map)['name'] : null;
    final season = r['seasons'] is Map ? r['seasons'] as Map : const {};
    final league = season['leagues'] is Map
        ? season['leagues'] as Map
        : const {};
    return VideoItem(
      id: (r['id'] ?? '').toString(),
      url: (r['url'] ?? '').toString(),
      kind: VideoKind.of(r['kind']?.toString()),
      seasonId: (r['season_id'] ?? '').toString(),
      matchId: r['match_id']?.toString(),
      title: (r['title'] ?? '').toString().trim(),
      teamName: (team['name'] ?? '').toString().trim(),
      teamLogo: (team['logo_url'] ?? '').toString().trim(),
      pinned: r['pinned'] == true,
      matchLabel: home == null || away == null ? '' : '$home – $away',
      week: (m['week'] as num?)?.toInt(),
      coverUrl: (r['cover_url'] ?? '').toString().trim(),
      logoUrl: (league['logo_url'] ?? '').toString().trim(),
      teamId: r['team_id']?.toString(),
    );
  }

  /// Haberdeki video listesinden (news.auto_data.videos).
  factory VideoItem.fromNews(Map v, VideoKind kind, {String logo = ''}) =>
      VideoItem(
        id: (v['id'] ?? '').toString(),
        url: (v['url'] ?? '').toString(),
        kind: kind,
        title: (v['title'] ?? '').toString().trim(),
        teamName: (v['team'] ?? '').toString().trim(),
        teamLogo: (v['team_logo'] ?? '').toString().trim(),
        coverUrl: (v['cover'] ?? '').toString().trim(),
        logoUrl: logo,
        teamId: v['team_id']?.toString(),
        players: [
          for (final p in (v['players'] as List? ?? const []))
            if (p is Map) VideoTag.fromMap(p),
        ],
      );

  /// Profildeki röportaj listesinden (player_videos).
  factory VideoItem.fromPlayerRow(Map r) => VideoItem(
    id: (r['id'] ?? '').toString(),
    url: (r['url'] ?? '').toString(),
    kind: VideoKind.of(r['kind']?.toString()),
    seasonId: (r['season_id'] ?? '').toString(),
    matchId: r['match_id']?.toString(),
    title: (r['title'] ?? '').toString().trim(),
    teamName: (r['team_name'] ?? '').toString().trim(),
    teamLogo: (r['team_logo'] ?? '').toString().trim(),
    matchLabel: (r['match_label'] ?? '').toString(),
    week: (r['week'] as num?)?.toInt(),
    coverUrl: (r['cover_url'] ?? '').toString().trim(),
  );
}

class VideoService {
  VideoService._();

  static SupabaseClient get _db => Supabase.instance.client;

  /// Ekleme / silme sonrası listeler yeniden okunur.
  static final changed = ValueNotifier<int>(0);

  static const _select =
      'id, season_id, match_id, kind, team_id, title, url, pinned, '
      'cover_url, '
      'created_at, teams(name, logo_url), seasons(leagues(logo_url)), '
      'matches(week, home:teams!home_team_id(name), away:teams!away_team_id(name))';

  static Future<List<VideoItem>> forSeason(String seasonId) async {
    final rows = await _db
        .from('videos')
        .select(_select)
        .eq('season_id', seasonId)
        .order('created_at', ascending: false);
    return [for (final r in rows) VideoItem.fromRow(r)];
  }

  /// Takımın röportajları (video eklerken seçilen takım).
  static Future<List<VideoItem>> forTeam(String seasonId, String teamId) async {
    final rows = await _db
        .from('videos')
        .select(_select)
        .eq('season_id', seasonId)
        .eq('team_id', teamId)
        .order('created_at', ascending: false);
    return [for (final r in rows) VideoItem.fromRow(r)];
  }

  static Future<List<VideoItem>> forMatch(String matchId) async {
    final rows = await _db
        .from('videos')
        .select(_select)
        .eq('match_id', matchId)
        .order('created_at', ascending: true);
    return [for (final r in rows) VideoItem.fromRow(r)];
  }

  /// Ekler ve yeni videonun kimliğini döner.
  static Future<String> add({
    String? seasonId,
    String? matchId,
    required VideoKind kind,
    String? teamId,
    String? title,
    required String url,
    bool pinned = false,
    bool asNews = false,
    String? coverUrl,
  }) async {
    final id = await _db.rpc(
      'video_add',
      params: {
        'p_season': seasonId,
        'p_match': matchId,
        'p_kind': kind.code,
        'p_team': teamId,
        'p_title': title,
        'p_url': url.trim(),
        'p_pinned': pinned,
        'p_as_news': asNews,
        'p_cover': coverUrl,
      },
    );
    changed.value++;
    return (id ?? '').toString();
  }

  /// Maçın iki takımının kadrosu (etiketleme için).
  static Future<List<VideoTagCandidate>> tagCandidates(String matchId) async {
    final rows =
        await _db.rpc('video_tag_candidates', params: {'p_match': matchId})
            as List;
    return [
      for (final r in rows)
        if (r is Map)
          VideoTagCandidate(
            VideoTag.fromMap(r),
            (r['team_id'] ?? '').toString(),
            (r['team_name'] ?? '').toString(),
          ),
    ];
  }

  /// Videonun şu anki etiketleri (futbolcu kimlikleri).
  static Future<Set<String>> taggedIds(String videoId) async {
    final rows = await _db
        .from('video_players')
        .select('player_id')
        .eq('video_id', videoId);
    return {for (final r in rows) r['player_id'].toString()};
  }

  static Future<void> setPlayers(String videoId, Iterable<String> ids) async {
    await _db.rpc(
      'video_set_players',
      params: {'p_id': videoId, 'p_players': ids.toList()},
    );
    changed.value++;
  }

  /// Futbolcunun etiketlendiği röportajlar (profil).
  static Future<List<VideoItem>> forPlayer(String playerId) async {
    final rows =
        await _db.rpc('player_videos', params: {'p_player': playerId}) as List;
    return [
      for (final r in rows)
        if (r is Map) VideoItem.fromPlayerRow(r),
    ];
  }

  static Future<void> delete(String id) async {
    await _db.rpc('video_delete', params: {'p_id': id});
    changed.value++;
  }

  /// Kapak fotoğrafını değiştirir; null kaldırır.
  static Future<void> setCover(String id, String? coverUrl) async {
    await _db.rpc('video_set_cover', params: {'p_id': id, 'p_cover': coverUrl});
    changed.value++;
  }

  /// Maç röportajının türü: pre / live / post.
  static Future<void> setKind(String id, VideoKind kind) async {
    await _db.rpc('video_set_kind', params: {'p_id': id, 'p_kind': kind.code});
    changed.value++;
  }

  static Future<void> setPinned(String id, bool pinned) async {
    await _db.rpc('video_set_pinned', params: {'p_id': id, 'p_pinned': pinned});
    changed.value++;
  }

  /// Kullanıcıya gösterilecek hata metni (veritabanının Türkçe mesajı).
  static String errorText(Object e) {
    if (e is PostgrestException && e.message.trim().isNotEmpty) {
      return e.message;
    }
    if (e is Exception && e.toString().startsWith('Exception: ')) {
      return e.toString().substring(11);
    }
    return 'Video eklenemedi. Bağlantıyı kontrol edin.';
  }
}

/// Sezonun medyasını yönetebilir mi (veritabanındaki can_manage_season_media
/// ile aynı): admin, kurucu başkan, o sezonda bölge sorumlusu.
bool canManageVideos(AppSessionState s, String? leagueId, String seasonId) =>
    s.canManageLeague(leagueId) || s.regionsInSeason(seasonId).isNotEmpty;

/// Instagram gönderisi / Reels bağlantısı mı (hikâye değil).
bool isInstagramPostUrl(String url) => RegExp(
  r'instagram\.com/(?:[A-Za-z0-9_.]+/)?(p|reel|reels|tv)/[A-Za-z0-9_-]+',
  caseSensitive: false,
).hasMatch(url);

/// Video kutucuğu: türün renginde zemin, takım arması, oynat simgesi ve ad.
class VideoTile extends StatelessWidget {
  const VideoTile({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.caption,
    this.large = false,
  });

  final VideoItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Alt satır (ör. maç ve hafta); yoksa yalnız ad.
  final String? caption;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = item.kind.color;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(c, const Color(0xFF0F172A), 0.45)!,
                const Color(0xFF0F172A),
              ],
            ),
          ),
          child: Stack(
            children: [
              if (item.coverUrl.isNotEmpty)
                Positioned.fill(
                  child: WebSafeImage(url: item.coverUrl, fit: BoxFit.cover),
                )
              else if (item.kind == VideoKind.tournament &&
                  item.logoUrl.isNotEmpty)
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        colors: [Color(0xFF1E3A8A), Color(0xFF0B1220)],
                        radius: 0.9,
                      ),
                    ),
                    padding: EdgeInsets.all(large ? 22 : 12),
                    child: WebSafeImage(url: item.logoUrl, fit: BoxFit.contain),
                  ),
                ),
              if (item.hasImage)
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.55, 1],
                        colors: [Colors.transparent, Color(0xB3000000)],
                      ),
                    ),
                  ),
                ),
              if (item.teamLogo.isNotEmpty)
                Positioned(
                  left: 8,
                  top: 8,
                  child: WebSafeImage(
                    url: item.teamLogo,
                    width: large ? 34 : 24,
                    height: large ? 34 : 24,
                    fit: BoxFit.contain,
                  ),
                ),
              Positioned(
                right: 7,
                top: 7,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF58529), Color(0xFFDD2A7B)],
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
              if (item.pinned)
                const Positioned(
                  right: 30,
                  top: 7,
                  child: Icon(
                    Icons.push_pin_rounded,
                    size: 16,
                    color: Color(0xFFFBBF24),
                  ),
                ),
              Center(
                child: Container(
                  width: large ? 52 : 34,
                  height: large ? 52 : 34,
                  decoration: const BoxDecoration(
                    color: Color(0x8C000000),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: large ? 32 : 22,
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (caption != null && caption!.isNotEmpty)
                      Text(
                        caption!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c,
                          fontSize: large ? 11 : 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    Text(
                      item.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: large ? 16 : 11.5,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Videoları tam ekranda oynatır; yana kaydırınca listedeki diğer video.
Future<void> openVideoPlayer(
  BuildContext context,
  List<VideoItem> items,
  int index,
) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'VideoPlayerPage'),
      builder: (_) => _VideoPlayerPage(items: items, initial: index),
    ),
  );
}

class _VideoPlayerPage extends StatefulWidget {
  const _VideoPlayerPage({required this.items, required this.initial});
  final List<VideoItem> items;
  final int initial;

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _i = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final cur = items[_i];
    final n = items.length;
    return BandBackPage(
      subtitle: n > 1 ? '${cur.kind.label} · ${_i + 1}/$n' : cur.kind.label,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pc,
                  itemCount: n,
                  onPageChanged: (i) => setState(() => _i = i),
                  itemBuilder: (_, i) =>
                      InstagramEmbed(url: items[i].url, focused: true),
                ),
              ),
              Container(
                color: kAdminBg,
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Önceki',
                      onPressed: _i == 0
                          ? null
                          : () => _pc.previousPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            ),
                      icon: const Icon(Icons.chevron_left_rounded),
                      color: Colors.white,
                      disabledColor: Colors.white24,
                    ),
                    Expanded(
                      child: Text(
                        [
                          cur.label,
                          if (cur.matchLabel.isNotEmpty) cur.matchLabel,
                        ].join(' · '),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Sonraki',
                      onPressed: _i >= n - 1
                          ? null
                          : () => _pc.nextPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            ),
                      icon: const Icon(Icons.chevron_right_rounded),
                      color: Colors.white,
                      disabledColor: Colors.white24,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Video yönetimi: uzun basınca sabitle / sil menüsü.
Future<void> showVideoActions(
  BuildContext context,
  VideoItem v, {
  bool canPin = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF16213A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Text(
              v.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          if (canPin)
            ListTile(
              leading: Icon(
                v.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                color: const Color(0xFFFBBF24),
              ),
              title: Text(
                v.pinned ? 'Sabitlemeyi kaldır' : 'En üstte sabitle',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
          if (v.matchId != null)
            ListTile(
              leading: const Icon(
                Icons.person_add_alt_1_rounded,
                color: Colors.white70,
              ),
              title: const Text(
                'Kişileri etiketle',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, 'tag'),
            ),
          if (v.matchId != null)
            ListTile(
              leading: const Icon(
                Icons.swap_horiz_rounded,
                color: Colors.white70,
              ),
              title: Text(
                'Türünü değiştir (şu an: ${v.kind.label})',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, 'kind'),
            ),
          ListTile(
            leading: const Icon(Icons.image_outlined, color: Colors.white70),
            title: Text(
              v.coverUrl.isEmpty
                  ? 'Kapak fotoğrafı seç'
                  : 'Kapak fotoğrafını değiştir',
              style: const TextStyle(color: Colors.white),
            ),
            onTap: () => Navigator.pop(ctx, 'cover'),
          ),
          if (v.coverUrl.isNotEmpty)
            ListTile(
              leading: const Icon(
                Icons.hide_image_outlined,
                color: Colors.white70,
              ),
              title: const Text(
                'Kapağı kaldır',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, 'uncover'),
            ),
          ListTile(
            leading: const Icon(
              Icons.delete_outline_rounded,
              color: kAdminDanger,
            ),
            title: const Text(
              'Videoyu kaldır',
              style: TextStyle(color: kAdminDanger),
            ),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  try {
    if (action == 'pin') {
      await VideoService.setPinned(v.id, !v.pinned);
    } else if (action == 'cover') {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final url = await uploadVideoCover(picked);
      await VideoService.setCover(v.id, url);
      messenger.showSnackBar(
        const SnackBar(content: Text('Kapak fotoğrafı güncellendi.')),
      );
    } else if (action == 'tag') {
      final cands = await VideoService.tagCandidates(v.matchId!);
      final cur = await VideoService.taggedIds(v.id);
      if (!context.mounted) return;
      final picked = await showDialog<Set<String>>(
        context: context,
        builder: (_) => _TagDialog(
          candidates: [
            for (final c in cands)
              if (v.teamId == null || c.teamId == v.teamId) c,
          ],
          selected: cur,
        ),
      );
      if (picked == null) return;
      await VideoService.setPlayers(v.id, picked);
      messenger.showSnackBar(
        const SnackBar(content: Text('Etiketler kaydedildi.')),
      );
    } else if (action == 'kind') {
      final picked = await showAdminOptionPicker<VideoKind>(
        context: context,
        title: 'Röportaj Türü',
        items: VideoKind.interviews,
        selected: v.kind,
        labelBuilder: (k) => k.label,
      );
      if (picked == null || picked == v.kind) return;
      await VideoService.setKind(v.id, picked);
      messenger.showSnackBar(
        SnackBar(content: Text('Tür "${picked.label}" olarak değiştirildi.')),
      );
    } else if (action == 'uncover') {
      await VideoService.setCover(v.id, null);
    } else {
      final yes = await showAdminConfirmDialog(
        context: context,
        title: 'Videoyu Kaldır',
        message:
            'Video uygulamadan kaldırılsın mı? Instagram\'daki gönderi '
            'silinmez.',
        confirmLabel: 'KALDIR',
        destructive: true,
      );
      if (!yes) return;
      await VideoService.delete(v.id);
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(VideoService.errorText(e))));
  }
}

/// Kapak fotoğrafını yükler (news/videos klasörü) ve linkini döner.
Future<String> uploadVideoCover(XFile file) async {
  final url = (await SupabaseImageUploadService().uploadImage(
    file,
    folder: MediaFolder.news,
    subfolder: 'videos',
  ))?.trim();
  if ((url ?? '').isEmpty) {
    throw Exception('Kapak fotoğrafı yüklenemedi, lütfen tekrar deneyin.');
  }
  return url!;
}

/// Maçın iki takımı (röportaj ekleme penceresinde takım seçimi).
class VideoMatchRef {
  const VideoMatchRef({
    required this.id,
    required this.homeId,
    required this.homeName,
    required this.awayId,
    required this.awayName,
  });
  final String id;
  final String homeId;
  final String homeName;
  final String awayId;
  final String awayName;
}

/// Video ekleme penceresi. [match] verilirse maç röportajı (tür + takım),
/// verilmezse turnuva videosu (başlık, sabitle, haber olarak yayınla).
Future<bool> showAddVideoDialog(
  BuildContext context, {
  String? seasonId,
  VideoMatchRef? match,
  VideoKind? initialKind,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _AddVideoDialog(
      seasonId: seasonId,
      match: match,
      initialKind: initialKind,
    ),
  );
  return ok == true;
}

class _AddVideoDialog extends StatefulWidget {
  const _AddVideoDialog({this.seasonId, this.match, this.initialKind});
  final String? seasonId;
  final VideoMatchRef? match;
  final VideoKind? initialKind;

  @override
  State<_AddVideoDialog> createState() => _AddVideoDialogState();
}

class _AddVideoDialogState extends State<_AddVideoDialog> {
  final _url = TextEditingController();
  final _title = TextEditingController();
  late VideoKind _kind =
      widget.initialKind ??
      (widget.match == null ? VideoKind.tournament : VideoKind.post);

  /// Takım: 'home' | 'away' | null (genel).
  String? _side = 'home';
  bool _pinned = false;
  bool _asNews = true;
  bool _busy = false;

  /// Seçilen kapak fotoğrafı (isteğe bağlı).
  XFile? _cover;

  /// Röportaj yapılan futbolcular (en çok 3).
  final _tags = <String>{};
  late final Future<List<VideoTagCandidate>>? _cands = widget.match == null
      ? null
      : VideoService.tagCandidates(
          widget.match!.id,
        ).catchError((_) => <VideoTagCandidate>[]);

  String? get _teamId {
    final m = widget.match;
    if (m == null) return null;
    return _side == 'home'
        ? m.homeId
        : _side == 'away'
        ? m.awayId
        : null;
  }

  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    try {
      final d = await Clipboard.getData(Clipboard.kTextPlain);
      final t = (d?.text ?? '').trim();
      if (t.isNotEmpty) setState(() => _url.text = t);
    } catch (_) {}
  }

  Future<void> _submit() async {
    final url = _url.text.trim();
    if (url.contains('/stories/')) {
      setState(
        () => _error =
            'Hikâyeler eklenemez; gönderi ya da Reels bağlantısı kullanın.',
      );
      return;
    }
    if (!isInstagramPostUrl(url)) {
      setState(
        () => _error = 'Instagram gönderisi ya da Reels bağlantısı yapıştırın.',
      );
      return;
    }
    final m = widget.match;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cover = _cover == null ? null : await uploadVideoCover(_cover!);
      final id = await VideoService.add(
        seasonId: widget.seasonId,
        matchId: m?.id,
        kind: _kind,
        teamId: m == null
            ? null
            : _side == 'home'
            ? m.homeId
            : _side == 'away'
            ? m.awayId
            : null,
        title: m == null ? _title.text.trim() : null,
        url: url,
        pinned: m == null && _pinned,
        asNews: m == null && _asNews,
        coverUrl: cover,
      );
      if (_tags.isNotEmpty && id.isNotEmpty) {
        await VideoService.setPlayers(id, _tags);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = VideoService.errorText(e);
        });
      }
    }
  }

  Widget _chips<T>(List<(T, String)> items, T selected, ValueChanged<T> on) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (v, label) in items)
          ChoiceChip(
            label: Text(label),
            selected: v == selected,
            onSelected: (_) => setState(() => on(v)),
            showCheckmark: false,
            labelStyle: TextStyle(
              color: v == selected ? Colors.white : Colors.white70,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
            backgroundColor: const Color(0xFF131D33),
            selectedColor: kAdminAccent.withValues(alpha: 0.35),
            side: BorderSide(
              color: v == selected ? kAdminAccent : const Color(0xFF263248),
            ),
          ),
      ],
    );
  }

  Widget _check(String label, bool value, ValueChanged<bool> on) {
    return InkWell(
      onTap: () => setState(() => on(!value)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              value
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: value ? kAdminAccent : Colors.white54,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    const labelStyle = TextStyle(
      color: Colors.white54,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1,
    );
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: AdminDialogCloseOverlay(
        onClose: () => Navigator.pop(context, false),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: adminDialogDecoration(),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminDialogHeader(
                  icon: Icons.video_library_rounded,
                  title: m == null ? 'Turnuva Videosu Ekle' : 'Röportaj Ekle',
                  subtitle: m == null ? null : '${m.homeName} – ${m.awayName}',
                ),
                const SizedBox(height: 16),
                if (m != null) ...[
                  const Text('TÜR', style: labelStyle),
                  const SizedBox(height: 6),
                  _chips<VideoKind>(
                    [for (final k in VideoKind.interviews) (k, k.label)],
                    _kind,
                    (v) => _kind = v,
                  ),
                  const SizedBox(height: 14),
                  const Text('TAKIM', style: labelStyle),
                  const SizedBox(height: 6),
                  _chips<String?>(
                    [
                      ('home', m.homeName),
                      ('away', m.awayName),
                      (null, 'Genel'),
                    ],
                    _side,
                    (v) {
                      _side = v;
                      _tags.clear();
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'RÖPORTAJ YAPILAN (İSTEĞE BAĞLI, EN ÇOK 3)',
                    style: labelStyle,
                  ),
                  const SizedBox(height: 6),
                  FutureBuilder<List<VideoTagCandidate>>(
                    future: _cands,
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(8),
                          child: LinearProgressIndicator(color: kAdminAccent),
                        );
                      }
                      final team = _teamId;
                      return VideoTagPicker(
                        candidates: [
                          for (final c in snap.data!)
                            if (team == null || c.teamId == team) c,
                        ],
                        selected: _tags,
                        onChanged: () => setState(() {}),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                ] else ...[
                  const Text('BAŞLIK', style: labelStyle),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: _inputDecoration(
                      'Ör. 2026 Sezonu açılış töreni',
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                const Text('INSTAGRAM BAĞLANTISI', style: labelStyle),
                const SizedBox(height: 6),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: _inputDecoration('instagram.com/reel/…').copyWith(
                    suffixIcon: TextButton(
                      onPressed: _paste,
                      child: const Text(
                        'Yapıştır',
                        style: TextStyle(
                          color: kAdminAccent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Gönderi ya da Reels bağlantısı. Hikâyeler eklenemez.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 14),
                const Text('KAPAK FOTOĞRAFI (İSTEĞE BAĞLI)', style: labelStyle),
                const SizedBox(height: 6),
                _coverPicker(m == null),
                if (m == null) ...[
                  const SizedBox(height: 10),
                  _check('En üstte sabitle', _pinned, (v) => _pinned = v),
                  _check(
                    'Haber olarak da yayınla',
                    _asNews,
                    (v) => _asNews = v,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: kAdminDanger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                AdminPrimaryButton(
                  label: 'EKLE',
                  busy: _busy,
                  onPressed: _busy ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickCover() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null && mounted) setState(() => _cover = picked);
  }

  Widget _coverPicker(bool tournament) {
    final c = _cover;
    return Row(
      children: [
        InkWell(
          onTap: _busy ? null : _pickCover,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 64,
            height: 80,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF0B1220),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF263248)),
              image: c == null
                  ? null
                  : DecorationImage(
                      image: pickedImageProvider(c),
                      fit: BoxFit.cover,
                    ),
            ),
            child: c == null
                ? const Icon(
                    Icons.add_photo_alternate_outlined,
                    color: Colors.white54,
                  )
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c == null
                    ? (tournament
                          ? 'Seçilmezse turnuva logosu gösterilir.'
                          : 'Seçilmezse takım arması gösterilir.')
                    : 'Kapak seçildi.',
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: _busy ? null : _pickCover,
                    child: Text(
                      c == null ? 'Fotoğraf seç' : 'Değiştir',
                      style: const TextStyle(
                        color: kAdminAccent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (c != null)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _cover = null),
                      child: const Text(
                        'Kaldır',
                        style: TextStyle(
                          color: Colors.white54,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white38),
    filled: true,
    fillColor: const Color(0xFF0B1220),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF263248)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kAdminAccent, width: 1.5),
    ),
  );
}

/// Menüdeki Videolar simgesi: seçili turnuvanın güncel sezonundaki video
/// sayısı (yoksa simge yalnız yetkiliye görünür).
class VideosShortcut {
  VideosShortcut._();

  static final count = ValueNotifier<int>(0);
  static String? _seasonId;
  static bool _listening = false;

  static Future<void> sync(String? seasonId) async {
    if (!_listening) {
      _listening = true;
      VideoService.changed.addListener(() => _load(_seasonId));
    }
    if (seasonId == _seasonId) return;
    _seasonId = seasonId;
    count.value = 0;
    await _load(seasonId);
  }

  static Future<void> _load(String? seasonId) async {
    if (seasonId == null) return;
    try {
      final n = await Supabase.instance.client
          .from('videos')
          .count()
          .eq('season_id', seasonId);
      if (_seasonId == seasonId) count.value = n;
    } catch (_) {}
  }
}

/// Futbolcu seçimi (en çok 3): seçilenler çip olarak; altında arama alanı
/// (yazınca eşleşenler listelenir) ve yanında "Seç" düğmesi (tüm kadro
/// listesi açılır).
class VideoTagPicker extends StatefulWidget {
  const VideoTagPicker({
    super.key,
    required this.candidates,
    required this.selected,
    required this.onChanged,
  });

  final List<VideoTagCandidate> candidates;

  /// Yerinde değiştirilir.
  final Set<String> selected;
  final VoidCallback onChanged;

  static const max = 3;

  @override
  State<VideoTagPicker> createState() => _VideoTagPickerState();
}

class _VideoTagPickerState extends State<VideoTagPicker> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  bool get _full => widget.selected.length >= VideoTagPicker.max;

  void _toggle(String id) {
    final s = widget.selected;
    if (s.contains(id)) {
      s.remove(id);
    } else if (!_full) {
      s.add(id);
    }
    widget.onChanged();
    setState(() {});
  }

  Future<void> _openList() async {
    FocusScope.of(context).unfocus();
    final picked = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _TagListDialog(
        candidates: widget.candidates,
        selected: widget.selected,
      ),
    );
    if (picked == null) return;
    widget.selected
      ..clear()
      ..addAll(picked);
    widget.onChanged();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.candidates.isEmpty) {
      return const Text(
        'Kadroda futbolcu bulunamadı.',
        style: TextStyle(color: Colors.white54, fontSize: 12.5),
      );
    }
    final byId = {for (final c in widget.candidates) c.tag.id: c};
    final chosen = [
      for (final id in widget.selected)
        if (byId[id] != null) byId[id]!,
    ];
    final q = StringUtils.normalizeTrKey(_q.text);
    final hits = q.isEmpty
        ? const <VideoTagCandidate>[]
        : [
            for (final c in widget.candidates)
              if (!widget.selected.contains(c.tag.id) &&
                  StringUtils.normalizeTrKey(c.tag.name).contains(q))
                c,
          ].take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (chosen.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in chosen)
                InputChip(
                  label: Text(c.tag.name),
                  avatar: _TagAvatar(photo: c.tag.photo, size: 22),
                  onDeleted: () => _toggle(c.tag.id),
                  deleteIconColor: Colors.white70,
                  labelStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                  backgroundColor: kAdminAccent.withValues(alpha: 0.25),
                  side: const BorderSide(color: kAdminAccent),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _q,
                enabled: !_full,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _full ? 'En çok 3 kişi seçildi' : 'İsim yazın…',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Colors.white38,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF0B1220),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 11,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF263248)),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF263248)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: kAdminAccent,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _openList,
              icon: const Icon(Icons.list_rounded, size: 18),
              label: const Text('Seç'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kAdminAccent,
                side: const BorderSide(color: kAdminAccent),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        if (q.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1220),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF263248)),
            ),
            child: hits.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Eşleşen futbolcu yok.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : Column(
                    children: [
                      for (final c in hits)
                        _TagRow(
                          c: c,
                          selected: false,
                          onTap: () {
                            _q.clear();
                            _toggle(c.tag.id);
                          },
                        ),
                    ],
                  ),
          ),
      ],
    );
  }
}

class _TagAvatar extends StatelessWidget {
  const _TagAvatar({required this.photo, this.size = 30});
  final String photo;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: photo.isEmpty
          ? SizedBox(
              width: size,
              height: size,
              child: ColoredBox(
                color: const Color(0xFF334155),
                child: Icon(
                  Icons.person_rounded,
                  size: size * 0.7,
                  color: Colors.white54,
                ),
              ),
            )
          : WebSafeImage(
              url: photo,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
    );
  }
}

/// Listede tek futbolcu satırı: fotoğraf, ad, takım; sağda seçim kutusu.
class _TagRow extends StatelessWidget {
  const _TagRow({required this.c, required this.selected, required this.onTap});
  final VideoTagCandidate c;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            _TagAvatar(photo: c.tag.photo),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.tag.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onTap == null ? Colors.white38 : Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    c.teamName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: selected ? kAdminAccent : Colors.white38,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Seç": tüm kadro, aramalı liste; en çok 3 işaretlenir.
class _TagListDialog extends StatefulWidget {
  const _TagListDialog({required this.candidates, required this.selected});
  final List<VideoTagCandidate> candidates;
  final Set<String> selected;

  @override
  State<_TagListDialog> createState() => _TagListDialogState();
}

class _TagListDialogState extends State<_TagListDialog> {
  late final _sel = {...widget.selected};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = StringUtils.normalizeTrKey(_q);
    final list = [
      for (final c in widget.candidates)
        if (q.isEmpty || StringUtils.normalizeTrKey(c.tag.name).contains(q)) c,
    ];
    final full = _sel.length >= VideoTagPicker.max;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: adminDialogDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Röportaj yapılan · ${_sel.length}/${VideoTagPicker.max}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Kapat',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
            TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _q = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Ara',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Colors.white38,
                  size: 20,
                ),
                filled: true,
                fillColor: const Color(0xFF0B1220),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final c = list[i];
                  final on = _sel.contains(c.tag.id);
                  return _TagRow(
                    c: c,
                    selected: on,
                    onTap: on || !full
                        ? () => setState(
                            () =>
                                on ? _sel.remove(c.tag.id) : _sel.add(c.tag.id),
                          )
                        : null,
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            AdminPrimaryButton(
              label: 'TAMAM',
              onPressed: () => Navigator.pop(context, _sel),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagDialog extends StatefulWidget {
  const _TagDialog({required this.candidates, required this.selected});
  final List<VideoTagCandidate> candidates;
  final Set<String> selected;

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  late final _sel = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: AdminDialogCloseOverlay(
        onClose: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: adminDialogDecoration(),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AdminDialogHeader(
                  icon: Icons.person_add_alt_1_rounded,
                  title: 'Kişileri Etiketle',
                  subtitle: 'Röportaj yapılan futbolcular (en çok 3)',
                ),
                const SizedBox(height: 16),
                VideoTagPicker(
                  candidates: widget.candidates,
                  selected: _sel,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 18),
                AdminPrimaryButton(
                  label: 'KAYDET',
                  onPressed: () => Navigator.pop(context, _sel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Etiketli futbolcular: fotoğraf + ad; dokununca profili.
class VideoTagsRow extends StatelessWidget {
  const VideoTagsRow({super.key, required this.tags, required this.onTap});
  final List<VideoTag> tags;
  final ValueChanged<VideoTag> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final t in tags)
          InkWell(
            onTap: () => onTap(t),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipOval(
                    child: t.photo.isEmpty
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: ColoredBox(
                              color: Color(0xFF334155),
                              child: Icon(
                                Icons.person_rounded,
                                size: 16,
                                color: Colors.white54,
                              ),
                            ),
                          )
                        : WebSafeImage(
                            url: t.photo,
                            width: 22,
                            height: 22,
                            fit: BoxFit.cover,
                          ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    t.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
