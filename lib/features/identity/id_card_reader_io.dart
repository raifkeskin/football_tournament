import 'dart:async' show TimeoutException;
import 'dart:io' show File, Platform;

import 'package:dmrtd/dmrtd.dart';
import 'package:flutter/material.dart'
    show BuildContext, MaterialPageRoute, Navigator;
import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'id_card.dart';
import 'mrz_scanner_io.dart';

/// Kimlik kartı okuyucu (Android / iOS): arka yüz kamerayla, çip NFC ile.
/// Kimliğin fotoğrafı yalnız telefonda işlenir ve hemen silinir.
class IdCardReader {
  IdCardReader._();

  static const supported = true;
  static const _channel = MethodChannel('ligmasasi/nfc');

  static Future<NfcState> nfcState() async {
    try {
      switch (await FlutterNfcKit.nfcAvailability) {
        case NFCAvailability.available:
          return NfcState.available;
        case NFCAvailability.disabled:
          return NfcState.disabled;
        case NFCAvailability.not_supported:
          return NfcState.unsupported;
      }
    } catch (_) {
      return NfcState.unsupported;
    }
  }

  /// Android: telefonun NFC ayarı açılır. iPhone'da NFC hep açıktır.
  static Future<bool> openNfcSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Canlı kamerayla arka yüz: kart algılanınca kamera kendiliğinden
  /// kapanır. Dönüş: okunan anahtar, ya da kullanıcının seçtiği yol
  /// ('photo' / 'manual'); kapatılırsa null.
  static Future<({IdCardKey? key, String? fallback})?> scanLive(
    BuildContext context,
  ) async {
    final r = await Navigator.of(context).push<MrzScanResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const MrzScannerScreen(),
      ),
    );
    if (r == null) return null;
    return (key: r.key, fallback: r.fallback);
  }

  /// Arka yüzün fotoğrafı çekilir, alttaki 3 satır telefonda okunur.
  /// Vazgeçilirse null; okunamazsa [IdCardError].
  static Future<IdCardKey?> scanBackSide() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      maxWidth: 2400,
      imageQuality: 95,
    );
    if (picked == null) return null;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final text = await recognizer.processImage(
        InputImage.fromFilePath(picked.path),
      );
      final key = parseIdCardMrz(text.text);
      if (key == null) {
        throw const IdCardError(
          'Arka yüzdeki alt satırlar okunamadı. Kartı düz tutup, alttaki '
          '3 satır net görünecek şekilde yeniden çekin ya da bilgileri '
          'elle girin.',
        );
      }
      return key;
    } finally {
      await recognizer.close();
      // Kimliğin fotoğrafı saklanmaz.
      try {
        await File(picked.path).delete();
      } catch (_) {}
    }
  }

  /// NFC anteni telefonun üst kısmında mı (iPhone) yoksa ortada mı.
  static bool get antennaTop => Platform.isIOS;

  /// Kartın nereye konacağı: iPhone'un NFC anteni üst kenarda (kameranın
  /// yanında); Android'de çoğunlukla arka ortada.
  static String get placementHint => Platform.isIOS
      ? 'Kartı iPhone\'un arkasında üst kısma, kameranın hemen altına düz '
            'yaslayın'
      : 'Kimliğinizi telefonun arkasına, tam ortaya düz yaslayın';

  /// Okuma yarıda koparsa (kart kaydı, temas kesildi) bu kadar kez kendi
  /// kendine yeniden denenir; kullanıcı baştan başlamak zorunda kalmaz.
  static const _attempts = 3;

  /// Kart bu kadar kez [_pollWindow] içinde algılanmazsa okuma bırakılır
  /// (kullanıcıya çipsiz devam seçeneği sunulur).
  static const detectTries = 3;

  /// Tek arama turu: kart bu sürede algılanmazsa arama yeniden başlar.
  static const _pollWindow = Duration(seconds: 5);

  /// Çipi okur: önce PACE (destekliyorsa), olmazsa BAC. [onStatus] okuma
  /// adımlarını, [onProgress] ilerlemeyi (0-1) bildirir (Android ekranı;
  /// iPhone'da sistem penceresinde yüzde yazar). [onSearching] kart
  /// aranırken deneme sırasını (1..[detectTries]) bildirir. Kart 5 sn'de
  /// algılanmazsa arama yeniden başlar; [detectTries] denemede de
  /// algılanmazsa [IdCardNotDetected]. Bağlantı koparsa [_attempts] kez
  /// yeniden denenir.
  static Future<IdCardData> readChip(
    IdCardKey key, {
    void Function(String status)? onStatus,
    void Function(double progress)? onProgress,
    void Function(int attempt)? onSearching,
  }) async {
    var interrupts = 0;
    var searches = 0;
    var resumed = false;
    while (true) {
      if (!resumed) {
        searches++;
        onSearching?.call(searches);
        onStatus?.call(
          searches == 1
              ? placementHint
              : searches < detectTries
              ? 'Kimlik algılanamadı, yeniden deneniyor ($searches/$detectTries)'
              : 'Son deneme ($searches/$detectTries)',
        );
      }
      try {
        return await _readChipOnce(
          key,
          resumed: resumed,
          onStatus: onStatus,
          onProgress: onProgress,
        );
      } on _NotDetected {
        if (resumed || searches >= detectTries) {
          throw const IdCardNotDetected();
        }
      } on _ReadInterrupted {
        interrupts++;
        if (interrupts >= _attempts) {
          throw const IdCardError(
            'Okuma yarıda kaldı. Kartı okuma bitene kadar oynatmadan, '
            'telefona tam yaslı tutun ve tekrar deneyin.',
          );
        }
        resumed = true;
        onProgress?.call(0);
        onStatus?.call('Bağlantı koptu, yeniden deneniyor… kartı sabit tutun');
      }
    }
  }

  static Future<IdCardData> _readChipOnce(
    IdCardKey key, {
    required bool resumed,
    void Function(String status)? onStatus,
    void Function(double progress)? onProgress,
  }) async {
    final nfc = NfcProvider();
    var detected = false;
    Future<void> step(double p) async {
      onProgress?.call(p);
      try {
        await nfc.setIosAlertMessage(
          'Okunuyor %${(p * 100).round()} · kartı oynatmayın',
        );
      } catch (_) {}
    }

    // Kart 5 sn içinde algılanmazsa arama kapatılır (_NotDetected).
    // iPhone'da zaman aşımı sistem penceresine uygulanmadığından burada
    // kesilir ve pencere kapatılır.
    Future<void> connect() async {
      if (Platform.isAndroid) {
        try {
          return await nfc.connect(timeout: _pollWindow);
        } catch (e) {
          if (_isTimeout(e)) throw const _NotDetected();
          rethrow;
        }
      }
      final f = nfc.connect(
        timeout: _pollWindow,
        iosAlertMessage: resumed
            ? 'Bağlantı koptu. Kartı aynı yere sabit tutun, yeniden okunuyor.'
            : '$placementHint ve okuma bitene kadar oynatmayın.',
      );
      try {
        await f.timeout(_pollWindow);
      } on TimeoutException {
        f.ignore();
        try {
          await FlutterNfcKit.finish(iosErrorMessage: 'Kimlik algılanamadı');
        } catch (_) {}
        throw const _NotDetected();
      } catch (e) {
        if (_isTimeout(e)) throw const _NotDetected();
        rethrow;
      }
    }

    try {
      await connect();
      if (!nfc.isConnected()) {
        throw const IdCardError('Kart algılanamadı. Tekrar deneyin.');
      }
      detected = true;
      onStatus?.call('Okunuyor, kartı oynatmayın…');
      await step(0.1);

      var passport = Passport(nfc);
      EfCardAccess? cardAccess;
      try {
        cardAccess = await passport.readEfCardAccess();
      } catch (_) {}
      await step(0.25);

      var opened = false;
      if (cardAccess != null) {
        try {
          await passport.startSessionPACE(
            DBAKey(
              key.documentNumber,
              key.birthDate,
              key.expiryDate,
              paceMode: true,
            ),
            cardAccess,
          );
          opened = true;
        } catch (_) {
          // PACE olmadı: bağlantıyı yenileyip BAC ile denenir.
          await nfc.disconnect();
          await connect();
          passport = Passport(nfc);
        }
      }
      if (!opened) {
        // OCR seri no adayları sırayla denenir.
        final docs = [key.documentNumber, ...key.alternatives];
        for (var i = 0; i < docs.length && !opened; i++) {
          try {
            await passport.startSession(
              DBAKey(docs[i], key.birthDate, key.expiryDate),
            );
            opened = true;
          } on PassportError {
            if (i == docs.length - 1) {
              throw const IdCardError(
                'Kartın kilidi açılamadı. Seri no, doğum tarihi ve son '
                'geçerlilik tarihini kartın ön yüzüyle karşılaştırın.',
              );
            }
          }
        }
      }

      await step(0.6);
      final dg1 = await passport.readEfDG1();
      await step(0.95);
      final mrz = dg1.mrz;
      final tc = tcFromText([mrz.optionalData, mrz.optionalData2 ?? '']);
      if (tc == null) {
        throw const IdCardError('Kartta kimlik numarası bulunamadı.');
      }
      onProgress?.call(1);
      await nfc.disconnect(iosAlertMessage: 'Kimlik okundu');
      return IdCardData(
        firstName: mrz.firstName.trim(),
        lastName: mrz.lastName.trim(),
        birthDate: mrz.dateOfBirth,
        tc: tc,
      );
    } on _NotDetected {
      rethrow;
    } on IdCardError catch (e) {
      await _close(nfc, e.message);
      rethrow;
    } catch (e) {
      final timeout = _isTimeout(e);
      // Kart algılandı ama okuma koptu: sessizce kapatıp yeniden denenir.
      if (detected && !timeout) {
        try {
          await nfc.disconnect(
            iosErrorMessage: 'Bağlantı koptu, yeniden deneniyor',
          );
        } catch (_) {}
        throw const _ReadInterrupted();
      }
      final msg = timeout
          ? 'Kart algılanamadı. Kartı telefonun arkasına (kameranın '
                'altına) yaslayıp tekrar deneyin.'
          : 'Okuma yarıda kaldı. Kartı okuma bitene kadar oynatmadan '
                'tutun ve tekrar deneyin.';
      await _close(nfc, msg);
      throw IdCardError(msg);
    }
  }

  static bool _isTimeout(Object e) {
    final s = e.toString();
    return s.contains('408') || s.toLowerCase().contains('timeout');
  }

  static Future<void> _close(NfcProvider nfc, String message) async {
    try {
      await nfc.disconnect(iosErrorMessage: message);
    } catch (_) {}
  }
}

/// Kart arama süresinde algılanmadı.
class _NotDetected implements Exception {
  const _NotDetected();
}

/// Kart algılandıktan sonra okuma koptu (yeniden denenecek).
class _ReadInterrupted implements Exception {
  const _ReadInterrupted();
}
