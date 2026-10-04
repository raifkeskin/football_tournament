import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';

/// Afişlerin mantıksal boyutu; paylaşırken 3x çizilir → 1080×1920
/// (Instagram hikaye boyutu).
const kPosterSize = Size(360, 640);
const _kPixelRatio = 3.0;

/// Afişi önizleme popup'ında gösterir; "Paylaş" ile PNG'ye çevirip telefonun
/// paylaşım menüsünü açar (web'de Web Share; desteklenmiyorsa indirilir).
///
/// [imageUrls]: afişteki ağ resimleri; çizimden önce yüklenir ki PNG'de
/// eksik kalmasın.
Future<void> showPosterPreview({
  required BuildContext context,
  required Widget poster,
  required String fileName,
  List<String> imageUrls = const [],
  String? shareText,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _PosterPreviewDialog(
      poster: poster,
      fileName: fileName,
      imageUrls: imageUrls,
      shareText: shareText,
    ),
  );
}

class _PosterPreviewDialog extends StatefulWidget {
  const _PosterPreviewDialog({
    required this.poster,
    required this.fileName,
    required this.imageUrls,
    this.shareText,
  });

  final Widget poster;
  final String fileName;
  final List<String> imageUrls;
  final String? shareText;

  @override
  State<_PosterPreviewDialog> createState() => _PosterPreviewDialogState();
}

class _PosterPreviewDialogState extends State<_PosterPreviewDialog> {
  final _boundaryKey = GlobalKey();
  late final Future<void> _ready = _prepare();
  bool _sharing = false;

  Future<void> _prepare() async {
    await GoogleFonts.pendingFonts();
    if (!mounted) return;
    await Future.wait([
      // Afiş zemini (stadyum fotoğrafı) PNG'ye çizilmeden önce hazır olsun.
      precacheImage(const AssetImage('assets/anasayfa.jpg'), context),
      for (final u in widget.imageUrls.where((u) => u.trim().isNotEmpty))
        precacheImage(NetworkImage(u), context, onError: (_, _) {}),
    ]);
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      // Önizleme ekrana sığsın diye küçültülmüş olabilir; RepaintBoundary
      // afişin kendi boyutunda (360×640) çizer, 3x ile 1080×1920 olur.
      final boundary =
          _boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: _kPixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('Afiş oluşturulamadı.');
      final bytes = data.buffer.asUint8List();
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              mimeType: 'image/png',
              name: '${widget.fileName}.png',
            ),
          ],
          fileNameOverrides: ['${widget.fileName}.png'],
          text: widget.shareText,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Paylaşılamadı: $e')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.62;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: adminDialogDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AdminDialogHeader(
              icon: Icons.ios_share_rounded,
              title: 'Afişi Paylaş',
              subtitle: 'Instagram hikayesi için 1080×1920',
            ),
            const SizedBox(height: 14),
            FutureBuilder<void>(
              future: _ready,
              builder: (context, snap) {
                final done = snap.connectionState == ConnectionState.done;
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: AspectRatio(
                    aspectRatio: kPosterSize.width / kPosterSize.height,
                    child: !done
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: kAdminAccent,
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: FittedBox(
                              child: RepaintBoundary(
                                key: _boundaryKey,
                                child: SizedBox.fromSize(
                                  size: kPosterSize,
                                  child: widget.poster,
                                ),
                              ),
                            ),
                          ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            AdminPrimaryButton(
              label: 'PAYLAŞ',
              icon: Icons.ios_share_rounded,
              busy: _sharing,
              onPressed: _share,
            ),
            const SizedBox(height: 10),
            AdminSecondaryButton(
              label: 'KAPAT',
              onPressed: _sharing ? null : () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Afişlerde logo: ağ resmi (web'de HTML resim bileşeni PNG'ye çizilemez);
/// yoksa / yüklenemezse baş harfli rozet.
class PosterLogo extends StatelessWidget {
  const PosterLogo({
    super.key,
    required this.url,
    required this.name,
    required this.size,
    this.badgeColor = const Color(0xFFF5C400),
    this.badgeTextColor = const Color(0xFF111827),
    this.shadow = false,
  });

  final String url;
  final String name;
  final double size;
  final Color badgeColor;
  final Color badgeTextColor;

  /// Koyu zeminde öne çıksın diye logonun şeklini izleyen gölge.
  final bool shadow;

  String get _initials {
    final w = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    return w
        .take(2)
        .map((e) => e.characters.first)
        .join()
        .replaceAll('i', 'İ')
        .replaceAll('ı', 'I')
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
      child: Text(
        _initials,
        style: TextStyle(
          color: badgeTextColor,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.36,
        ),
      ),
    );
    if (url.trim().isEmpty) return badge;
    Widget image({Color? color}) => Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      color: color,
      colorBlendMode: color == null ? null : BlendMode.srcIn,
      errorBuilder: (_, _, _) => color == null ? badge : const SizedBox(),
    );
    if (!shadow) return image();
    // Logonun kendi şeklinde koyu, bulanık gölge (çerçeve/daire yok).
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: Offset(0, size * 0.035),
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: size * 0.05,
              sigmaY: size * 0.05,
            ),
            child: image(color: Colors.black.withValues(alpha: 0.6)),
          ),
        ),
        image(),
      ],
    );
  }
}
