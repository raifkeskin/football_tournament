import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/youtube_player_page.dart';

/// Maç yayınını oynatır; yetkili maçın ve 2. yarının başladığı anı
/// "Şu an" düğmeleriyle seçer (Golleri Bul penceresindeki alanlar dolar).
/// Oynatıcı ayrı sayfada: telefonda açılır pencere içindeki WebView donuyor.
Future<({int? kickoff, int? second})?> pickStreamMoments(
  BuildContext context, {
  required String videoId,
  int? kickoff,
  int? second,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<({int? kickoff, int? second})>(
      settings: const RouteSettings(name: 'StreamMomentPicker'),
      fullscreenDialog: true,
      builder: (_) =>
          _Picker(videoId: videoId, kickoff: kickoff, second: second),
    ),
  );
}

class _Picker extends StatefulWidget {
  const _Picker({required this.videoId, this.kickoff, this.second});

  final String videoId;
  final int? kickoff;
  final int? second;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  late final _controller = YoutubePlayerController.fromVideoId(
    videoId: widget.videoId,
    autoPlay: false,
    params: const YoutubePlayerParams(
      showFullscreenButton: kIsWeb,
      strictRelatedVideos: true,
      origin: youtubePlayerOrigin,
    ),
  );
  late int? _kickoff = widget.kickoff;
  late int? _second = widget.second;

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  Future<int> _now() async => (await _controller.currentTime).round();

  static String _clock(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  Widget _row(String label, int? value, VoidCallback onNow) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: kAdminMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value == null ? 'Seçilmedi' : _clock(value),
                  style: TextStyle(
                    color: value == null ? Colors.white38 : Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onNow,
            style: FilledButton.styleFrom(backgroundColor: kAdminAccent),
            icon: const Icon(Icons.my_location_rounded, size: 18),
            label: const Text(
              'ŞU AN',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerFrame(
      controller: _controller,
      title: 'Başlangıç anlarını seç',
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Videoyu ilgili ana getirip "Şu an"a basın. Yayın maç '
              'başladıktan sonra açıldıysa maçın başlangıcını boş bırakın.',
              style: TextStyle(color: kAdminMuted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            _row('MAÇIN BAŞLADIĞI AN', _kickoff, () async {
              final t = await _now();
              if (mounted) setState(() => _kickoff = t);
            }),
            _row('2. YARININ BAŞLADIĞI AN', _second, () async {
              final t = await _now();
              if (mounted) setState(() => _second = t);
            }),
            const SizedBox(height: 4),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, (
                  kickoff: _kickoff,
                  second: _second,
                )),
                style: FilledButton.styleFrom(backgroundColor: kAdminAccent),
                child: const Text(
                  'KULLAN',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
