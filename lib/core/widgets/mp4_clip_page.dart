import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../services/instagram_share.dart';
import '../services/whatsapp_share.dart';
import 'app_name_band.dart';
import 'youtube_player_page.dart' show resetPlayerOrientation;

/// Kendi depomuzdaki (yayıncının teslim ettiği) MP4 kesiti tam ekran
/// oynatır. [endSec] başlangıçtan büyükse o saniyede durur; değilse dosya
/// sonuna kadar. Bitince "Tekrar İzle". [storyUrl] varsa (gol kesitinin
/// 9:16 hâli) altta "Instagram hikâyesinde paylaş".
class Mp4ClipPage extends StatefulWidget {
  const Mp4ClipPage({
    super.key,
    required this.url,
    required this.title,
    this.startSec = 0,
    this.endSec = 0,
    this.storyUrl,
  });

  final String url;
  final String? storyUrl;
  final String title;
  final int startSec;
  final int endSec;

  @override
  State<Mp4ClipPage> createState() => _Mp4ClipPageState();
}

class _Mp4ClipPageState extends State<Mp4ClipPage> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(
    Uri.parse(widget.url),
  );
  bool _ready = false;
  bool _ended = false;
  String? _error;

  /// Tam ekran düğmesiyle yatay tam ekran (telefon yan çevrilince de).
  bool _full = false;
  bool? _immersive;
  Route<dynamic>? _route;
  bool? _bandHidden;

  void _setFull(bool full) {
    setState(() => _full = full);
    if (kIsWeb) return;
    SystemChrome.setPreferredOrientations(
      full
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          // Yalnız serbest bırakmak ekranı yatayda bırakır: önce dikeye.
          : const [DeviceOrientation.portraitUp],
    );
  }

  /// Tam ekranda sistem çubukları ve uygulamanın turnuva bandı gizlenir.
  void _syncFill(bool fill) {
    if (!kIsWeb && _immersive != fill) {
      _immersive = fill;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        SystemChrome.setEnabledSystemUIMode(
          fill ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        );
      });
    }
    final route = ModalRoute.of(context);
    if (route == null || (_bandHidden == fill && _route == route)) return;
    _route = route;
    _bandHidden = fill;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LeagueSwitchScope.setBandHidden(route, fill);
    });
  }

  /// Paylaşım sürerken hangi düğme ('ig' / 'wa').
  String? _sharing;
  late final Future<bool> _igAvailable = (widget.storyUrl ?? '').isEmpty
      ? Future.value(false)
      : InstagramShare.isAvailable();

  /// Hikâye MP4'ü (bir kez indirilir; iki düğme de aynı dosyayı paylaşır).
  Uint8List? _story;

  /// Hikâye MP4'ünü indirip Instagram hikâyesinde ya da WhatsApp'ta açar.
  Future<void> _share(String target) async {
    final messenger = ScaffoldMessenger.of(context);
    final origin = WhatsAppShare.originOf(context);
    setState(() => _sharing = target);
    if (_c.value.isPlaying) await _c.pause();
    try {
      var bytes = _story;
      if (bytes == null) {
        final r = await http.get(Uri.parse(widget.storyUrl!));
        if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
        bytes = _story = r.bodyBytes;
      }
      if (target == 'wa') {
        await WhatsAppShare.shareVideo(bytes, origin: origin);
      } else if (!await InstagramShare.shareVideo(bytes, story: true)) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Instagram açılamadı.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Video indirilemedi. Tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _sharing = null);
    }
  }

  Duration get _start => Duration(seconds: widget.startSec);
  Duration? get _end =>
      widget.endSec > widget.startSec ? Duration(seconds: widget.endSec) : null;

  @override
  void initState() {
    super.initState();
    _c.addListener(_tick);
    _c
        .initialize()
        .then((_) async {
          if (_start > Duration.zero) await _c.seekTo(_start);
          await _c.play();
          if (mounted) setState(() => _ready = true);
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = 'Video açılamadı.');
        });
  }

  void _tick() {
    if (!_ready || _ended) return;
    final v = _c.value;
    final end = _end;
    final atEnd =
        (end != null && v.position >= end) ||
        (v.duration > Duration.zero &&
            v.position >= v.duration &&
            !v.isPlaying);
    if (atEnd) {
      _c.pause();
      setState(() => _ended = true);
    } else {
      setState(() {});
    }
  }

  Future<void> _replay() async {
    setState(() => _ended = false);
    await _c.seekTo(_start);
    await _c.play();
  }

  @override
  void dispose() {
    _c.removeListener(_tick);
    _c.dispose();
    resetPlayerOrientation();
    LeagueSwitchScope.setBandHidden(_route, false);
    super.dispose();
  }

  /// Yatay tam ekran: yalnız video, sağ üstte küçült.
  Widget _fullScreen() => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _c.value.aspectRatio,
            child: GestureDetector(
              onTap: () => _c.value.isPlaying
                  ? _c.pause()
                  : _ended
                  ? _replay()
                  : _c.play(),
              child: VideoPlayer(_c),
            ),
          ),
        ),
        if (!_c.value.isPlaying)
          IgnorePointer(
            child: Center(
              child: Icon(
                _ended ? Icons.replay_rounded : Icons.play_circle_fill_rounded,
                size: 64,
                color: Colors.white70,
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: VideoProgressIndicator(
            _c,
            allowScrubbing: true,
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
            colors: const VideoProgressColors(
              playedColor: Color(0xFF10B981),
              bufferedColor: Colors.white24,
              backgroundColor: Colors.white12,
            ),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: IconButton.filledTonal(
            tooltip: 'Küçült',
            onPressed: () => _setFull(false),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.fullscreen_exit_rounded),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final fill = _ready && (_full || landscape);
    _syncFill(fill);
    // Tam ekrandayken geri tuşu önce tam ekrandan çıkarır.
    return PopScope(
      canPop: !_full,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _full) _setFull(false);
      },
      child: fill ? _fullScreen() : _page(),
    );
  }

  Widget _page() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Tekrar izle',
            onPressed: _ready ? _replay : null,
            icon: const Icon(Icons.replay_rounded),
          ),
        ],
      ),
      body: Center(
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: Colors.white70))
            : !_ready
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: _c.value.aspectRatio,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                          onTap: () => _c.value.isPlaying
                              ? _c.pause()
                              : _ended
                              ? _replay()
                              : _c.play(),
                          child: VideoPlayer(_c),
                        ),
                        if (!_c.value.isPlaying && !_ended)
                          const IgnorePointer(
                            child: Center(
                              child: Icon(
                                Icons.play_circle_fill_rounded,
                                size: 64,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        if (!_ended)
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: IconButton(
                              tooltip: 'Tam ekran',
                              onPressed: () => _setFull(true),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black45,
                              ),
                              icon: const Icon(
                                Icons.fullscreen_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                        if (_ended)
                          ColoredBox(
                            color: Colors.black87,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FilledButton.icon(
                                    onPressed: _replay,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.14,
                                      ),
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
                          ),
                      ],
                    ),
                  ),
                  VideoProgressIndicator(
                    _c,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    colors: const VideoProgressColors(
                      playedColor: Color(0xFF10B981),
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                  if ((widget.storyUrl ?? '').isNotEmpty)
                    FutureBuilder<bool>(
                      future: _igAvailable,
                      builder: (context, snap) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Row(
                          children: [
                            if (snap.data == true) ...[
                              Expanded(
                                child: _ShareButton(
                                  label: 'Instagram',
                                  icon: Icons.camera_alt_outlined,
                                  color: const Color(0xFFD62976),
                                  busy: _sharing == 'ig',
                                  onPressed: _sharing == null
                                      ? () => _share('ig')
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: _ShareButton(
                                label: 'WhatsApp',
                                icon: Icons.chat_rounded,
                                color: const Color(0xFF1DA851),
                                busy: _sharing == 'wa',
                                onPressed: _sharing == null
                                    ? () => _share('wa')
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: color,
      foregroundColor: Colors.white,
      disabledBackgroundColor: color.withValues(alpha: 0.5),
      disabledForegroundColor: Colors.white70,
      minimumSize: const Size(0, 46),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    icon: busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Icon(icon),
    label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
  );
}
