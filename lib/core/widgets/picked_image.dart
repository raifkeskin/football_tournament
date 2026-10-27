import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/logo_background.dart';
import 'admin_form.dart';
import 'admin_page.dart';

/// Bellekte üretilmiş (dosyası olmayan) resimlerin baytları.
final _memoryBytes = Expando<Uint8List>();

/// Kullanıcının logo için seçtiği hâl: 'clean' (arka planı temizlenmiş) ya
/// da 'original'. Yükleme bu seçime uyar, yeniden temizlemez.
final _logoChoice = Expando<String>();

/// Seçilen (henüz yüklenmemiş) resmin önizlemesi. Web'de `XFile.path` bir
/// blob adresidir ve `Image.file` çalışmaz; orada ağ resmi olarak okunur.
ImageProvider pickedImageProvider(XFile file) {
  final bytes = _memoryBytes[file];
  if (bytes != null) return MemoryImage(bytes);
  return kIsWeb ? NetworkImage(file.path) : FileImage(File(file.path));
}

/// Bellekte hazırlanmış (ör. standarda getirilmiş) PNG logo. Yükleme onu
/// olduğu gibi gönderir, yeniden işlemez.
XFile preparedLogoFile(Uint8List png) {
  final f = XFile.fromData(png, name: 'logo.png', mimeType: 'image/png');
  _memoryBytes[f] = png;
  _logoChoice[f] = 'clean';
  return f;
}

/// Logo yüklenirken: kullanıcı orijinali mi, temizlenmiş hâli mi seçti?
/// null: seçim yapılmadı (eski akış; yükleme kendisi temizler).
String? pickedLogoChoice(XFile file) => _logoChoice[file];

/// Seçilen logonun arka planını temizler ve iki hâli yan yana gösterip
/// hangisinin kalacağını sorar. Temizlenecek bir şey yoksa orijinal döner.
/// Pencere kapatılırsa `null` (logo değişmez).
///
/// Temizleme kenardan dolgu yapar; logonun çerçevesinde boşluk varsa
/// içteki beyazlar da silinebilir. Bu yüzden seçim kullanıcıya bırakılır.
Future<XFile?> preparePickedLogo(BuildContext context, XFile picked) async {
  Uint8List? png;
  Uint8List? original;
  try {
    original = await picked.readAsBytes();
    png = await compute(removeLogoBackground, original);
  } catch (e) {
    debugPrint('Logo arka planı kaldırılamadı: $e');
  }
  if (png == null || original == null || !context.mounted) {
    _logoChoice[picked] = 'original';
    return picked;
  }
  final cleaned = XFile.fromData(png, name: 'logo.png', mimeType: 'image/png');
  _memoryBytes[cleaned] = png;
  _logoChoice[cleaned] = 'clean';
  _memoryBytes[picked] = original;
  _logoChoice[picked] = 'original';

  return showDialog<XFile>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: AdminDialogCloseOverlay(
        onClose: () => Navigator.pop(ctx),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
          decoration: adminDialogDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminDialogHeader(
                icon: Icons.auto_fix_high_rounded,
                title: 'Logo Görünümü',
                subtitle: 'Uygulamada hangisi kullanılsın?',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _LogoOption(
                      bytes: png!,
                      label: 'Arka Planı Temiz',
                      hint: 'Zemin şeffaf',
                      onTap: () => Navigator.pop(ctx, cleaned),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LogoOption(
                      bytes: original!,
                      label: 'Orijinal',
                      hint: 'Olduğu gibi',
                      onTap: () => Navigator.pop(ctx, picked),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Temizlemede logonun içindeki beyaz alanlar da silinebilir. '
                'Bozuk görünüyorsa orijinali seçin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kAdminMuted, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Seçim kutusu: logo, uygulamadaki koyu zeminde nasıl görünecekse öyle.
class _LogoOption extends StatelessWidget {
  const _LogoOption({
    required this.bytes,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  final Uint8List bytes;
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0F172A),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kAdminAccent.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kAdminMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bellekte kesilmiş (kadrajı ayarlanmış) JPEG fotoğraf; önizleme web'de de
/// baytlardan okunur.
XFile preparedPhotoFile(Uint8List jpg) {
  final f = XFile.fromData(jpg, name: 'photo.jpg', mimeType: 'image/jpeg');
  _memoryBytes[f] = jpg;
  return f;
}
