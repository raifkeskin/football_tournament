import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/logo_background.dart';

/// Resimlerin hangi klasöre yükleneceği (storage kuralları klasöre göre
/// yetki verir).
enum MediaFolder {
  leagues('leagues'),
  teams('teams'),
  players('players'),
  news('news'),
  matches('matches'),

  /// Turnuva sponsorlarının logoları.
  sponsors('sponsors'),

  /// Futbolcunun onay bekleyen profil fotoğrafları:
  /// `profile_requests/<auth uid>/` (yalnızca kendi klasörüne yükleyebilir).
  profileRequests('profile_requests'),

  /// Yöneticilerin profil fotoğrafı: `staff/<auth uid>/` (yalnızca kendi
  /// klasörü).
  staff('staff');

  const MediaFolder(this.path);

  final String path;
}

/// Resim yükleme işlemleri için soyut arayüz.
abstract class ImageUploadService {
  /// Yükler ve herkese açık linki döner. Hata olursa nedenini içeren bir
  /// Exception fırlatır (ör. dosya çok büyük).
  ///
  /// Görsel seçiciden gelen [XFile] baytları okunur; mobilde ve web'de aynı
  /// şekilde çalışır (dosya sistemi kullanılmaz).
  ///
  /// [subfolder] verilirse dosya `<folder>/<subfolder>/` altına konur.
  Future<String?> uploadImage(
    XFile image, {
    required MediaFolder folder,
    String? subfolder,
  });

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
  /// Web'de eklenti yok; aynı işlem saf Dart `image` paketiyle yapılır.
  static const _maxSide = 1600;

  /// Oyuncu / profil / yönetici fotoğrafları küçük yuvarlaklarda ve kartta
  /// görünür: 512 piksel yeterli (~30-60 KB).
  static const _maxSidePortrait = 512;

  /// Takım/turnuva logoları en büyük açılış ekranında ~170 px görünür;
  /// 384 piksel keskin kalır, dosya 512'ye göre ~%45 küçük olur.
  static const _maxSideLogo = 384;

  static int _maxSideFor(MediaFolder f) => switch (f) {
    MediaFolder.players ||
    MediaFolder.profileRequests ||
    MediaFolder.staff => _maxSidePortrait,
    MediaFolder.teams ||
    MediaFolder.leagues ||
    MediaFolder.sponsors => _maxSideLogo,
    _ => _maxSide,
  };

  /// Web: decode → kenarı [maxSide]'a indir → JPEG (PNG şeffafsa PNG).
  static (Uint8List, String)? _shrinkPure(
    Uint8List bytes,
    String srcExt,
    int maxSide, {
    bool forceJpeg = false,
  }) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    var im = img.bakeOrientation(decoded);
    if (im.width > maxSide || im.height > maxSide) {
      im = im.width >= im.height
          ? img.copyResize(im, width: maxSide)
          : img.copyResize(im, height: maxSide);
    }
    if (!forceJpeg && srcExt == 'png' && im.hasAlpha) {
      final png = img.encodePng(im, level: 6);
      if (png.length <= _maxPngBytes) return (png, 'png');
    }
    return (img.encodeJpg(im, quality: 82), 'jpg');
  }

  static const _maxPngBytes = 1536 * 1024;

  static String _extOf(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    if (ext == 'jpeg') return 'jpg';
    return const ['jpg', 'png', 'webp', 'gif'].contains(ext) ? ext : 'jpg';
  }

  Future<(Uint8List, String)> _shrink(
    Uint8List bytes,
    String srcExt, {
    int maxSide = _maxSide,
    bool forceJpeg = false,
  }) async {
    if (kIsWeb) {
      try {
        final out = _shrinkPure(bytes, srcExt, maxSide, forceJpeg: forceJpeg);
        // Küçültme dosyayı büyütürse (zaten küçük resim) orijinal kalır;
        // JPEG zorunluysa (haber) her zaman dönüştürülmüş hali.
        if (out != null && (forceJpeg || out.$1.length < bytes.length)) {
          return out;
        }
      } catch (e) {
        debugPrint('Resim küçültülemedi, orijinal yükleniyor: $e');
      }
      return (bytes, srcExt);
    }
    try {
      Future<Uint8List> compress(CompressFormat format) =>
          FlutterImageCompress.compressWithList(
            bytes,
            minWidth: maxSide,
            minHeight: maxSide,
            quality: 82,
            format: format,
          );

      if (srcExt == 'png' && !forceJpeg) {
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
    String? subfolder,
  }) async {
    final original = await image.readAsBytes();
    final isLogo =
        folder == MediaFolder.teams ||
        folder == MediaFolder.leagues ||
        folder == MediaFolder.sponsors;
    final logoPng = isLogo ? await _logoWithoutBackground(original) : null;
    final (bytes, ext) = logoPng != null
        ? (logoPng, 'png')
        : await _shrink(
            original,
            _extOf(image.name),
            maxSide: _maxSideFor(folder),
            // Haber fotoğrafları Instagram'a da gidebilir: yalnız JPEG.
            forceJpeg: folder == MediaFolder.news,
          );

    // Web'de (JS) `1 << 32` sıfır olur ve nextInt hata verir; 31 bit yeterli.
    final rand = Random().nextInt(0x7fffffff).toRadixString(16);
    final dir = subfolder == null ? folder.path : '${folder.path}/$subfolder';
    final path = '$dir/${DateTime.now().millisecondsSinceEpoch}_$rand.$ext';
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
