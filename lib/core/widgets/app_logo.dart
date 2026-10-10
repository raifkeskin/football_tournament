import 'package:flutter/material.dart';

/// Lig Masası logosu: altın şeritli yeşil "LM" harfleri arasında stadyum ve
/// saha. Ana görsel design/app_logo_master.jpg; uygulama içi küçük kopyası
/// ve uygulama ikonları ondan üretilir (tool/render_app_icons_test.dart).
///
/// Açılış ekranında önceden yüklenir ([precache]); afiş gibi ekran dışı
/// çizimlerde de hazır olur.
///
/// Köşeler boyutla orantılı yuvarlanır (uygulama ikonu gibi). Görsel
/// yüklenene kadar aynı boyutta boş alan kalır (yerleşim kaymaz).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  static const asset = 'assets/images/app_logo.jpg';

  final double size;

  static Future<void> precache(BuildContext context) =>
      precacheImage(const AssetImage(asset), context);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Tek çözülmüş kopya (512 px) her boyutta ortak kullanılır; ilk
        // gösterimden sonra anında çizilir.
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
