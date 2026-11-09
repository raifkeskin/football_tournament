import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Videoyu WhatsApp'ta BELGE olarak paylaşır (video olarak gidince WhatsApp
/// kaliteyi düşürüyor; belge olarak dosya olduğu gibi gider). Sohbet
/// WhatsApp'ın kendi ekranında seçilir. Android'de WhatsApp doğrudan açılır
/// (MainActivity.kt); iOS ve web'de sistemin paylaş menüsü açılır.
class WhatsAppShare {
  WhatsAppShare._();

  static const _channel = MethodChannel('ligmasasi/instagram');

  /// iPad'de paylaş menüsünün çıkacağı yer (düğmenin alanı).
  static Rect? originOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  static Future<void> shareVideo(
    Uint8List mp4, {
    Rect? origin,
    String name = 'gol.mp4',
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final ok = await _channel
          .invokeMethod<bool>('whatsapp', {'bytes': mp4})
          .catchError((_) => false);
      if (ok == true) return;
    }
    await SharePlus.instance.share(
      ShareParams(
        // Video türü yerine genel dosya türü: WhatsApp belge olarak alır.
        files: [
          XFile.fromData(mp4, mimeType: 'application/octet-stream', name: name),
        ],
        sharePositionOrigin: origin,
      ),
    );
  }
}
