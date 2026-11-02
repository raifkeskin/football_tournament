import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../services/app_session.dart';
import '../services/app_settings.dart';
import 'app_name_band.dart';
import 'mp4_clip_page.dart';

const youtubePlayerOrigin = 'https://ligmasasi.com';

/// Oynatıcı tam ekrana geçince ekran yataya döner (sistem çubukları gizli),
/// çıkınca telefonun kendi yönüne bırakılır. Web'de bunu index.html'deki
/// `fullscreenchange` dinleyicisi yapar.
void landscapeOnFullscreen(
  YoutubePlayerController controller, {
  ValueChanged<bool>? onChanged,
}) {
  if (kIsWeb) return;
  controller.setFullScreenListener((full) {
    onChanged?.call(full);
    if (full) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      // Yönler yalnız serbest bırakılırsa iOS (ve yatay tutulan Android)
      // ekranı yatayda bırakır: bar ve Kapat düğmesi gelmez, tam ekrandan
      // çıkılmamış görünür. Çıkışta dikeye döndürülür; sayfa kapanınca
      // resetPlayerOrientation serbest bırakır.
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  });
}

/// Tam ekrandan çıkışta ya da oynatıcı kapanınca yönlendirmeyi geri verir.
void resetPlayerOrientation() {
  if (kIsWeb) return;
  SystemChrome.setPreferredOrientations(const []);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
}

/// YouTube linkinden 11 karakterlik video kimliği (watch, youtu.be, embed,
/// shorts, live); YouTube'a ait değilse null.
String? youtubeVideoId(String url) {
  final u = url.trim();
  if (RegExp(r'^[_\-a-zA-Z0-9]{11}$').hasMatch(u)) return u;
  final normalized = u.contains('://') ? u : 'https://$u';
  final uri = Uri.tryParse(normalized);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  String? id;
  if (host.endsWith('youtu.be')) {
    id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  } else if (host.contains('youtube.com') ||
      host.contains('youtube-nocookie.com')) {
    id = uri.queryParameters['v'];
    final seg = uri.pathSegments;
    if (id == null &&
        seg.length >= 2 &&
        const {'embed', 'shorts', 'live', 'v'}.contains(seg.first)) {
      id = seg[1];
    }
  }
  if (id == null || !RegExp(r'^[_\-a-zA-Z0-9]{11}$').hasMatch(id)) {
    return null;
  }
  return id;
}

/// Yayını uygulamanın içinde, tam ekran oynatır (kullanıcı YouTube'a
/// gitmeden izler). Link YouTube'a ait değilse dışarıda açılır.
/// [fullscreen]: telefonda doğrudan yatay tam ekranda başlar.
Future<void> openYoutubeInApp(
  BuildContext context,
  String url, {
  bool fullscreen = false,
}) async {
  final id = youtubeVideoId(url);
  if (id == null) {
    final uri = Uri.tryParse(url.trim());
    final ok =
        uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Yayın linki açılamadı.')));
    }
    return;
  }
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'YoutubePlayerPage'),
      fullscreenDialog: true,
      builder: (_) =>
          _YoutubePlayerPage(videoId: id, url: url, fullscreen: fullscreen),
    ),
  );
}

class _YoutubePlayerPage extends StatefulWidget {
  const _YoutubePlayerPage({
    required this.videoId,
    required this.url,
    this.fullscreen = false,
  });

  final String videoId;
  final String url;
  final bool fullscreen;

  @override
  State<_YoutubePlayerPage> createState() => _YoutubePlayerPageState();
}

class _YoutubePlayerPageState extends State<_YoutubePlayerPage> {
  late final _controller = YoutubePlayerController.fromVideoId(
    videoId: widget.videoId,
    autoPlay: true,
    params: const YoutubePlayerParams(
      // Android'de YouTube'un kendi tam ekranı WebView'da boş ekran
      // bırakıyor; telefonda tam ekran YoutubePlayerFrame düğmesiyle.
      showFullscreenButton: kIsWeb,
      strictRelatedVideos: true,
      origin: youtubePlayerOrigin,
    ),
  );

