import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

const youtubePlayerOrigin = 'https://masterfutbol.web.app';

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
      showFullscreenButton: true,
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Kapat',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Maç Yayını', style: TextStyle(fontSize: 16)),
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
      ),
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: YoutubePlayer(controller: _controller),
        ),
      ),
    );
  }
}
