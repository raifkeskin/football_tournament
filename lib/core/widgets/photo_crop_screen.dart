import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'admin_page.dart';
import 'picked_image.dart';

/// Profil fotoğrafının oranı: oyuncu kartındaki vesikalık (84×108).
const kPortraitPhotoAspect = 7 / 9;

/// Galeriden seçer ve kadraj ekranını açar; vazgeçilirse null.
Future<XFile?> pickAndCropPortraitPhoto(BuildContext context) async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return null;
  final bytes = await picked.readAsBytes();
  if (!context.mounted) return null;
  return cropPortraitPhoto(context, bytes);
}

/// Yüklenmiş fotoğrafın kadrajını yeniden ayarlar.
Future<XFile?> cropPortraitPhotoFromUrl(
  BuildContext context,
  String url,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) throw Exception('${res.statusCode}');
    if (!context.mounted) return null;
    return await cropPortraitPhoto(context, res.bodyBytes);
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Fotoğraf açılamadı. Yeniden seçin.')),
    );
    return null;
  }
}

/// Kadraj ekranı: fotoğraf sürüklenir, iki parmakla ya da kaydırıcıyla
/// yakınlaştırılır. Dikdörtgen çerçeve oyuncu kartını, içindeki daire yuvarlak
/// görünümleri gösterir. Kesilmiş JPEG döner.
Future<XFile?> cropPortraitPhoto(BuildContext context, Uint8List bytes) {
  return Navigator.of(context).push<XFile>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _PhotoCropScreen(bytes: bytes),
    ),
  );
}

class _PhotoCropScreen extends StatefulWidget {
  const _PhotoCropScreen({required this.bytes});

  final Uint8List bytes;

  @override
  State<_PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<_PhotoCropScreen> {
  static const _maxZoom = 5.0;

  Size? _image;
  bool _failed = false;
  bool _saving = false;

  Size _frame = Size.zero;
  double _zoom = 1;
  Offset _offset = Offset.zero; // Resmin sol üstü, çerçeveye göre.
  bool _placed = false;

  double _startZoom = 1;
  Offset _startFocal = Offset.zero;
  Offset _startOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      if (mounted) setState(() => _image = size);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  double get _baseScale =>
      math.max(_frame.width / _image!.width, _frame.height / _image!.height);

  double get _scale => _baseScale * _zoom;

  Offset _clamp(Offset o) {
    final w = _image!.width * _scale;
    final h = _image!.height * _scale;
    return Offset(
      o.dx.clamp(_frame.width - w, 0.0),
      o.dy.clamp(_frame.height - h, 0.0),
    );
  }

  /// [focal] (çerçeveye göre) altındaki nokta yerinde kalarak yakınlaştırır.
  void _zoomTo(double zoom, Offset focal, Offset fromOffset, double fromZoom) {
    final fromScale = _baseScale * fromZoom;
    final point = (focal - fromOffset) / fromScale;
    _zoom = zoom.clamp(1.0, _maxZoom);
    _offset = _clamp(focal - point * _scale);
  }

  void _place(Size frame) {
    if (_placed && frame == _frame) return;
    final old = _frame;
    _frame = frame;
    if (!_placed) {
      // İlk açılış: ortala, dikey fotoğrafta üstten biraz pay bırak.
      final w = _image!.width * _scale;
      final h = _image!.height * _scale;
      _offset = _clamp(Offset((frame.width - w) / 2, (frame.height - h) / 4));
      _placed = true;
    } else if (old.width > 0) {
      _offset = _clamp(_offset * (frame.width / old.width));
    }
  }

  Future<void> _save() async {
    final s = _scale;
    final rect = [
      -_offset.dx / s / _image!.width,
      -_offset.dy / s / _image!.height,
      _frame.width / s / _image!.width,
      _frame.height / s / _image!.height,
    ];
    setState(() => _saving = true);
    final out = await compute(_cropJpeg, (widget.bytes, rect));
    if (!mounted) return;
    if (out == null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Fotoğraf kesilemedi.')));
      return;
    }
    Navigator.of(context).pop(preparedPhotoFile(out));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Kadrajı ayarla'),
        actions: [
          TextButton(
            onPressed: _image == null || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Kaydet',
                    style: TextStyle(
                      color: kAdminAccent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ],
      ),
      body: _failed
          ? const Center(
              child: Text(
                'Fotoğraf açılamadı.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : _image == null
          ? const SizedBox.shrink()
          : SafeArea(child: _editor()),
    );
  }

  Widget _editor() {
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final maxW = math.min(c.maxWidth - 48, 420.0);
              final maxH = c.maxHeight - 32;
              var fw = maxW;
              var fh = fw / kPortraitPhotoAspect;
              if (fh > maxH) {
                fh = maxH;
                fw = fh * kPortraitPhotoAspect;
              }
              _place(Size(fw, fh));
              final origin = Offset(
                (c.maxWidth - fw) / 2,
                (c.maxHeight - fh) / 2,
              );
              final s = _scale;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (d) {
                  _startZoom = _zoom;
                  _startOffset = _offset;
                  _startFocal = d.localFocalPoint - origin;
                },
                onScaleUpdate: (d) => setState(() {
                  final focal = d.localFocalPoint - origin;
                  _zoomTo(
                    _startZoom * d.scale,
                    _startFocal,
                    _startOffset,
                    _startZoom,
                  );
                  _offset = _clamp(_offset + (focal - _startFocal));
                }),
                child: Stack(
                  children: [
                    Positioned(
                      left: origin.dx + _offset.dx,
                      top: origin.dy + _offset.dy,
                      width: _image!.width * s,
                      height: _image!.height * s,
                      child: Image.memory(
                        widget.bytes,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _FramePainter(
                            Rect.fromLTWH(origin.dx, origin.dy, fw, fh),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.zoom_out_rounded, color: Colors.white54),
              Expanded(
                child: Slider(
                  value: _zoom,
                  min: 1,
                  max: _maxZoom,
                  activeColor: kAdminAccent,
                  onChanged: (v) => setState(() {
                    final center = Offset(_frame.width / 2, _frame.height / 2);
                    _zoomTo(v, center, _offset, _zoom);
                  }),
                ),
              ),
              const Icon(Icons.zoom_in_rounded, color: Colors.white54),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Text(
            'Sürükleyerek kaydırın, iki parmakla büyütün. Çerçeve oyuncu '
            'kartında, daire yuvarlak fotoğraflarda görünen alandır.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// Çerçeve dışını karartır; çerçeveyi ve içindeki daireyi çizer.
class _FramePainter extends CustomPainter {
  _FramePainter(this.frame);

  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(frame, const Radius.circular(10));
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(r),
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
    // Yuvarlak görünümler fotoğrafın ortasındaki kareyi gösterir.
    canvas.drawCircle(
      frame.center,
      frame.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.frame != frame;
}

/// Kesme işi: oranlar (x, y, w, h) resmin yönü düzeltilmiş boyutuna göre.
Uint8List? _cropJpeg((Uint8List, List<double>) args) {
  final (bytes, r) = args;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final im = img.bakeOrientation(decoded);
  final x = (r[0] * im.width).round().clamp(0, im.width - 1);
  final y = (r[1] * im.height).round().clamp(0, im.height - 1);
  final w = (r[2] * im.width).round().clamp(1, im.width - x);
  final h = (r[3] * im.height).round().clamp(1, im.height - y);
  var out = img.copyCrop(im, x: x, y: y, width: w, height: h);
  if (out.height > 1000) out = img.copyResize(out, height: 1000);
  return img.encodeJpg(out, quality: 88);
}
