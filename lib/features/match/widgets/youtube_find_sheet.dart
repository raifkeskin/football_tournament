import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/web_safe_image.dart';
import '../services/youtube_autolink_service.dart';

/// "12 Ekim · 21:04"
String broadcastDate(DateTime? at) =>
    at == null ? '' : DateFormat('d MMMM · HH:mm', 'tr_TR').format(at);

/// YouTube kapak görseli (16:9) + oynat simgesi.
class BroadcastThumb extends StatelessWidget {
  const BroadcastThumb({super.key, required this.videoId, this.radius = 8});

  final String videoId;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFF0B1220)),
            WebSafeImage(
              url: 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg',
              fit: BoxFit.cover,
            ),
            const Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white70,
                size: 30,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Maç detayı › Medya: turnuva kanalında bu maçın yayınını arar; seçilen
/// yayın maçın canlı yayın linki olur.
Future<void> showYoutubeFindSheet({
  required BuildContext context,
  required String matchId,
  required VoidCallback onAttached,
  required VoidCallback onManual,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _YoutubeFindSheet(
      matchId: matchId,
      onAttached: onAttached,
      onManual: onManual,
    ),
  );
}

class _YoutubeFindSheet extends StatefulWidget {
  const _YoutubeFindSheet({
    required this.matchId,
    required this.onAttached,
    required this.onManual,
  });

  final String matchId;
  final VoidCallback onAttached;
  final VoidCallback onManual;

  @override
  State<_YoutubeFindSheet> createState() => _YoutubeFindSheetState();
}

class _YoutubeFindSheetState extends State<_YoutubeFindSheet> {
  final _service = YoutubeAutolinkService();
  late final Future<List<FoundBroadcast>> _items = _service.search(
    widget.matchId,
  );
  String? _selected;
  bool _saving = false;

  Future<void> _attach() async {
    final id = _selected;
    if (id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await _service.attach(widget.matchId, id);
      nav.pop();
      widget.onAttached();
      messenger.showSnackBar(
        const SnackBar(content: Text('Yayın maça eklendi.')),
      );
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _button(String label, VoidCallback? onTap, {bool primary = false}) {
    return Expanded(
      child: SizedBox(
        height: 46,
        child: primary
            ? FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kAdminAccent,
                  foregroundColor: const Color(0xFF04120D),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onTap,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
              )
            : OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onTap,
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: FutureBuilder<List<FoundBroadcast>>(
        future: _items,
        builder: (context, snap) {
          final loading = snap.connectionState != ConnectionState.done;
          final items = snap.data ?? const <FoundBroadcast>[];
          _selected ??= items.isEmpty ? null : items.first.videoId;
          final empty = !loading && items.isEmpty;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                empty ? 'Uygun yayın bulunamadı' : 'Kanalda bulunan yayınlar',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                snap.hasError
                    ? '${snap.error}'
                    : empty
                    ? 'Kanalın son 50 videosunda iki takımın adı geçen bir '
                          'yayın yok. Linki elle ekleyebilirsiniz.'
                    : 'Turnuvanın YouTube kanalında iki takımın adı geçen '
                          'videolar; maç saatine en yakını başta.',
                style: const TextStyle(color: Colors.white60, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: CircularProgressIndicator(color: kAdminAccent),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        _resultRow(items[i], best: i == 0),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _button(
                    snap.hasError || empty ? 'Kapat' : 'Vazgeç',
                    _saving ? null : () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  if (snap.hasError || empty)
                    _button('Elle link ekle', () {
                      Navigator.pop(context);
                      widget.onManual();
                    }, primary: true)
                  else
                    _button(
                      'Maça ekle',
                      loading || _saving || _selected == null ? null : _attach,
                      primary: true,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _resultRow(FoundBroadcast b, {required bool best}) {
    final sel = _selected == b.videoId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: sel ? kAdminAccent : Colors.transparent,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _saving ? null : () => setState(() => _selected = b.videoId),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                SizedBox(width: 112, child: BroadcastThumb(videoId: b.videoId)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        broadcastDate(b.at),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11.5,
                        ),
                      ),
                      if (best)
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            '✓ En uygun',
                            style: TextStyle(
                              color: kAdminAccent,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
