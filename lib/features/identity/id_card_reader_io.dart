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

  /// Çipi okur: önce PACE (destekliyorsa), olmazsa BAC. [onStatus] okuma
  /// adımlarını bildirir (Android ekranı; iPhone'da sistem penceresi).
  static Future<IdCardData> readChip(
    IdCardKey key, {
    void Function(String status)? onStatus,
  }) async {
    final nfc = NfcProvider();
    Future<void> connect() => nfc.connect(
      timeout: const Duration(seconds: 45),
      iosAlertMessage: 'Kimlik kartını telefonun arkasına yaklaştırın',
    );

    try {
      onStatus?.call('Kartı telefonun arkasına yaklaştırın');
      await connect();
      if (!nfc.isConnected()) {
        throw const IdCardError('Kart algılanamadı. Tekrar deneyin.');
      }
      onStatus?.call('Okunuyor, kartı oynatmayın…');
      await nfc.setIosAlertMessage('Okunuyor, kartı oynatmayın…');

      var passport = Passport(nfc);
      EfCardAccess? cardAccess;
      try {
        cardAccess = await passport.readEfCardAccess();
      } catch (_) {}

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

      final dg1 = await passport.readEfDG1();
      final mrz = dg1.mrz;
      final tc = tcFromText([mrz.optionalData, mrz.optionalData2 ?? '']);
      if (tc == null) {
        throw const IdCardError('Kartta kimlik numarası bulunamadı.');
      }
      await nfc.disconnect(iosAlertMessage: 'Kimlik okundu');
      return IdCardData(
        firstName: mrz.firstName.trim(),
        lastName: mrz.lastName.trim(),
        birthDate: mrz.dateOfBirth,
        tc: tc,
      );
    } on IdCardError catch (e) {
      await _close(nfc, e.message);
      rethrow;
    } catch (e) {
      final timeout =
          e.toString().contains('408') ||
          e.toString().toLowerCase().contains('timeout');
      final msg = timeout
          ? 'Kart algılanamadı. Kartı telefonun arkasına (kameranın '
                'altına) yaslayıp tekrar deneyin.'
          : 'Okuma yarıda kaldı. Kartı okuma bitene kadar oynatmadan '
                'tutun ve tekrar deneyin.';
      await _close(nfc, msg);
      throw IdCardError(msg);
    }
  }

  static Future<void> _close(NfcProvider nfc, String message) async {
    try {
      await nfc.disconnect(iosErrorMessage: message);
    } catch (_) {}
  }
}
