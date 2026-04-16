import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver2_fixed/image_gallery_saver2_fixed.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../models/match.dart';
import '../widgets/web_safe_image.dart';
import '../services/database_service.dart';
import '../services/in_app_browser.dart';
import '../services/image_upload_service.dart';
import 'admin_match_event_screen.dart';
import 'admin_match_lineup_screen.dart';

class _SecondYellowCardIcon extends StatelessWidget {
  const _SecondYellowCardIcon();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 14,
      height: 20,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.amber, Colors.red],
          stops: [0.5, 0.5],
        ),
      ),
    );
  }
}

String _shortenName(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) return cleaned;
  final parts = cleaned.split(' ');
  if (parts.length <= 2) return cleaned;
  final first = parts[0];
  final second = parts[1];
  final last = parts.last;
  final initial = last.isEmpty ? '' : '${last[0].toUpperCase()}.';
  return '$first $second $initial';
}

String _normalizeUrl(String raw) {
  final url = raw.trim();
  if (url.isEmpty) return '';
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return 'https://$url';
}

Future<void> _openExternalUrl(BuildContext context, String rawUrl) async {
  final normalized = _normalizeUrl(rawUrl);
  final uri = Uri.tryParse(normalized);
  if (uri == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link geçersiz.')));
    return;
  }
  try {
    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: kIsWeb ? '_blank' : null,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Link açılamadı.')));
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Link açılamadı: $e')));
  }
}

String? _extractYoutubeVideoId(String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return null;
  final converted = YoutubePlayerController.convertUrlToId(trimmed);
  if ((converted ?? '').trim().isNotEmpty) return converted!.trim();
  final uri = Uri.tryParse(_normalizeUrl(trimmed));
  if (uri == null) return null;

  if (uri.host.contains('youtu.be')) {
    final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first.trim();
    return id.isEmpty ? null : id;
  }

  if (uri.host.contains('youtube.com') ||
      uri.host.contains('youtube-nocookie.com')) {
    final v = (uri.queryParameters['v'] ?? '').trim();
    if (v.isNotEmpty) return v;

    final segments = uri.pathSegments;
    final embedIndex = segments.indexOf('embed');
    if (embedIndex != -1 && segments.length > embedIndex + 1) {
      final id = segments[embedIndex + 1].trim();
      return id.isEmpty ? null : id;
    }

    final shortsIndex = segments.indexOf('shorts');
    if (shortsIndex != -1 && segments.length > shortsIndex + 1) {
      final id = segments[shortsIndex + 1].trim();
      return id.isEmpty ? null : id;
    }
  }

  return null;
}