  @override
  void initState() {
    super.initState();
    // Çerçevenin tam ekran dinleyicisi kurulduktan sonra.
    if (widget.fullscreen && !kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.enterFullScreen();
      });
    }
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  // YouTube'a geçiş videonun içindeki YouTube logosundan.
  @override
  Widget build(BuildContext context) {
    return YoutubePlayerFrame(
      controller: _controller,
      title: 'Maç Yayını',
      youtubeUrl: widget.url,
    );
  }
}

/// YouTube yayınının yalnızca [startSec]–[endSec] aralığını tam ekran
/// oynatır (YZ gol kesitleri). Video kesilmez; oynatıcı aralıkta başlar ve
/// durur.
Future<void> openYoutubeClip(
  BuildContext context, {
  required String videoId,
  required int startSec,
  required int endSec,
  String title = 'Gol',
  String? clipUrl,
  String? storyUrl,
}) {
  // Gol kesitinin MP4 hâli (Mac'te üretilir): YouTube yerine dosya oynar,
  // hikâye MP4'ü Instagram'da paylaşılabilir. Yeni özellik: önce yalnız
  // admin.
  if ((clipUrl ?? '').isNotEmpty) {
    var allowed = AppSettings.goalClipMp4Enabled.value;
    if (!allowed) {
      try {
        allowed = AppSession.of(context).value.isAdmin;
      } catch (_) {}
    }
    if (allowed) {
      return Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'Mp4ClipPage'),
          fullscreenDialog: true,
          builder: (_) =>
              Mp4ClipPage(url: clipUrl!, title: title, storyUrl: storyUrl),
        ),
      );
    }
  }
  // Yayıncının teslim ettiği kesit: video_id alanında kendi depomuzdaki MP4
  // adresi (http…) durur; YouTube yerine yerel oynatıcı.
  if (videoId.startsWith('http')) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'Mp4ClipPage'),
        fullscreenDialog: true,
        builder: (_) => Mp4ClipPage(
          url: videoId,
          title: title,
          startSec: startSec,
          endSec: endSec,
        ),
      ),
    );
  }
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'YoutubeClipPage'),
      fullscreenDialog: true,
      builder: (_) => _YoutubeClipPage(
        videoId: videoId,
        startSec: startSec,
        endSec: endSec,
        title: title,
      ),
    ),
  );
}

class _YoutubeClipPage extends StatefulWidget {
  const _YoutubeClipPage({
    required this.videoId,
    required this.startSec,
    required this.endSec,
    required this.title,
  });

  final String videoId;
  final int startSec;
  final int endSec;
  final String title;

  @override
  State<_YoutubeClipPage> createState() => _YoutubeClipPageState();
}

class _YoutubeClipPageState extends State<_YoutubeClipPage> {
  // Bitiş YouTube'a bırakılmaz (endSeconds yok): video sonunda YouTube öneri
  // şeridi gösterir ve gömülü oynatıcıda kapatılamaz. Bitiş saniyesinde
  // video duraklatılır, üstü "Tekrar İzle" katmanıyla örtülür.
  //
  // YouTube oynatma başlarken 2-3 sn başlığı ve ortada ‖ işaretini gösterir
  // (gömülü oynatıcıda kapatılamaz). Kesit [_lead] sn önceden başlar ve bu
  // süre siyah kapakla örtülür; kapak kalkınca kesitin başı ekrandadır.
  static const _lead = 3;
  static const _coverFor = Duration(milliseconds: 2700);

  late final int _from = math.max(0, widget.startSec - _lead);

  late final _controller = YoutubePlayerController.fromVideoId(
    videoId: widget.videoId,
    autoPlay: true,
    startSeconds: _from.toDouble(),
    params: const YoutubePlayerParams(
      // Android'de YouTube'un kendi tam ekranı WebView'da boş ekran
      // bırakıyor; telefonda tam ekran YoutubePlayerFrame düğmesiyle.
      showFullscreenButton: kIsWeb,
      // YouTube'un çizelgesi tüm yayını (2 saat) gösterip kesitin dışına
      // atlatıyor; yerine yalnız kesiti gösteren _ClipControls.
      showControls: false,
      strictRelatedVideos: true,
      origin: youtubePlayerOrigin,
    ),
  );

