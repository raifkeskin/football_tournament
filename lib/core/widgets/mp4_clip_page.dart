import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../services/instagram_share.dart';

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
  bool _sharing = false;
  late final Future<bool> _igAvailable = (widget.storyUrl ?? '').isEmpty
      ? Future.value(false)
      : InstagramShare.isAvailable();

  /// Hikâye MP4'ü indirilir, Instagram'ın hikâye ekranında açılır.
  Future<void> _shareStory() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sharing = true);
    if (_c.value.isPlaying) await _c.pause();
    try {
      final r = await http.get(Uri.parse(widget.storyUrl!));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final ok = await InstagramShare.shareVideo(r.bodyBytes, story: true);
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Instagram açılamadı.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Video indirilemedi. Tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  FutureBuilder<bool>(
                    future: _igAvailable,
                    builder: (context, snap) {
                      if (snap.data != true) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: FilledButton.icon(
                          onPressed: _sharing ? null : _shareStory,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFD62976),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: _sharing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.ios_share_rounded),
                          label: const Text(
                            'Instagram hikâyesinde paylaş',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
      ),
    );
  }
}
