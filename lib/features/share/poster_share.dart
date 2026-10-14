import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import 'poster_background.dart';

/// Afişlerin hikâye boyutu (mantıksal); paylaşırken 3x çizilir → 1080×1920.
/// Gönderi boyutu için [PosterFormat.post].
const kPosterSize = Size(360, 640);
const _kPixelRatio = 3.0;

const _kPrefFormat = 'poster_format';
const _kPrefPlain = 'poster_plain';
const _kPrefScorers = 'poster_scorers';

/// Afişi önizleme popup'ında gösterir. Pencerede boyut (hikâye / gönderi),
/// zemin (fotoğraf / sade) ve maç sonucunda gol atanlar seçilir; "Paylaş"
/// PNG'yi telefonun paylaşım menüsüne, "Telefona indir" galeriye (web'de
/// dosya olarak) kaydeder. Seçimler cihazda hatırlanır.
///
/// [imageUrls]: afişteki ağ resimleri; çizimden önce yüklenir ki PNG'de
/// eksik kalmasın.
///
/// [kind] ve [leagueId] ya da [seasonId] verilirse turnuvanın o afiş türü
/// için seçtiği arka plan zemin olarak kullanılır ve sade zemin seçeneği
/// çıkar; [kind] yoksa (kadro, esame, diziliş) afiş kendi takım rengi
/// zeminiyle çizilir.
///
/// [formats]: afişin desteklediği boyutlar (birden fazlaysa sekme çıkar).
/// [scorersOption]: "Gol atanlar" anahtarı gösterilsin mi.
Future<void> showPosterPreview({
  required BuildContext context,
  required Widget poster,
  required String fileName,
  List<String> imageUrls = const [],
  String? shareText,
  String? leagueId,
  String? seasonId,
  PosterKind? kind,
  String title = 'Afişi Paylaş',
  List<PosterFormat> formats = const [PosterFormat.story],
  bool scorersOption = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _PosterPreviewDialog(
      poster: poster,
      fileName: fileName,
      imageUrls: imageUrls,
      shareText: shareText,
      leagueId: leagueId,
      seasonId: seasonId,
      kind: kind,
      title: title,
      formats: formats,
      scorersOption: scorersOption,
    ),
  );
}

class _PosterPreviewDialog extends StatefulWidget {
  const _PosterPreviewDialog({
    required this.poster,
    required this.fileName,
    required this.imageUrls,
    required this.title,
    required this.formats,
    required this.scorersOption,
    this.shareText,
    this.leagueId,
    this.seasonId,
    this.kind,
  });

  final Widget poster;
  final String fileName;
  final List<String> imageUrls;
  final String title;
  final List<PosterFormat> formats;
  final bool scorersOption;
  final String? shareText;
  final String? leagueId;
  final String? seasonId;
  final PosterKind? kind;

  @override
  State<_PosterPreviewDialog> createState() => _PosterPreviewDialogState();
}

class _PosterPreviewDialogState extends State<_PosterPreviewDialog> {
  final _boundaryKey = GlobalKey();
  late final Future<void> _ready = _prepare();
  bool _sharing = false;
  bool _saving = false;

  late PosterFormat _format = widget.formats.first;
  bool _plain = false;
  bool _scorers = true;

  /// Turnuvanın afiş arka planı; yoksa afiş kendi zeminini çizer.
  ImageProvider? _background;

  bool get _plainOption => widget.kind != null;

  Future<void> _prepare() async {
    final (_, bgUrl, _) = await (
      GoogleFonts.pendingFonts(),
      widget.kind == null
          ? Future<String?>.value()
          : PosterBackgrounds.resolve(
              kind: widget.kind!,
              leagueId: widget.leagueId,
              seasonId: widget.seasonId,
            ),
      _loadPrefs(),
    ).wait;
    if (!mounted) return;
    var ok = true;
    final bg = bgUrl == null ? null : NetworkImage(bgUrl);
    await Future.wait([
      // Afiş zemini PNG'ye çizilmeden önce hazır olsun.
      precacheImage(kDefaultPosterPhoto, context),
      if (bg != null) precacheImage(bg, context, onError: (_, _) => ok = false),
      for (final u in widget.imageUrls.where((u) => u.trim().isNotEmpty))
        precacheImage(NetworkImage(u), context, onError: (_, _) {}),
    ]);
    // Görsel inmezse varsayılan zemin kullanılır.
    if (bg != null && ok) _background = bg;
  }