  StreamSubscription<YoutubeVideoState>? _position;
  StreamSubscription<YoutubePlayerValue>? _state;
  bool _ended = false;
  bool _covered = true;
  Timer? _uncover;

  @override
  void initState() {
    super.initState();
    final endMs = widget.endSec * 1000 - 150;
    _position = _controller.videoStateStream.listen((v) {
      if (!_ended && v.position.inMilliseconds >= endMs) _finish();
    });
    _state = _controller.stream.listen((v) {
      if (!_ended && v.playerState == PlayerState.ended) _finish();
      // Oynatma başlayınca YouTube'un açılış yazıları sönene kadar kapak.
      if (_covered &&
          _uncover == null &&
          v.playerState == PlayerState.playing) {
        _uncover = Timer(_coverFor, _removeCover);
      }
    });
    // Oynatma hiç başlamazsa (otomatik oynatma engeli) kapak takılı kalmasın.
    Timer(const Duration(seconds: 8), _removeCover);
  }

  void _removeCover() {
    if (mounted && _covered) setState(() => _covered = false);
  }

  void _finish() {
    _controller.pauseVideo();
    if (mounted) setState(() => _ended = true);
  }

  @override
  void dispose() {
    _position?.cancel();
    _state?.cancel();
    _uncover?.cancel();
    _controller.close();
    super.dispose();
  }

