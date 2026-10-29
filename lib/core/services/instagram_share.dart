import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Görseli telefondaki Instagram uygulamasında açar: hikâye düzenleyicisi
/// (müzik, çıkartma) ya da gönderi ekranı (açıklama). Paylaşım Instagram'da o
/// an açık olan hesaptan yapılır. Android (MainActivity.kt) ve iOS
/// (AppDelegate.swift); web'de [isAvailable] false döner. iOS'ta hikâye için
/// Facebook App ID gerekir, yoksa gönderi yolu açılır.
class InstagramShare {
  InstagramShare._();

  static const _channel = MethodChannel('ligmasasi/instagram');

  /// Meta uygulamasının (LigMasasi Yayın) Facebook App ID'si; Instagram
  /// hikâye paylaşımında kaynağı belirtir. Boşsa gönderilmez.
  static const _facebookAppId = '2164236947498221';

  static Future<bool>? _available;

  /// Instagram yüklü mü (bir kez sorulur).
  static Future<bool> isAvailable() {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return Future.value(false);
    }
    return _available ??= _channel
        .invokeMethod<bool>('isInstalled')
        .then((v) => v ?? false)
        .catchError((_) => false);
  }

  /// PNG'yi Instagram'da açar; açılamazsa false.
  static Future<bool> share(Uint8List png, {required bool story}) async {
    final ok = await _channel.invokeMethod<bool>('share', {
      'bytes': png,
      'story': story,
      'appId': _facebookAppId,
    });
    return ok ?? false;
  }
}
