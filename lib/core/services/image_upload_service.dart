import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resimlerin hangi klasöre yükleneceği (storage kuralları klasöre göre
/// yetki verir).
enum MediaFolder { leagues, teams, players, news, matches }

/// Resim yükleme işlemleri için soyut arayüz.
abstract class ImageUploadService {
  /// Yükler ve herkese açık linki döner. Hata olursa nedenini içeren bir
  /// Exception fırlatır (ör. dosya çok büyük).
  Future<String?> uploadImage(File image, {required MediaFolder folder});

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
  static const _maxSide = 1600;
  static const _maxPngBytes = 1536 * 1024;

  Future<(File, String)> _shrink(File image) async {
    final dot = image.path.lastIndexOf('.');
    final srcExt = dot < 0 ? '' : image.path.substring(dot + 1).toLowerCase();
    try {
      final tmp = await getTemporaryDirectory();
      Future<File?> compress(String ext, CompressFormat format) async {
        final out = await FlutterImageCompress.compressAndGetFile(
          image.absolute.path,
          '${tmp.path}/up_${DateTime.now().microsecondsSinceEpoch}.$ext',
          minWidth: _maxSide,
          minHeight: _maxSide,
          quality: 82,
          format: format,
        );
        return out == null ? null : File(out.path);
      }

      if (srcExt == 'png') {
        // Fotoğraf içerikli PNG küçültülse de MB'larca kalır; o zaman JPEG.
        final png = await compress('png', CompressFormat.png);
        if (png != null && await png.length() <= _maxPngBytes) {
          return (png, 'png');
        }
      }
      final jpg = await compress('jpg', CompressFormat.jpeg);
      if (jpg != null) return (jpg, 'jpg');
    } catch (e) {
      debugPrint('Resim sıkıştırılamadı, orijinal yükleniyor: $e');
    }
    final fallbackExt = const ['jpg', 'jpeg', 'png', 'webp', 'gif']
            .contains(srcExt)
        ? (srcExt == 'jpeg' ? 'jpg' : srcExt)
        : 'jpg';
    return (image, fallbackExt);
  }

  @override
  Future<String?> uploadImage(File image, {required MediaFolder folder}) async {
    final (file, ext) = await _shrink(image);
    final rand = Random().nextInt(1 << 32).toRadixString(16);
    final path =
        '${folder.name}/${DateTime.now().millisecondsSinceEpoch}_$rand.$ext';
    try {
      await _client.storage
          .from(bucket)
          .upload(
            path,
            file,
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
