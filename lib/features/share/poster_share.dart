import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/instagram_share.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/utils/in_app_browser.dart';
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
/// PNG'yi telefonun paylaşım menüsüne, "Instagram" seçili boyuta göre
/// Instagram'ın hikâye ya da gönderi ekranına (yalnız Android, Instagram
/// yüklüyse), "Telefona indir" galeriye (web'de dosya olarak) kaydeder.
/// Seçimler cihazda hatırlanır.
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
///
/// [photoPoster] verilirse afiş seçilen fotoğrafla çizilir ve pencerede
/// "Fotoğraf seç" çıkar: galeriden seçilen fotoğraf yalnız bu afişte
/// kullanılır, hiçbir yere kaydedilmez. Başlangıçta [photoUrl] (ör.
/// oyuncunun profil fotoğrafı) kullanılır.
Future<void> showPosterPreview({
  required BuildContext context,
  Widget? poster,
  Widget Function(ImageProvider? photo)? photoPoster,
  String? photoUrl,
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
      photoPoster: photoPoster,
      photoUrl: photoUrl,
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
    required this.photoPoster,
    required this.photoUrl,
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

  final Widget? poster;
  final Widget Function(ImageProvider? photo)? photoPoster;
  final String? photoUrl;
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
  bool _instagramBusy = false;

  /// İndirme bitti: düğme birkaç saniye "KAYDEDİLDİ" gösterir (galeriye
  /// kayıt bildirim üretmediği için kullanıcı çalışmadı sanmasın).
  bool _saved = false;
  Timer? _savedTimer;
  late final Future<bool> _instagram = InstagramShare.isAvailable();

  /// Pencerenin altında gösterilen sonuç (snackbar popup'ın arkasında
  /// kalıyordu).
  ({String text, bool error, bool gallery})? _notice;

  void _say(String text, {bool error = false, bool gallery = false}) {
    if (mounted) {
      setState(() => _notice = (text: text, error: error, gallery: gallery));
    }
  }

  void _flashSaved() {
    HapticFeedback.mediumImpact();
    _savedTimer?.cancel();
    setState(() => _saved = true);
    _savedTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  @override
  void dispose() {
    _savedTimer?.cancel();
    super.dispose();
  }

  late PosterFormat _format = widget.formats.first;

  /// Fotoğraflı afişte kullanılan fotoğraf; [_picked] seçildiyse o.
  late final ImageProvider? _profile =
      (widget.photoUrl ?? '').trim().isEmpty
      ? null
      : NetworkImage(widget.photoUrl!.trim());
  ImageProvider? _picked;
  ImageProvider? get _photo => _picked ?? _profile;

  Future<void> _pickPhoto() async {
    try {
      final f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );
      if (f == null || !mounted) return;
      final image = MemoryImage(await f.readAsBytes());
      if (!mounted) return;
      await precacheImage(image, context);
      if (mounted) setState(() => _picked = image);
    } catch (e) {
      _say('Fotoğraf açılamadı: $e', error: true);
    }
  }
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
      if (_profile != null)
        precacheImage(_profile, context, onError: (_, _) {}),
    ]);
    // Görsel inmezse varsayılan zemin kullanılır. Kayıtlı boyut (gönderi /
    // hikâye) da burada okunduğu için bütün ekran yeniden çizilir; yoksa
    // düğmeler eski boyutu, afiş yeni boyutu gösteriyordu.
    if (!mounted) return;
    setState(() {
      if (bg != null && ok) _background = bg;
    });
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
    setState(() {
      _sharing = true;
      _notice = null;
    });
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
      _say('Paylaşılamadı: $e', error: true);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Afişi Instagram'da açar: Hikâye boyutunda hikâye düzenleyicisi
  /// (müzik, çıkartma), Gönderi boyutunda gönderi ekranı (açıklama).
  Future<void> _shareInstagram() async {
    setState(() {
      _instagramBusy = true;
      _notice = null;
    });
    try {
      final bytes = await _png();
      final ok = await InstagramShare.share(
        bytes,
        story: _format == PosterFormat.story,
      );
      if (!ok) _say('Instagram açılamadı.', error: true);
    } catch (e) {
      _say('Instagram\'a aktarılamadı: $e', error: true);
    } finally {
      if (mounted) setState(() => _instagramBusy = false);
    }
  }

  /// Telefonda galeriye kaydeder; web'de PNG dosyası olarak indirir.
  /// Instagram vb. uygulamaların içindeki tarayıcı indirmeyi sessizce
  /// engellediği için orada indirme denenmez, ne yapılacağı yazılır.
  Future<void> _download() async {
    final inApp = kIsWeb ? inAppBrowserName() : null;
    if (inApp != null) {
      _say(
        '$inApp içindeki tarayıcı dosya indirmeye izin vermiyor. Sağ üstteki '
        '⋮ menüsünden "Tarayıcıda aç" deyip orada indirin.',
        error: true,
      );
      return;
    }
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      final bytes = await _png();
      if (kIsWeb) {
        await XFile.fromData(
          bytes,
          mimeType: 'image/png',
          name: '$_name.png',
        ).saveTo('$_name.png');
        _say('İndirme başlatıldı: $_name.png (İndirilenler klasörü).');
        _flashSaved();
      } else {
        if (!await Gal.hasAccess(toAlbum: false)) {
          await Gal.requestAccess(toAlbum: false);
        }
        await Gal.putImageBytes(bytes, name: _name);
        _say('Afiş galeriye kaydedildi.', gallery: true);
        _flashSaved();
      }
    } on GalException catch (e) {
      _say(
        e.type == GalExceptionType.accessDenied
            ? 'Galeriye kaydetmek için fotoğraf izni gerekli.'
            : 'Kaydedilemedi: ${e.type.message}',
        error: true,
      );
    } catch (e) {
      _say('Kaydedilemedi: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Pencerenin alt düğmeleri (İndir, Paylaş, Instagram) — dar, yan yana.
  Widget _actionButton({
    required String label,
    required IconData icon,
    required bool busy,
    required VoidCallback onTap,
    required BoxDecoration decoration,
  }) {
    return Opacity(
      opacity: _busy && !busy ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          height: 46,
          decoration: decoration,
          child: InkWell(
            onTap: _busy ? null : onTap,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _segment<T>({
    required List<T> values,
    required T selected,
    required String Function(T) title,
    String Function(T)? subtitle,
    required ValueChanged<T> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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

  bool get _busy => _sharing || _saving || _instagramBusy;

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
                // Başlık yok; sağ üstteki kapat düğmesine yer.
                const SizedBox(height: 34),
                if (widget.formats.length > 1) ...[
                  _segment<PosterFormat>(
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
                    dense: false,
                    value: _scorers,
                    activeTrackColor: kAdminAccent,
                    onChanged: _busy ? null : (v) => _set(() => _scorers = v),
                    title: const Text(
                      'Gol atanlar gösterilsin',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                if (widget.photoPoster != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _pickPhoto,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('FOTOĞRAF SEÇ'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(44),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      if (_picked != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _picked = null),
                            style: TextButton.styleFrom(
                              foregroundColor: kAdminAccent,
                              minimumSize: const Size.fromHeight(44),
                            ),
                            child: Text(
                              _profile == null
                                  ? 'FOTOĞRAFI KALDIR'
                                  : 'PROFİL FOTOĞRAFI',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
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
                                          child:
                                              widget.photoPoster?.call(
                                                _photo,
                                              ) ??
                                              widget.poster ??
                                              const SizedBox(),
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
                if (_notice != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        _notice!.error
                            ? Icons.info_outline_rounded
                            : Icons.check_circle_rounded,
                        size: 18,
                        color: _notice!.error
                            ? const Color(0xFFFBBF24)
                            : kAdminAccent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _notice!.text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                      if (_notice!.gallery)
                        TextButton(
                          onPressed: () => Gal.open(),
                          child: const Text(
                            'GALERİDE AÇ',
                            style: TextStyle(
                              color: kAdminAccent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                FutureBuilder<bool>(
                  future: _instagram,
                  builder: (context, snap) {
                    final instagram = snap.data == true;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _actionButton(
                                label: _saved ? 'KAYDEDİLDİ' : 'İNDİR',
                                icon: _saved
                                    ? Icons.check_circle_rounded
                                    : Icons.download_rounded,
                                busy: _saving,
                                onTap: _download,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.04),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.25),
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _actionButton(
                                label: 'PAYLAŞ',
                                icon: Icons.ios_share_rounded,
                                busy: _sharing,
                                onTap: _share,
                                decoration: BoxDecoration(
                                  color: kAdminAccent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            if (instagram) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: _actionButton(
                                  label: 'INSTAGRAM',
                                  icon: Icons.camera_alt_outlined,
                                  busy: _instagramBusy,
                                  onTap: _shareInstagram,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFF58529),
                                        Color(0xFFDD2A7B),
                                        Color(0xFF8134AF),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (instagram)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
                            child: Text(
                              'Instagram ${_format == PosterFormat.story ? 'hikâyesi' : 'gönderisi'} '
                              'olarak açılır; o an açık olan hesaptan paylaşılır.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: kAdminMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tüm afişlerin altındaki imza: uygulama logosu ve yanında "LİG MASASI".
class PosterAppMark extends StatelessWidget {
  const PosterAppMark({super.key});

  @override
  Widget build(BuildContext context) {
    final st = PosterOptions.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AppLogo(size: st.pick(26, 20)),
        const SizedBox(width: 7),
        Text(
          'LİG MASASI',
          style: GoogleFonts.barlowCondensed(
            fontSize: st.pick(14, 12),
            color: Colors.white70,
            fontWeight: FontWeight.w800,
            fontStyle: FontStyle.italic,
            letterSpacing: 2,
          ),
        ),
      ],
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
