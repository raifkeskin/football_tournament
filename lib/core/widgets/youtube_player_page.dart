import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'app_name_band.dart';

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
      resetPlayerOrientation();
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
Future<void> openYoutubeInApp(BuildContext context, String url) async {
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
      builder: (_) => _YoutubePlayerPage(videoId: id, url: url),
    ),
  );
}

class _YoutubePlayerPage extends StatefulWidget {
  const _YoutubePlayerPage({required this.videoId, required this.url});

  final String videoId;
  final String url;

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
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerFrame(
      controller: _controller,
      title: 'Maç Yayını',
      actions: [
        // Video gömülemiyorsa (kanal izin vermiyorsa) YouTube'da açılır.
        TextButton.icon(
          onPressed: () => launchUrl(
            Uri.parse(widget.url.trim()),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: const Text('YouTube'),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
        ),
      ],
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
}) {
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
  late final _controller = YoutubePlayerController.fromVideoId(
    videoId: widget.videoId,
    autoPlay: true,
    startSeconds: widget.startSec.toDouble(),
    params: const YoutubePlayerParams(
      // Android'de YouTube'un kendi tam ekranı WebView'da boş ekran
      // bırakıyor; telefonda tam ekran YoutubePlayerFrame düğmesiyle.
      showFullscreenButton: kIsWeb,
      strictRelatedVideos: true,
      origin: youtubePlayerOrigin,
    ),
  );

  StreamSubscription<YoutubeVideoState>? _position;
  StreamSubscription<YoutubePlayerValue>? _state;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    final endMs = widget.endSec * 1000 - 150;
    _position = _controller.videoStateStream.listen((v) {
      if (!_ended && v.position.inMilliseconds >= endMs) _finish();
    });
    _state = _controller.stream.listen((v) {
      if (!_ended && v.playerState == PlayerState.ended) _finish();
    });
  }

  void _finish() {
    _controller.pauseVideo();
    if (mounted) setState(() => _ended = true);
  }

  @override
  void dispose() {
    _position?.cancel();
    _state?.cancel();
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
  });

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
    landscapeOnFullscreen(
      widget.controller,
      onChanged: (full) {
        if (mounted) setState(() => _full = full);
      },
    );
  }

  @override
  void dispose() {
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
                            controlsBuilder: (context, isFullscreen) =>
                                isFullscreen
                                ? _FullscreenExit(
                                    onExit: widget.controller.exitFullScreen,
                                  )
                                : const SizedBox.shrink(),
                          ),
                          if (widget.overlay != null) widget.overlay!,
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