  /// Son seçilen boyut / zemin / gol atanlar (cihazda).
  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final f = PosterFormat.values
          .where((e) => e.name == p.getString(_kPrefFormat))
          .firstOrNull;
      _plain = _plainOption && (p.getBool(_kPrefPlain) ?? false);
      _scorers = p.getBool(_kPrefScorers) ?? true;
      if (f != null && widget.formats.contains(f)) _format = f;
    } catch (_) {
      // Tercih okunamazsa varsayılanlar kullanılır.
    }
  }

  Future<void> _savePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (widget.formats.length > 1) {
        await p.setString(_kPrefFormat, _format.name);
      }
      if (_plainOption) await p.setBool(_kPrefPlain, _plain);
      if (widget.scorersOption) await p.setBool(_kPrefScorers, _scorers);
    } catch (_) {}
  }

  void _set(VoidCallback change) {
    setState(change);
    _savePrefs();
  }

  /// Afişi seçili boyutta PNG'ye çevirir (önizleme küçültülmüş olabilir;
  /// RepaintBoundary afişin kendi boyutunda çizer, 3x ile 1080 genişlik).
  Future<Uint8List> _png() async {
    final boundary =
        _boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _kPixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw Exception('Afiş oluşturulamadı.');
    return data.buffer.asUint8List();
  }

  String get _name =>
      '${widget.fileName}${_format == PosterFormat.post ? '_gonderi' : ''}';

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final bytes = await _png();
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, mimeType: 'image/png', name: '$_name.png'),
          ],
          fileNameOverrides: ['$_name.png'],
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

  /// Telefonda galeriye kaydeder; web'de PNG dosyası olarak indirir.
  Future<void> _download() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final bytes = await _png();
      if (kIsWeb) {
        await XFile.fromData(
          bytes,
          mimeType: 'image/png',
          name: '$_name.png',
        ).saveTo('$_name.png');
        messenger.showSnackBar(const SnackBar(content: Text('Afiş indirildi.')));
      } else {
        if (!await Gal.hasAccess(toAlbum: false)) {
          await Gal.requestAccess(toAlbum: false);
        }
        await Gal.putImageBytes(bytes, name: _name);
        messenger.showSnackBar(
          const SnackBar(content: Text('Afiş galeriye kaydedildi.')),
        );
      }
    } on GalException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.type == GalExceptionType.accessDenied
                ? 'Galeriye kaydetmek için fotoğraf izni gerekli.'
                : 'Kaydedilemedi: ${e.type.message}',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _segment<T>({
    required String label,
    required List<T> values,
    required T selected,
    required String Function(T) title,
    String Function(T)? subtitle,
    required ValueChanged<T> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            label,
            style: const TextStyle(
              color: kAdminMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Row(
          children: [
            for (var i = 0; i < values.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Material(
                  color: values[i] == selected
                      ? kAdminAccent.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.04),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: values[i] == selected
                          ? kAdminAccent
                          : Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _busy ? null : () => onChanged(values[i]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Column(
                        children: [
                          Text(
                            title(values[i]),
                            style: TextStyle(
                              color: values[i] == selected
                                  ? Colors.white
                                  : Colors.white70,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle(values[i]),
                              style: const TextStyle(
                                color: kAdminMuted,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  bool get _busy => _sharing || _saving;

  @override
  Widget build(BuildContext context) {
    final size = _format.size;
    final maxH =
        MediaQuery.sizeOf(context).height *
        (widget.formats.length > 1 || _plainOption ? 0.42 : 0.6);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: AdminDialogCloseOverlay(
        onClose: _busy ? null : () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: adminDialogDecoration(),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminDialogHeader(
                  icon: Icons.ios_share_rounded,
                  title: widget.title,
                  subtitle: widget.formats.length > 1
                      ? 'Instagram gönderisi ya da hikâyesi'
                      : 'Instagram hikâyesi için 1080×1920',
                ),
                const SizedBox(height: 12),
                if (widget.formats.length > 1) ...[
                  _segment<PosterFormat>(
                    label: 'BOYUT',
                    values: widget.formats,
                    selected: _format,
                    title: (f) => f.label,
                    subtitle: (f) => f.pixels,
                    onChanged: (f) => _set(() => _format = f),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_plainOption) ...[
                  _segment<bool>(
                    label: 'ZEMİN',
                    values: const [false, true],
                    selected: _plain,
                    title: (v) => v ? 'Sade' : 'Fotoğraf',
                    onChanged: (v) => _set(() => _plain = v),
                  ),
                  const SizedBox(height: 6),
                ],
                if (widget.scorersOption)
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                    dense: true,
                    value: _scorers,
                    activeTrackColor: kAdminAccent,
                    onChanged: _busy ? null : (v) => _set(() => _scorers = v),
                    title: const Text(
                      'Gol atanlar',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                FutureBuilder<void>(
                  future: _ready,
                  builder: (context, snap) {
                    final done = snap.connectionState == ConnectionState.done;
                    return ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxH),
                      child: AspectRatio(
                        aspectRatio: size.width / size.height,
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
                                      size: size,
                                      child: PosterOptions(
                                        style: PosterStyle(
                                          format: _format,
                                          plain: _plain,
                                          showScorers: _scorers,
                                        ),
                                        child: PosterBackground(
                                          image: _plain ? null : _background,
                                          child: widget.poster,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                AdminPrimaryButton(
                  label: 'PAYLAŞ',
                  icon: Icons.ios_share_rounded,
                  busy: _sharing,
                  onPressed: _busy ? null : _share,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _download,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded),
                    label: Text(kIsWeb ? 'İNDİR' : 'TELEFONA İNDİR'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
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
          fontWeight: FontWeight.w800,
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
