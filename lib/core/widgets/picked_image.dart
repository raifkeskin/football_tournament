import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/logo_background.dart';

/// Bellekte üretilmiş (dosyası olmayan) resimlerin baytları.
final _memoryBytes = Expando<Uint8List>();

/// Seçilen (henüz yüklenmemiş) resmin önizlemesi. Web'de `XFile.path` bir
/// blob adresidir ve `Image.file` çalışmaz; orada ağ resmi olarak okunur.
ImageProvider pickedImageProvider(XFile file) {
  final bytes = _memoryBytes[file];
  if (bytes != null) return MemoryImage(bytes);
  return kIsWeb ? NetworkImage(file.path) : FileImage(File(file.path));
}

/// Seçilen logonun arka planını hemen temizler; önizleme yüklenecek hâli
/// gösterir. Temizlenecek bir şey yoksa ya da hata olursa aynı dosya döner.
Future<XFile> preparePickedLogo(XFile picked) async {
  try {
    final png = await compute(removeLogoBackground, await picked.readAsBytes());
    if (png == null) return picked;
    final file = XFile.fromData(png, name: 'logo.png', mimeType: 'image/png');
    _memoryBytes[file] = png;
    return file;
  } catch (e) {
    debugPrint('Logo arka planı kaldırılamadı: $e');
    return picked;
  }
}
