import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'id_card.dart';

/// Canlı tarayıcıdan dönüş: okunan anahtar ya da kullanıcının seçtiği yol.
class MrzScanResult {
  const MrzScanResult.key(IdCardKey this.key) : fallback = null;
  const MrzScanResult.fallback(String this.fallback) : key = null;

  final IdCardKey? key;

  /// 'photo' (fotoğraf çek) ya da 'manual' (elle gir).
  final String? fallback;
}

/// Kimliğin arka yüzünü canlı kamerayla okur: her karede alttaki 3 satır
/// telefonda tanınır; sağlama haneleri tutan aynı sonuç art arda iki karede
/// gelince kamera kapanır. Görüntü kaydedilmez, sunucuya gitmez.
class MrzScannerScreen extends StatefulWidget {
  const MrzScannerScreen({super.key});

  @override
  State<MrzScannerScreen> createState() => _MrzScannerScreenState();
}

class _MrzScannerScreenState extends State<MrzScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  bool _busy = false;
  bool _done = false;
  bool _torch = false;
  String? _error;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastKey;

  /// Okunan satırlar var ama sağlama tutmadı: kullanıcıya "yaklaştırın".
  bool _seeing = false;

  /// Kamera açılıyor: arka plandan dönüşte ikinci bir kamera açılmasın.
  bool _starting = false;

  static const _blue = Color(0xFF38BDF8);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop(rebuild: false);
    _recognizer.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_done) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stop();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _start();
    }
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final c = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await c.initialize();
      try {
        await c.setFocusMode(FocusMode.auto);
      } catch (_) {}
      // Açılırken ekran kapandıysa ya da uygulama arka plana alındıysa
      // önizleme hiç gösterilmez.
      final state = WidgetsBinding.instance.lifecycleState;
      if (!mounted || _done || state != AppLifecycleState.resumed) {
        await c.dispose();
        return;
      }
      _camera = back;
      setState(() {
        _controller = c;
        _error = null;
      });
      await c.startImageStream(_onFrame);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e.code.contains('Access')
            ? 'Kamera izni verilmedi. Telefon ayarlarından Lig Masası için '
                  'kamera iznini açın ya da bilgileri elle girin.'
            : 'Kamera açılamadı. Fotoğraf çekerek ya da elle deneyin.',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Kamera açılamadı. Fotoğraf çekerek ya da elle deneyin.',
        );
      }
    } finally {
      _starting = false;
    }
  }

  /// Önizleme önce ekrandan kaldırılır, sonra kamera kapatılır: kapanmış
  /// kameraya önizleme çizdirilirse "Disposed CameraController" hatası olur.
  Future<void> _stop({bool rebuild = true}) async {
    final c = _controller;
    if (c == null) return;
    if (rebuild && mounted) {
      setState(() => _controller = null);
      await WidgetsBinding.instance.endOfFrame;
    } else {
      _controller = null;
    }
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    try {
      await c.dispose();
    } catch (_) {}
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _done) return;
    final now = DateTime.now();
    if (now.difference(_last).inMilliseconds < 250) return;
    _busy = true;
    _last = now;
    try {
      final input = _inputImage(image);
      if (input == null) return;
      final text = await _recognizer.processImage(input);
      final key = parseIdCardMrz(text.text);
      final seeing = text.text.contains('<<');
      if (mounted && seeing != _seeing) setState(() => _seeing = seeing);
      if (key == null) {
        _lastKey = null;
        return;
      }
      final sig = '${key.documentNumber}|${key.birthDate}|${key.expiryDate}';
      // Aynı sonuç iki karede: tek karelik yanlış okuma elenir.
      if (_lastKey != sig) {
        _lastKey = sig;
        return;
      }
      _done = true;
      HapticFeedback.mediumImpact();
      await _stop();
      if (mounted) Navigator.of(context).pop(MrzScanResult.key(key));
    } catch (_) {
      // Tek kare okunamadı; sonraki kare denenir.
    } finally {
      _busy = false;
    }
  }

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImage? _inputImage(CameraImage image) {
    final cam = _camera;
    final c = _controller;
    if (cam == null || c == null) return null;
    final sensor = cam.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensor);
    } else {
      final dev = _orientations[c.value.deviceOrientation] ?? 0;
      rotation = InputImageRotationValue.fromRawValue(
        (sensor - dev + 360) % 360,
      );
    }
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (rotation == null || format == null || image.planes.length != 1) {
      return null;
    }
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _toggleTorch() async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      setState(() => _torch = !_torch);
    } catch (_) {}
  }

  void _fallback(String kind) {
    _done = true;
    Navigator.of(context).pop(MrzScanResult.fallback(kind));
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (c != null && c.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: c.value.previewSize?.height ?? 1,
                height: c.value.previewSize?.width ?? 1,
                child: CameraPreview(c),
              ),
            )
          else if (_error == null)
            const Center(child: CircularProgressIndicator(color: _blue)),
          if (_error == null) _overlay(context),
          if (_error != null) _errorView(),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: 'Kapat',
                  ),
                  const Spacer(),
                  if (c != null)
                    IconButton(
                      onPressed: _toggleTorch,
                      icon: Icon(
                        _torch
                            ? Icons.flashlight_on_rounded
                            : Icons.flashlight_off_rounded,
                        color: _torch ? _blue : Colors.white,
                      ),
                      tooltip: 'Fener',
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Kart biçimli çerçeve; dışı karartılır. Alttaki 3 satırın yeri
  /// çerçevede gösterilir.
  Widget _overlay(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width - 40;
    final h = w / 1.586; // kimlik kartı oranı
    return Column(
      children: [
        const Spacer(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Kimliğin arka yüzünü çerçeveye hizalayın',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _seeing ? _blue : Colors.white, width: 3),
          ),
          alignment: Alignment.bottomCenter,
          child: Container(
            height: h * 0.36,
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (_seeing ? _blue : Colors.white).withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '<<<  alttaki 3 satır  <<<',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _seeing
              ? 'Okunuyor… kartı sabit tutun'
              : 'Kart otomatik algılanır, fotoğraf çekmenize gerek yok',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _seeing ? _blue : Colors.white70,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        _bottomButtons(),
      ],
    );
  }

  Widget _bottomButtons() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextButton.icon(
              onPressed: () => _fallback('photo'),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Fotoğraf çek'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: () => _fallback('manual'),
              icon: const Icon(Icons.keyboard_alt_outlined),
              label: const Text('Elle gir'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            color: Colors.white54,
            size: 48,
          ),
          const SizedBox(height: 14),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14.5),
          ),
          const SizedBox(height: 18),
          _bottomButtons(),
        ],
      ),
    ),
  );
}