List<String> _extractVideoUrls(String raw) {
  final cleaned = raw.replaceAll('\r', '\n').trim();
  if (cleaned.isEmpty) return const [];
  final parts = cleaned.split(RegExp(r'[\n,; ]+'));
  final out = <String>[];
  for (final p in parts) {
    final s = p.trim();
    if (s.isEmpty) continue;
    final normalized = _normalizeUrl(s);
    final uri = Uri.tryParse(normalized);
    if (uri == null) continue;
    if ((uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      continue;
    }
    out.add(normalized);
  }
  return out;
}

Future<void> _openPhotoDialog(BuildContext context, String imageUrl) async {
  final url = _normalizeUrl(imageUrl);
  if (url.isEmpty) return;
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) {
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: Colors.black,
            child: SafeArea(
              child: Column(
                children: [
                  Container(
                    height: 50,
                    color: const Color(0xFF1E293B),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        const Spacer(),
                        IconButton(
                          onPressed: () => _openExternalUrl(context, url),
                          icon: const Icon(
                            Icons.file_download,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
                          maxWidth: MediaQuery.sizeOf(context).width,
                        ),
                        child: Image.network(
                          url,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          },
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white54,
                            size: 64,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

Future<void> _openVideoDialog(BuildContext context, String rawUrl) async {
  final normalized = _normalizeUrl(rawUrl);
  if (normalized.isEmpty) return;

  final youtubeId = _extractYoutubeVideoId(normalized);
  if (youtubeId != null) {
    try {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => _YoutubeVideoDialog(videoId: youtubeId),
      );
    } catch (_) {
      await openInAppBrowser(context, normalized);
    }
    return;
  }

  final lower = normalized.toLowerCase();
  final isMp4 = lower.contains('.mp4');
  if (isMp4) {
    try {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => _Mp4VideoDialog(videoUrl: normalized),
      );
    } catch (_) {
      await openInAppBrowser(context, normalized);
    }
    return;
  }

  await openInAppBrowser(context, normalized);
}

class _YoutubeVideoDialog extends StatefulWidget {
  const _YoutubeVideoDialog({required this.videoId});
  final String videoId;

  @override
  State<_YoutubeVideoDialog> createState() => _YoutubeVideoDialogState();
}

class _YoutubeVideoDialogState extends State<_YoutubeVideoDialog> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
      ),
    );
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: Colors.black,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 50,
                  color: const Color(0xFF1E293B),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: YoutubePlayer(
                    controller: _controller,
                    aspectRatio: 16 / 9,
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

class _Mp4VideoDialog extends StatefulWidget {
  const _Mp4VideoDialog({required this.videoUrl});
  final String videoUrl;

  @override
  State<_Mp4VideoDialog> createState() => _Mp4VideoDialogState();
}

class _Mp4VideoDialogState extends State<_Mp4VideoDialog> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    final uri = Uri.tryParse(widget.videoUrl);
    if (uri == null) return;
    final c = VideoPlayerController.networkUrl(uri);
    _controller = c;
    c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      c.setLooping(true);
      c.play();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final initialized = c?.value.isInitialized == true;
    final aspect = initialized ? c!.value.aspectRatio : (16 / 9);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: Colors.black,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 50,
                  color: const Color(0xFF1E293B),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                AspectRatio(
                  aspectRatio: aspect,
                  child: initialized
                      ? VideoPlayer(c!)
                      : const Center(child: CircularProgressIndicator()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _saveNetworkImageToGallery(
  BuildContext context, {
  required String imageUrl,
  String? fileName,
}) async {
  try {
    PermissionStatus status;
    if (Platform.isIOS) {
      status = await Permission.photosAddOnly.request();
      if (!status.isGranted) {
        status = await Permission.photos.request();
      }
    } else {
      status = await Permission.photos.request();
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
    }
    if (!status.isGranted) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Galeriye kayıt izni verilmedi.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final uri = Uri.tryParse(imageUrl);
    if (uri == null) throw Exception('Geçersiz görsel linki');
    final resp = await http.get(uri);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Görsel indirilemedi (${resp.statusCode})');
    }

    final result = await ImageGallerySaver.saveImage(
      resp.bodyBytes,
      quality: 100,
      name: fileName,
    );
    final ok = (result is Map) && (result['isSuccess'] == true);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Görsel galeriye kaydedildi.' : 'Kayıt başarısız.'),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
    );
  }
}

Widget _eventIcon(
  String type, {
  required bool isSecondYellow,
  required bool isOwnGoal,
}) {
  switch (type) {
    case 'goal':
      return Icon(
        Icons.sports_soccer,
        color: isOwnGoal ? Colors.red : Colors.green,
      );
    case 'substitution':
      return const Icon(Icons.swap_horiz_rounded, color: Colors.blueGrey);
    case 'assist':
      return const Icon(Icons.handshake_rounded, color: Colors.blue);
    case 'yellow_card':
      return isSecondYellow
          ? const _SecondYellowCardIcon()
          : const Icon(Icons.rectangle, color: Colors.amber, size: 20);
    case 'red_card':
      return const Icon(Icons.rectangle, color: Colors.red, size: 20);
    default:
      return const Icon(Icons.info_outline);
  }
}

class MatchDetailsScreen extends StatefulWidget {
  final MatchModel match;
  final bool isAdmin;
  const MatchDetailsScreen({
    super.key,
    required this.match,
    this.isAdmin = false,
  });

  @override
  State<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends State<MatchDetailsScreen> {
  final _picker = ImagePicker();
  final _imageUploadService = ImgBBUploadService();

  Future<void> _openYoutubeLinkEditor(MatchModel match) async {
    final controller = TextEditingController(text: match.youtubeUrl ?? '');
    final db = DatabaseService();
    final cs = Theme.of(context).colorScheme;

    try {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: cs.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                12 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    'YouTube Maç Linki',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Material(
                    color: cs.surfaceContainerLow,
                    elevation: 0.5,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      child: TextField(
                        controller: controller,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          hintText: 'https://youtube.com/…',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            controller.clear();
                            Navigator.pop(context, true);
                          },
                          child: const Text('Kaldır'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Kaydet'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (saved != true) return;
      await db.updateMatchYoutubeUrl(
        matchId: match.id,
        youtubeUrl: controller.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('YouTube linki güncellendi.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _openBroadcastLinkEditor(MatchModel match) async {
    final controller = TextEditingController(text: match.youtubeUrl ?? '');
    final db = DatabaseService();

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text(
              'Maç Yayın Linki',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'https://…'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      );
      if (saved != true) return;
      await db.updateMatchYoutubeUrl(
        matchId: match.id,
        youtubeUrl: controller.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maç yayını güncellendi.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _pickAndUploadHighlightPhoto({
    required MatchModel match,
    required bool isHome,
  }) async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final url = await _imageUploadService.uploadImage(File(picked.path));
      final trimmed = (url ?? '').trim();
      if (trimmed.isEmpty) {
        throw Exception('Fotoğraf yüklenemedi.');
      }

      await DatabaseService().updateMatchHighlightPhotoUrl(
        matchId: match.id,
        isHome: isHome,
        photoUrl: trimmed,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fotoğraf eklendi.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _openHighlightsActionSheet(MatchModel match) async {
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.link_rounded),
                title: const Text(
                  'Maç Yayın Linki Ekle',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _openBroadcastLinkEditor(match);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_back_outlined),
                title: const Text(
                  'Ev Sahibi Takım Fotosu Ekle',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadHighlightPhoto(match: match, isHome: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_front_outlined),
                title: const Text(
                  'Deplasman Takım Fotosu Ekle',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadHighlightPhoto(match: match, isHome: false);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openPitchEditor(MatchModel match) async {
    final cs = Theme.of(context).colorScheme;
    final matchRef = FirebaseFirestore.instance
        .collection('matches')
        .doc(match.id);
    try {
      final saved = await showModalBottomSheet<Map<String, String?>?>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        backgroundColor: cs.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          String? selectedId = (match.pitchId ?? '').trim().isEmpty
              ? null
              : match.pitchId!.trim();
          String? selectedName = (match.pitchName ?? '').trim().isEmpty
              ? null
              : match.pitchName!.trim();
          return StatefulBuilder(
            builder: (context, setSheetState) {
              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    12 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      const Text(
                        'Saha Seç',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 10),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('pitches')
                            .orderBy('nameKey')
                            .snapshots(),
                        builder: (context, snap) {
                          final docs = snap.data?.docs ?? const [];
                          return DropdownButtonFormField<String?>(
                            key: ValueKey(selectedId),
                            initialValue: selectedId,
                            decoration: const InputDecoration(
                              labelText: 'Saha',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Saha Seçilmedi'),
                              ),
                              for (final d in docs)
                                DropdownMenuItem<String?>(
                                  value: d.id,
                                  child: Text(
                                    ((d.data()
                                                as Map<
                                                  String,
                                                  dynamic
                                                >)['name'] ??
                                            '')
                                        .toString(),
                                  ),
                                ),
                            ],
                            onChanged: (v) {
                              final selected = docs
                                  .where((e) => e.id == v)
                                  .toList();
                              final data = selected.isEmpty
                                  ? null
                                  : (selected.first.data()
                                        as Map<String, dynamic>);
                              final name = (data?['name'] ?? '')
                                  .toString()
                                  .trim();
                              setSheetState(() {
                                selectedId = v;
                                selectedName = v == null || name.isEmpty
                                    ? null
                                    : name;
                              });
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        onPressed: () => Navigator.pop(context, {
                          'pitchId': selectedId,
                          'pitchName': selectedName,
                        }),
                        child: const Text('Kaydet'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

      if (saved == null) return;
      await matchRef.update({
        'pitchId': saved['pitchId'],
        'pitchName': saved['pitchName'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saha bilgisi güncellendi.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _openDateTimeEditor(MatchModel match) async {
    final cs = Theme.of(context).colorScheme;
    final matchRef = FirebaseFirestore.instance
        .collection('matches')
        .doc(match.id);

    DateTime? selectedDate;
    final dateStr = (match.matchDate ?? '').trim();
    final dm = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(dateStr);
    if (dm != null) {
      final y = int.tryParse(dm.group(1) ?? '');
      final mo = int.tryParse(dm.group(2) ?? '');
      final d = int.tryParse(dm.group(3) ?? '');
      if (y != null && mo != null && d != null) {
        selectedDate = DateTime(y, mo, d);
      }
    }
    final hourController = TextEditingController();
    final minuteController = TextEditingController();
    final hourFocus = FocusNode();
    final minuteFocus = FocusNode();

    final timeText = (match.matchTime ?? '').trim();
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(timeText);
    if (m != null) {
      hourController.text = m.group(1)!.padLeft(2, '0');
      minuteController.text = m.group(2)!.padLeft(2, '0');
    }

    String ddMmYyyy(DateTime d) {
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    }

    String yyyyMmDd(DateTime d) {
      return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickDate() async {
              final now = DateTime.now();
              final initial = selectedDate ?? now;
              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 10),
              );
              if (picked == null) return;
              setDialogState(() {
                selectedDate = DateTime(picked.year, picked.month, picked.day);
              });
            }

            Future<void> save() async {
              final d = selectedDate;
              if (d == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lütfen maç tarihini seçin.')),
                );
                return;
              }
              final hh = hourController.text.trim();
              final mm = minuteController.text.trim();
              if (hh.isEmpty || mm.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lütfen saat bilgisini girin.')),
                );
                return;
              }
              final h = int.tryParse(hh);
              final m = int.tryParse(mm);
              if (h == null ||
                  m == null ||
                  h < 0 ||
                  h > 23 ||
                  m < 0 ||
                  m > 59) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saat formatı geçersiz.')),
                );
                return;
              }
              final time =
                  '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
              await matchRef.update({
                'matchDate': yyyyMmDd(d),
                'matchTime': time,
                'dateString': FieldValue.delete(),
                'time': FieldValue.delete(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
              if (!context.mounted) return;
              Navigator.pop(context, true);
            }

            return AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              title: InkWell(
                onTap: pickDate,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month_outlined, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          selectedDate == null
                              ? 'Maç Tarihi'
                              : ddMmYyyy(selectedDate!),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: TextField(
                          controller: hourController,
                          focusNode: hourFocus,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          onChanged: (v) {
                            final text = v.trim();
                            if (text.length == 2) {
                              FocusScope.of(context).requestFocus(minuteFocus);
                            }
                          },
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          decoration: const InputDecoration(
                            hintText: 'SS',
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
                          maxLength: 2,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        ':',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 64,
                        child: TextField(
                          controller: minuteController,
                          focusNode: minuteFocus,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          onChanged: (v) {
                            final text = v.trim();
                            if (text.length == 2) {
                              FocusScope.of(context).unfocus();
                            }
                          },
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          decoration: const InputDecoration(
                            hintText: 'DK',
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
                          maxLength: 2,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: pickDate,
                        icon: const Icon(Icons.edit_calendar_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      onPressed: save,
                      child: const Text('KAYDET'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    hourController.dispose();
    minuteController.dispose();
    hourFocus.dispose();
    minuteFocus.dispose();

    if (!mounted) return;
    if (ok == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tarih/Saat güncellendi.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dbService = DatabaseService();

    return StreamBuilder<List<MatchEvent>>(
      stream: dbService.getMatchEvents(widget.match.id),
      builder: (context, eventSnapshot) {
        if (eventSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Maç Detayı')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (eventSnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Maç Detayı')),
            body: Center(child: Text('Hata: ${eventSnapshot.error}')),
          );
        }

        final events = eventSnapshot.data ?? const <MatchEvent>[];

        int htHomeFromEvents(String teamId) => events
            .where(
              (e) => e.type == 'goal' && e.minute <= 45 && e.teamId == teamId,
            )
            .length;

        return StreamBuilder<MatchModel>(
          stream: dbService.watchMatch(widget.match.id),
          builder: (context, matchSnapshot) {
            if (!matchSnapshot.hasData) {
              return Scaffold(
                appBar: AppBar(title: const Text('Maç Detayı')),
                body: const Center(child: CircularProgressIndicator()),
              );
            }

            final m = matchSnapshot.data!;
            final showScores = m.status != MatchStatus.notStarted;
            final htHome =
                m.score?.halfTime.home ??
                (showScores ? htHomeFromEvents(m.homeTeamId) : null);
            final htAway =
                m.score?.halfTime.away ??
                (showScores ? htHomeFromEvents(m.awayTeamId) : null);

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('teams')
                  .where(
                    FieldPath.documentId,
                    whereIn: [m.homeTeamId, m.awayTeamId],
                  )
                  .snapshots(),
              builder: (context, teamSnapshot) {
                final teamLogoById = <String, String>{};
                if (teamSnapshot.hasData) {
                  for (final doc in teamSnapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final raw = (data['logoUrl'] ?? data['logo'] ?? '')
                        .toString()
                        .trim();
                    teamLogoById[doc.id] = raw;
                  }
                }

                final homeLogo = (m.homeTeamLogoUrl.trim()).isNotEmpty
                    ? m.homeTeamLogoUrl
                    : (teamLogoById[m.homeTeamId] ?? '');
                final awayLogo = (m.awayTeamLogoUrl.trim()).isNotEmpty
                    ? m.awayTeamLogoUrl
                    : (teamLogoById[m.awayTeamId] ?? '');

                final showLineupsTab = widget.isAdmin;

                return DefaultTabController(
                  length: showLineupsTab ? 3 : 2,
                  child: Builder(
                    builder: (context) {
                      final tabController = DefaultTabController.of(context);
                      final isAdmin = widget.isAdmin;

                      return Scaffold(
                        appBar: AppBar(title: const Text('Maç Detayı')),
                        floatingActionButton: !isAdmin
                            ? null
                            : AnimatedBuilder(
                                animation: tabController,
                                builder: (context, _) {
                                  final idx = tabController.index;
                                  final isHighlightsTab =
                                      (showLineupsTab && idx == 2) ||
                                      (!showLineupsTab && idx == 1);

                                  if (idx == 0) {
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        FloatingActionButton(
                                          heroTag: 'yt_${m.id}',
                                          mini: true,
                                          onPressed: () =>
                                              _openYoutubeLinkEditor(m),
                                          child: const Icon(
                                            Icons.videocam_rounded,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        FloatingActionButton(
                                          heroTag: 'pitch_${m.id}',
                                          mini: true,
                                          onPressed: () => _openPitchEditor(m),
                                          child: const Icon(
                                            Icons.location_on_outlined,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        FloatingActionButton(
                                          heroTag: 'event_${m.id}',
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    AdminMatchEventScreen(
                                                      match: m,
                                                    ),
                                              ),
                                            );
                                          },
                                          child: const Icon(Icons.add),
                                        ),
                                      ],
                                    );
                                  }

                                  if (isHighlightsTab) {
                                    return FloatingActionButton(
                                      heroTag: 'highlights_${m.id}',
                                      onPressed: () =>
                                          _openHighlightsActionSheet(m),
                                      child: const Icon(Icons.add),
                                    );
                                  }

                                  return const SizedBox.shrink();
                                },
                              ),
                        body: Column(
                          children: [
                            Card(
                              margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 14,
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _TeamInfo(
                                            name: m.homeTeamName,
                                            logoUrl: homeLogo,
                                            textAlign: TextAlign.right,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '${m.homeScore} - ${m.awayScore}',
                                              style: const TextStyle(
                                                fontSize: 44,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            if (showScores)
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (htHome != null &&
                                                      htAway != null)
                                                    _ScorePill(
                                                      label: 'İY',
                                                      value: '$htHome-$htAway',
                                                    ),
                                                  if (htHome != null &&
                                                      htAway != null)
                                                    const SizedBox(width: 8),
                                                  _ScorePill(
                                                    label: 'MS',
                                                    value:
                                                        '${m.homeScore}-${m.awayScore}',
                                                  ),
                                                ],
                                              ),
                                            const SizedBox(height: 8),
                                            Builder(
                                              builder: (context) {
                                                final timeText =
                                                    (m.matchTime ?? '')
                                                        .toString()
                                                        .trim();
                                                final dateStr =
                                                    (m.matchDate ?? '')
                                                        .toString()
                                                        .trim();
                                                final hasDateTime =
                                                    dateStr.isNotEmpty &&
                                                    timeText.isNotEmpty;
                                                final text = hasDateTime
                                                    ? '${dateStr.split('-').reversed.join('.')}  $timeText'
                                                    : 'Tarih ve Saat Belirlenmedi';
                                                final row = Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    if (!hasDateTime)
                                                      Icon(
                                                        Icons
                                                            .calendar_month_outlined,
                                                        size: 16,
                                                        color: Colors.white,
                                                      ),
                                                    if (!hasDateTime)
                                                      const SizedBox(width: 6),
                                                    Text(
                                                      text,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                );
                                                if (!hasDateTime &&
                                                    widget.isAdmin) {
                                                  return InkWell(
                                                    onTap: () =>
                                                        _openDateTimeEditor(m),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 4,
                                                          ),
                                                      child: row,
                                                    ),
                                                  );
                                                }
                                                return row;
                                              },
                                            ),
                                            if ((m.pitchName ?? '')
                                                .trim()
                                                .isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 6,
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons
                                                          .location_on_outlined,
                                                      size: 16,
                                                      color: Colors.white,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Saha: ${(m.pitchName ?? '').trim()}',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if (m.status == MatchStatus.live &&
                                                m.minute != null) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                "CANLI • ${m.minute}'",
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _TeamInfo(
                                            name: m.awayTeamName,
                                            logoUrl: awayLogo,
                                            textAlign: TextAlign.left,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: Card(
                                margin: EdgeInsets.zero,
                                child: TabBar(
                                  labelColor: Colors.white,
                                  unselectedLabelColor: Colors.white,
                                  indicatorColor: Colors.white,
                                  labelStyle: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  unselectedLabelStyle: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  tabs: [
                                    const Tab(text: 'Detay'),
                                    if (showLineupsTab)
                                      const Tab(text: 'Kadrolar'),
                                    const Tab(text: 'Önemli Anlar'),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _KeepAlive(
                                    child: _EventsTab(
                                      match: m,
                                      events: events,
                                      isAdmin: isAdmin,
                                    ),
                                  ),
                                  if (showLineupsTab)
                                    _KeepAlive(
                                      child: _LineupsTab(
                                        match: m,
                                        isAdmin: isAdmin,
                                      ),
                                    ),
                                  _KeepAlive(child: _HighlightsTab(match: m)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _LineupsTab extends StatelessWidget {
  const _LineupsTab({required this.match, required this.isAdmin});

  final MatchModel match;
  final bool isAdmin;

  Future<void> _openLineupSheet(
    BuildContext context, {
    required bool isStarting,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: Text('Ev Sahibi • ${match.homeTeamName}'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminMatchLineupScreen(
                        match: match,
                        isHome: true,
                        initialTabIndex: isStarting ? 0 : 1,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.flight_takeoff_outlined),
                title: Text('Deplasman • ${match.awayTeamName}'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminMatchLineupScreen(
                        match: match,
                        isHome: false,
                        initialTabIndex: isStarting ? 0 : 1,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Widget _playerRow(LineupPlayer p, ColorScheme cs) {
    final n = (p.number ?? '').trim();
    final number = n.isEmpty ? '-' : n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                number,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              p.name,
              textAlign: TextAlign.left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(BuildContext context, List<LineupPlayer> players) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: players.isEmpty
          ? Text('-', style: TextStyle(color: cs.onSurfaceVariant))
          : Column(children: [for (final p in players) _playerRow(p, cs)]),
    );
  }

  Widget _sectionTitle(
    BuildContext context,
    String text, {
    required bool isStarting,
    required bool hasAnyData,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
      child: SizedBox(
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              text,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (isAdmin && hasAnyData)
              Positioned(
                right: 0,
                child: IconButton(
                  tooltip: 'Düzenle',
                  onPressed: () =>
                      _openLineupSheet(context, isStarting: isStarting),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = match.homeLineupDetail;
    final away = match.awayLineupDetail;
    final homeStarting = home?.starting ?? const <LineupPlayer>[];
    final awayStarting = away?.starting ?? const <LineupPlayer>[];
    final homeSubs = home?.subs ?? const <LineupPlayer>[];
    final awaySubs = away?.subs ?? const <LineupPlayer>[];
    final isEmpty =
        homeStarting.isEmpty &&
        awayStarting.isEmpty &&
        homeSubs.isEmpty &&
        awaySubs.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        if (isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Kadro henüz girilmedi.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        IgnorePointer(
          ignoring: isEmpty,
          child: Opacity(
            opacity: isEmpty ? 0.45 : 1,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionTitle(
                      context,
                      'İlk 11',
                      isStarting: true,
                      hasAnyData:
                          homeStarting.isNotEmpty || awayStarting.isNotEmpty,
                    ),
                    if (isAdmin && homeStarting.isEmpty && awayStarting.isEmpty)
                      Center(
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: IconButton(
                            tooltip: 'İlk 11 ekle',
                            onPressed: () =>
                                _openLineupSheet(context, isStarting: true),
                            icon: Icon(Icons.add, color: Colors.green.shade800),
                          ),
                        ),
                      ),
                    if (isAdmin && homeStarting.isEmpty && awayStarting.isEmpty)
                      const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _box(context, homeStarting)),
                        const SizedBox(width: 12),
                        Expanded(child: _box(context, awayStarting)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _sectionTitle(
                      context,
                      'Yedekler',
                      isStarting: false,
                      hasAnyData: homeSubs.isNotEmpty || awaySubs.isNotEmpty,
                    ),
                    if (isAdmin && homeSubs.isEmpty && awaySubs.isEmpty)
                      Center(
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: IconButton(
                            tooltip: 'Yedek ekle',
                            onPressed: () =>
                                _openLineupSheet(context, isStarting: false),
                            icon: Icon(Icons.add, color: Colors.green.shade800),
                          ),
                        ),
                      ),
                    if (isAdmin && homeSubs.isEmpty && awaySubs.isEmpty)
                      const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _box(context, homeSubs)),
                        const SizedBox(width: 12),
                        Expanded(child: _box(context, awaySubs)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin<_KeepAlive> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _HighlightsTab extends StatelessWidget {
  const _HighlightsTab({required this.match});

  final MatchModel match;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    final videoUrls = _extractVideoUrls(match.youtubeUrl ?? '');
    for (var i = 0; i < videoUrls.length; i++) {
      final title = videoUrls.length == 1 ? 'Maç Yayını' : 'Video ${i + 1}';
      items.add(
        ListTile(
          leading: const Icon(Icons.play_circle_fill, color: Colors.red),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            videoUrls[i],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _openVideoDialog(context, videoUrls[i]),
        ),
      );
    }

    final homePhoto = (match.homeHighlightPhotoUrl ?? '').trim();
    if (homePhoto.isNotEmpty) {
      items.add(
        ListTile(
          leading: const Icon(
            Icons.photo_library,
            color: Colors.lightBlueAccent,
          ),
          title: Text(
            '${match.homeTeamName} Takım Fotosu',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          onTap: () {
            _openPhotoDialog(context, homePhoto);
          },
        ),
      );
    }

    final awayPhoto = (match.awayHighlightPhotoUrl ?? '').trim();
    if (awayPhoto.isNotEmpty) {
      items.add(
        ListTile(
          leading: const Icon(
            Icons.photo_library,
            color: Colors.lightBlueAccent,
          ),
          title: Text(
            '${match.awayTeamName} Takım Fotosu',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          onTap: () {
            _openPhotoDialog(context, awayPhoto);
          },
        ),
      );
    }

    if (items.isEmpty) {
      return const Center(child: Text('Henüz önemli an eklenmedi.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: items.length,
      separatorBuilder: (context, index) =>
          Divider(color: Colors.grey.shade300, height: 1),
      itemBuilder: (context, index) => items[index],
    );
  }
}

class _EventsTab extends StatelessWidget {
  const _EventsTab({
    required this.match,
    required this.events,
    required this.isAdmin,
  });

  final MatchModel match;
  final List<MatchEvent> events;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(
        child: Text('Henüz kaydedilmiş bir olay (gol/kart) yok.'),
      );
    }

    final runningScores = <String?>[];
    var home = 0;
    var away = 0;
    for (final e in events) {
      if (e.type == 'goal') {
        final scoringTeamId = e.isOwnGoal
            ? (e.teamId == match.homeTeamId
                  ? match.awayTeamId
                  : match.homeTeamId)
            : e.teamId;
        if (scoringTeamId == match.homeTeamId) home += 1;
        if (scoringTeamId == match.awayTeamId) away += 1;
        runningScores.add('$home-$away');
      } else {
        runningScores.add(null);
      }
    }

    final dbService = DatabaseService();

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: events.length,
      separatorBuilder: (context, index) =>
          Divider(color: Colors.grey.shade300, height: 1),
      itemBuilder: (context, index) {
        final event = events[index];
        final isHome = event.teamId == match.homeTeamId;
        final isSecondYellow = event.type == 'yellow_card'
            ? events
                  .take(index)
                  .where(
                    (e) =>
                        e.type == 'yellow_card' &&
                        e.teamId == event.teamId &&
                        e.playerName == event.playerName,
                  )
                  .isNotEmpty
            : false;
        final row = _TimelineRow(
          isHome: isHome,
          minute: event.minute,
          type: event.type,
          playerName: event.playerName,
          assistPlayerName: event.assistPlayerName,
          subInPlayerName: event.subInPlayerName,
          isSecondYellow: isSecondYellow,
          runningScore: runningScores[index],
          isOwnGoal: event.isOwnGoal,
        );

        if (!isAdmin) return row;

        return InkWell(
          onLongPress: () async {
            final confirmed = await showModalBottomSheet<bool>(
              context: context,
              showDragHandle: true,
              builder: (context) {
                return SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: const Text('Olayı Sil'),
                        onTap: () => Navigator.pop(context, true),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                );
              },
            );
            if (confirmed != true) return;
            try {
              await dbService.deleteMatchEvent(event);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Olay silindi.'),
                  backgroundColor: Colors.green,
                ),
              );
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Silme hatası: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          child: row,
        );
      },
    );
  }
}

class _TeamInfo extends StatelessWidget {
  final String name;
  final String logoUrl;
  final TextAlign textAlign;
  const _TeamInfo({
    required this.name,
    required this.logoUrl,
    required this.textAlign,
  });

  String _normalizeUrl(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return 'https://$url';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = _normalizeUrl(logoUrl);
    return Column(
      crossAxisAlignment: textAlign == TextAlign.right
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.primary.withValues(alpha: 0.10),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: WebSafeImage(
            url: url,
            width: 56,
            height: 56,
            isCircle: true,
            fallbackIconSize: 26,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          textAlign: textAlign,
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.isHome,
    required this.minute,
    required this.type,
    required this.playerName,
    required this.assistPlayerName,
    required this.isSecondYellow,
    this.runningScore,
    required this.isOwnGoal,
    required this.subInPlayerName,
  });
  final bool isHome;
  final int minute;
  final String type;
  final String playerName;
  final String? assistPlayerName;
  final bool isSecondYellow;
  final String? runningScore;
  final bool isOwnGoal;
  final String? subInPlayerName;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = _eventIcon(
      type,
      isSecondYellow: isSecondYellow,
      isOwnGoal: isOwnGoal,
    );

    final assist = (assistPlayerName ?? '').trim();
    final isGoal = type == 'goal';
    final isSub = type == 'substitution';
    final titleText = _shortenName(playerName);
    final assistText = _shortenName(assist);
    final inName = _shortenName((subInPlayerName ?? '').trim());

    Widget content;
    if (isSub) {
      content = Column(
        crossAxisAlignment: isHome
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: isHome
                ? [
                    Flexible(
                      child: Text(
                        inName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: Color(0xFF2E7D32),
                    ),
                  ]
                : [
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: Color(0xFF2E7D32),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        inName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: isHome
                ? [
                    Flexible(
                      child: Text(
                        titleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.arrow_back_rounded,
                      size: 18,
                      color: Colors.red,
                    ),
                  ]
                : [
                    const Icon(
                      Icons.arrow_back_rounded,
                      size: 18,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        titleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
          ),
        ],
      );
    } else {
      final playerLine = Text(
        isGoal && isOwnGoal ? '$titleText (KK)' : titleText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isGoal ? FontWeight.w900 : FontWeight.w800,
          fontSize: isGoal ? 14 : 13,
        ),
      );
      final assistLine = (isGoal && assistText.isNotEmpty)
          ? Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                assistText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null;

      content = Column(
        crossAxisAlignment: isHome
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [playerLine, ?assistLine],
      );
    }

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: isHome
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (runningScore != null)
            SizedBox(
              width: 76,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    runningScore!,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          if (runningScore != null) const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: isHome
                ? [Flexible(child: content), const SizedBox(width: 8), icon]
                : [icon, const SizedBox(width: 8), Flexible(child: content)],
          ),
        ],
      ),
    );

    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: isHome ? bubble : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 54,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            "$minute'",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: isHome ? const SizedBox.shrink() : bubble,
          ),
        ),
      ],
    );
  }
}
