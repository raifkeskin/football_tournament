import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resimlerin hangi klasöre yükleneceği (storage kuralları klasöre göre
/// yetki verir).
enum MediaFolder { leagues, teams, players, news, matches }

/// Resim yükleme işlemleri için soyut arayüz.
abstract class ImageUploadService {
  /// Yükler ve herkese açık linki döner; hata olursa null.
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

  @override
  Future<String?> uploadImage(File image, {required MediaFolder folder}) async {
    try {
      final dot = image.path.lastIndexOf('.');
      var ext = dot < 0 ? 'jpg' : image.path.substring(dot + 1).toLowerCase();
      if (ext == 'jpeg') ext = 'jpg';
      if (!const ['jpg', 'png', 'webp', 'gif'].contains(ext)) ext = 'jpg';
      final rand = Random().nextInt(1 << 32).toRadixString(16);
      final path =
          '${folder.name}/${DateTime.now().millisecondsSinceEpoch}_$rand.$ext';
      await _client.storage
          .from(bucket)
          .upload(
            path,
            image,
            fileOptions: FileOptions(
              contentType: _contentType(ext),
              cacheControl: '31536000', // dosya adı benzersiz; 1 yıl önbellek
            ),
          );
      return _client.storage.from(bucket).getPublicUrl(path);
    } catch (e) {
      debugPrint('Storage yükleme hatası: $e');
      return null;
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