  Future<void> _replay() async {
    setState(() => _ended = false);
    await _controller.seekTo(
      seconds: widget.startSec.toDouble(),
      allowSeekAhead: true,
    );
    await _controller.playVideo();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerFrame(
      controller: _controller,
      title: widget.title,
      controls: _ClipControls(
        controller: _controller,
        startSec: widget.startSec,
        endSec: widget.endSec,
        ended: _ended,
        onReplay: _replay,
      ),
      actions: [
        IconButton(
          tooltip: 'Tekrar izle',
          onPressed: _replay,
          icon: const Icon(Icons.replay_rounded),
        ),
      ],
      overlay: _ended
          ? ColoredBox(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: _replay,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('Tekrar İzle'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white60,
                      ),
                      child: const Text('Kapat'),
                    ),
                  ],
                ),
              ),
            )
          : _covered
          ? const ColoredBox(
              color: Colors.black,
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white54,
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

/// Oynatıcı sayfası iskeleti. Dikeyde üst bar + ortada 16:9 oynatıcı (altta
/// isteğe bağlı [footer]); tam ekran düğmesine basılınca ya da telefon yatay
/// tutulunca bar ve sistem çubukları gizlenir, oynatıcı ekranı doldurur.
/// Ağaç yapısı değişmez (yalnız bar gizlenir), geçişte video yeniden
/// yüklenmez. [overlay] oynatıcının üstüne çizilir (ör. kesit sonu).
class YoutubePlayerFrame extends StatefulWidget {
  const YoutubePlayerFrame({
    super.key,
    required this.controller,
    required this.title,
    this.actions = const [],
    this.overlay,
    this.footer,
    this.youtubeUrl,
    this.controls,
  });

  /// YouTube düğmeleri kapalıyken oynatıcının üstüne çizilen kendi
  /// düğmelerimiz (tam ekranda da görünür).
  final Widget? controls;

  /// Video uygulama içinde oynatılamıyorsa (kanal gömmeye izin vermiyor,
  /// video yok) ortada açıklama ve "YouTube'da izle" düğmesi çıkar.
  final String? youtubeUrl;

  final YoutubePlayerController controller;
  final String title;
  final List<Widget> actions;
  final Widget? overlay;
  final Widget? footer;

  @override
  State<YoutubePlayerFrame> createState() => _YoutubePlayerFrameState();
}

class _YoutubePlayerFrameState extends State<YoutubePlayerFrame> {
  bool _full = false;

  /// Oynatıcı hatası (gömme izni yok, video bulunamadı).
  YoutubeError _error = YoutubeError.none;
  StreamSubscription<YoutubePlayerValue>? _errorSub;

  /// Oynatıcı her zaman hata bildirmiyor (yalnız kapak görseli kalıyor):
  /// açılırken YouTube'a videonun gömülebilir olup olmadığı sorulur.
  Future<void> _checkEmbeddable() async {
    final url = (widget.youtubeUrl ?? '').trim();
    if (url.isEmpty) return;
    try {
      final res = await http
          .get(
            Uri.https('www.youtube.com', '/oembed', {
              'url': url,
              'format': 'json',
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (!mounted || _error != YoutubeError.none) return;
      if (res.statusCode == 401 || res.statusCode == 403) {
        setState(() => _error = YoutubeError.notEmbeddable);
      } else if (res.statusCode == 404) {
        setState(() => _error = YoutubeError.videoNotFound);
      }
    } catch (_) {
      // Sorulamazsa oynatıcının kendi hatası beklenir.
    }
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse((widget.youtubeUrl ?? '').trim());
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('YouTube açılamadı.')));
    }
  }

  bool? _immersive;

  /// Tam ekranda uygulamanın ortak (turnuva) bandı gizlenir.
  Route<dynamic>? _route;
  bool? _bandHidden;

  void _syncBand(bool fill) {
    final route = ModalRoute.of(context);
    if (route == null || (_bandHidden == fill && _route == route)) return;
    _route = route;
    _bandHidden = fill;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LeagueSwitchScope.setBandHidden(route, fill);
    });
  }

  @override
  void initState() {
    super.initState();
    _errorSub = widget.controller.stream.listen((v) {
      if (v.error != _error && mounted) setState(() => _error = v.error);
    });
    _checkEmbeddable();
    landscapeOnFullscreen(
      widget.controller,
      onChanged: (full) {
        if (mounted) setState(() => _full = full);
      },
    );
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    resetPlayerOrientation();
    LeagueSwitchScope.setBandHidden(_route, false);
    super.dispose();
  }

  /// Telefon kendiliğinden yataya dönünce de sistem çubukları gizlenir.
  void _syncImmersive(bool fill) {
    if (kIsWeb || _immersive == fill) return;
    _immersive = fill;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(
        fill ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final fill = _full || landscape;
    _syncImmersive(fill);
    _syncBand(fill);
    // Tam ekrandayken geri tuşu önce tam ekrandan çıkarır.
    return PopScope(
      canPop: !_full,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _full) widget.controller.exitFullScreen();
      },
      child: _scaffold(context, fill),
    );
  }

  /// Video gömülerek oynatılamıyor: açıklama ve YouTube'a geçiş.
  Widget _errorCover() {
    final embed = const {
      YoutubeError.notEmbeddable,
      YoutubeError.sameAsNotEmbeddable,
    }.contains(_error);
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.82),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                embed
                    ? 'Yayının sahibi bu videonun uygulama içinde '
                          'oynatılmasına izin vermiyor.'
                    : 'Video şu an burada oynatılamıyor.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, height: 1.35),
              ),
              if ((widget.youtubeUrl ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF0000),
                  ),
                  onPressed: _openExternally,
                  icon: const Icon(Icons.smart_display_rounded),
                  label: const Text(
                    "YouTube'da izle",
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _scaffold(BuildContext context, bool fill) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: fill
          ? null
          : AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              leading: IconButton(
                tooltip: 'Kapat',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(widget.title, style: const TextStyle(fontSize: 16)),
              actions: [
                ...widget.actions,
                // Telefonda YouTube'un tam ekran düğmesi gizli; yerine bu.
                if (!kIsWeb)
                  IconButton(
                    tooltip: 'Tam ekran',
                    icon: const Icon(Icons.fullscreen_rounded),
                    onPressed: () => widget.controller.enterFullScreen(),
                  ),
              ],
            ),
      body: SafeArea(
        top: !fill,
        bottom: !fill,
        left: !fill,
        right: !fill,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          YoutubePlayer(
                            controller: widget.controller,
                            // Tam ekranda oynatıcı sayfanın üstündeki ayrı
                            // katmanda çizilir; çıkış düğmesi de oraya.
                            controlsBuilder: (context, isFullscreen) => Stack(
                              fit: StackFit.expand,
                              children: [
                                if (widget.controls != null) widget.controls!,
                                if (isFullscreen)
                                  _FullscreenExit(
                                    onExit: widget.controller.exitFullScreen,
                                  ),
                              ],
                            ),
                          ),
                          if (widget.overlay != null) widget.overlay!,
                          if (_error != YoutubeError.none) _errorCover(),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!fill && widget.footer != null) widget.footer!,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tam ekranda sol üstte "Kapat" düğmesi; girişte birkaç saniye nasıl
/// çıkılacağını söyleyen ipucu. Boş alanlar dokunuşu oynatıcıya bırakır.
class _FullscreenExit extends StatefulWidget {
  const _FullscreenExit({required this.onExit});

  final VoidCallback onExit;

  @override
  State<_FullscreenExit> createState() => _FullscreenExitState();
}

class _FullscreenExitState extends State<_FullscreenExit> {
  bool _hint = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _hint = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 14,
          left: 14,
          child: Material(
            color: Colors.black.withValues(alpha: 0.6),
            shape: const StadiumBorder(side: BorderSide(color: Colors.white38)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: widget.onExit,
              child: const Padding(
                padding: EdgeInsets.fromLTRB(10, 8, 14, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close_rounded, color: Colors.white, size: 22),
                    SizedBox(width: 6),
                    Text(
                      'Kapat',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 28,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _hint ? 1 : 0,
              duration: const Duration(milliseconds: 400),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Çıkmak için Kapat\'a basın ya da ekranı aşağı kaydırın',
                    style: TextStyle(color: Colors.white, fontSize: 13.5),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Gol kesitinin kendi düğmeleri: oynat/duraklat, yalnız kesit süresini
/// gösteren çubuk (kesit içinde ileri/geri sarılır) ve süre. Videoya
/// dokunmak oynatır/duraklatır; YouTube'a dokunuş gitmez.
class _ClipControls extends StatefulWidget {
  const _ClipControls({
    required this.controller,
    required this.startSec,
    required this.endSec,
    required this.ended,
    required this.onReplay,
  });

  final YoutubePlayerController controller;
  final int startSec;
  final int endSec;
  final bool ended;
  final VoidCallback onReplay;

  @override
  State<_ClipControls> createState() => _ClipControlsState();
}

class _ClipControlsState extends State<_ClipControls> {
  StreamSubscription<YoutubeVideoState>? _posSub;
  StreamSubscription<YoutubePlayerValue>? _stateSub;
  double _pos = 0;
  double? _drag;
  bool _playing = false;

  double get _len => (widget.endSec - widget.startSec).clamp(1, 36000) * 1.0;

  @override
  void initState() {
    super.initState();
    _posSub = widget.controller.videoStateStream.listen((v) {
      final p = (v.position.inMilliseconds / 1000 - widget.startSec).clamp(
        0.0,
        _len,
      );
      if (mounted && (p - _pos).abs() > 0.05) setState(() => _pos = p);
    });
    _stateSub = widget.controller.stream.listen((v) {
      final playing =
          v.playerState == PlayerState.playing ||
          v.playerState == PlayerState.buffering;
      if (mounted && playing != _playing) setState(() => _playing = playing);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (widget.ended) return widget.onReplay();
    _playing ? widget.controller.pauseVideo() : widget.controller.playVideo();
  }

  Future<void> _seek(double v) async {
    setState(() {
      _pos = v;
      _drag = null;
    });
    await widget.controller.seekTo(
      seconds: widget.startSec + v,
      allowSeekAhead: true,
    );
    if (!_playing) await widget.controller.playVideo();
  }

  static String _fmt(double s) {
    final t = s.round();
    return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final value = (_drag ?? _pos).clamp(0.0, _len);
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: const SizedBox.expand(),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xB3000000), Color(0x00000000)],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 12, 2),
              child: Row(
                children: [
                  IconButton(
                    tooltip: _playing ? 'Duraklat' : 'Oynat',
                    color: Colors.white,
                    onPressed: _toggle,
                    icon: Icon(
                      widget.ended
                          ? Icons.replay_rounded
                          : _playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white30,
                        thumbColor: Colors.white,
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                      ),
                      child: Slider(
                        value: value,
                        max: _len,
                        onChanged: (v) => setState(() => _drag = v),
                        onChangeEnd: _seek,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${_fmt(value)} / ${_fmt(_len)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
