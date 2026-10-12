import 'package:flutter/material.dart';

/// Lig Masası logosu: zeminsiz yuvarlak LM arması (altın halka, LİG MASASI
/// yazısı, ortada krem-altın LM), saydam PNG; bulunduğu zeminin rengi
/// arkadan görünür. Kaynak design/app_logo_crest.png; bu kopya ve uygulama
/// ikonları ondan üretilir (tool/render_app_icons_test.dart).
///
/// Açılış ekranında önceden yüklenir ([precache]); afiş gibi ekran dışı
/// çizimlerde de hazır olur.
///
/// Görsel yüklenene kadar aynı boyutta boş alan kalır (yerleşim kaymaz).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  static const asset = 'assets/images/app_logo.png';

  final double size;

  static Future<void> precache(BuildContext context) =>
      precacheImage(const AssetImage(asset), context);

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      // Tek çözülmüş kopya (512 px) her boyutta ortak kullanılır; ilk
      // gösterimden sonra anında çizilir.
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    );
  }
}
