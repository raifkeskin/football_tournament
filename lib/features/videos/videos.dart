import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/app_session.dart';
import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../../core/widgets/app_name_band.dart';
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
  });

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
    );
  }

  /// Haberdeki video listesinden (news.auto_data.videos).
  factory VideoItem.fromNews(Map v, VideoKind kind) => VideoItem(
    id: (v['id'] ?? '').toString(),
    url: (v['url'] ?? '').toString(),
    kind: kind,
    title: (v['title'] ?? '').toString().trim(),
    teamName: (v['team'] ?? '').toString().trim(),
    teamLogo: (v['team_logo'] ?? '').toString().trim(),
  );
}

class VideoService {
  VideoService._();

  static SupabaseClient get _db => Supabase.instance.client;

  /// Ekleme / silme sonrası listeler yeniden okunur.
  static final changed = ValueNotifier<int>(0);

  static const _select =
      'id, season_id, match_id, kind, title, url, pinned, created_at, '
      'teams(name, logo_url), '
      'matches(week, home:teams!home_team_id(name), away:teams!away_team_id(name))';

  static Future<List<VideoItem>> forSeason(String seasonId) async {
    final rows = await _db
        .from('videos')
        .select(_select)
        .eq('season_id', seasonId)
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

  static Future<void> add({
    String? seasonId,
    String? matchId,
    required VideoKind kind,
    String? teamId,
    String? title,
    required String url,
    bool pinned = false,
    bool asNews = false,
  }) async {
    await _db.rpc(
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
      },
    );
    changed.value++;
  }

  static Future<void> delete(String id) async {
    await _db.rpc('video_delete', params: {'p_id': id});
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
                  itemBuilder: (_, i) => InstagramEmbed(url: items[i].url),
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
      await VideoService.add(
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
      );
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
                    (v) => _side = v,
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
