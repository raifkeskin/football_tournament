import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/logo_background.dart';

/// Resimlerin hangi klasöre yükleneceği (storage kuralları klasöre göre
/// yetki verir).
enum MediaFolder { leagues, teams, players, news, matches }

/// Resim yükleme işlemleri için soyut arayüz.
abstract class ImageUploadService {
  /// Yükler ve herkese açık linki döner. Hata olursa nedenini içeren bir
  /// Exception fırlatır (ör. dosya çok büyük).
  ///
  /// Görsel seçiciden gelen [XFile] baytları okunur; mobilde ve web'de aynı
  /// şekilde çalışır (dosya sistemi kullanılmaz).
  Future<String?> uploadImage(XFile image, {required MediaFolder folder});

  /// Eski resmi siler. Sadece bizim depomuzdaki linkler silinir; eski
  /// ImgBB linkleri ve boş değerler sessizce atlanır.
  Future<void> deleteImageByUrl(String? url);
}

/// Supabase Storage `media` bucket'ı (bkz. 20261002100000_media_storage.sql).
class SupabaseImageUploadService implements ImageUploadService {
  SupabaseImageUploadService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const bucket = 'media';
  final SupabaseClient _client;

  static String _contentType(String ext) => switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    _ => 'image/jpeg',
  };

  /// Kenarı en fazla [_maxSide] piksel olacak şekilde küçültür ve sıkıştırır.
  /// PNG'ler şeffaflık kaybolmasın diye PNG kalır, diğerleri JPEG olur.
  /// Telefon kamerasından gelen 5-10 MB'lık resimler ~200-500 KB'a iner.
  /// Web'de sıkıştırma eklentisi yok; resim olduğu gibi yüklenir.
  static const _maxSide = 1600;
  static const _maxPngBytes = 1536 * 1024;

  static String _extOf(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    if (ext == 'jpeg') return 'jpg';
    return const ['jpg', 'png', 'webp', 'gif'].contains(ext) ? ext : 'jpg';
  }

  Future<(Uint8List, String)> _shrink(Uint8List bytes, String srcExt) async {
    if (kIsWeb) return (bytes, srcExt);
    try {
      Future<Uint8List> compress(CompressFormat format) =>
          FlutterImageCompress.compressWithList(
            bytes,
            minWidth: _maxSide,
            minHeight: _maxSide,
            quality: 82,
            format: format,
          );

      if (srcExt == 'png') {
        // Fotoğraf içerikli PNG küçültülse de MB'larca kalır; o zaman JPEG.
        final png = await compress(CompressFormat.png);
        if (png.length <= _maxPngBytes) return (png, 'png');
      }
      return (await compress(CompressFormat.jpeg), 'jpg');
    } catch (e) {
      debugPrint('Resim sıkıştırılamadı, orijinal yükleniyor: $e');
      return (bytes, srcExt);
    }
  }

  /// Takım/turnuva logolarının beyaz arka planı şeffaf yapılır. Silinecek
  /// arka plan yoksa ya da işlem başarısızsa `null` döner.
  Future<Uint8List?> _logoWithoutBackground(Uint8List bytes) async {
    try {
      return await compute(removeLogoBackground, bytes);
    } catch (e) {
      debugPrint('Logo arka planı kaldırılamadı, orijinal yükleniyor: $e');
      return null;
    }
  }

  @override
  Future<String?> uploadImage(
    XFile image, {
    required MediaFolder folder,
  }) async {
    final original = await image.readAsBytes();
    final isLogo = folder == MediaFolder.teams || folder == MediaFolder.leagues;
    final logoPng = isLogo ? await _logoWithoutBackground(original) : null;
    final (bytes, ext) = logoPng != null
        ? (logoPng, 'png')
        : await _shrink(original, _extOf(image.name));

    // Web'de (JS) `1 << 32` sıfır olur ve nextInt hata verir; 31 bit yeterli.
    final rand = Random().nextInt(0x7fffffff).toRadixString(16);
    final path =
        '${folder.name}/${DateTime.now().millisecondsSinceEpoch}_$rand.$ext';
    try {
      await _client.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: _contentType(ext),
              cacheControl: '31536000', // dosya adı benzersiz; 1 yıl önbellek
            ),
          );
      return _client.storage.from(bucket).getPublicUrl(path);
    } on StorageException catch (e) {
      debugPrint('Storage yükleme hatası: $e');
      if (e.statusCode == '413') {
        throw Exception('Resim çok büyük (en fazla 5 MB).');
      }
      throw Exception('Resim yüklenemedi: ${e.message}');
    }
  }

  /// Linkten bucket içindeki yolu çıkarır; bizim depomuz değilse null.
  static String? pathFromUrl(String? url) {
    final u = (url ?? '').trim();
    const marker = '/storage/v1/object/public/$bucket/';
    final i = u.indexOf(marker);
    if (i < 0) return null;
    final path = Uri.decodeComponent(u.substring(i + marker.length));
    return path.isEmpty ? null : path.split('?').first;
  }

  @override
  Future<void> deleteImageByUrl(String? url) async {
    final path = pathFromUrl(url);
    if (path == null) return;
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (e) {
      // Silinemeyen eski dosya kaydı bozmaz; sadece logla.
      debugPrint('Storage silme hatası: $e');
    }
  }
}
