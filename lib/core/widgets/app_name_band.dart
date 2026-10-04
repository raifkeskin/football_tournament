import 'package:flutter/material.dart';

import 'tvl_logo.dart';

/// Uygulama adı.
const kAppName = 'Türk Veteranlar Ligi';

/// Tüm ekranların en üstündeki uygulama adı bandı. Durum çubuğu boşluğunu
/// bant üstlenir; altındaki ekranlara üst boşluk verilmez (çift boşluk
/// olmasın).
class AppNameBand extends StatelessWidget {
  const AppNameBand({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          // Yeşil bant: solda logo (yazıdan büyük), yanında uygulama adı.
          // Yazı tipi uygulamaya gömülü (pubspec fonts).
          Container(
            padding: EdgeInsets.only(top: top),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF064E3B),
                  Color(0xFF10B981),
                  Color(0xFF064E3B),
                ],
              ),
              border: Border(
                bottom: BorderSide(color: Colors.white, width: 1.5),
              ),
            ),
            child: const SizedBox(
              height: 50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  TvlLogo(size: 46, ringText: true),
                  SizedBox(width: 12),
                  Text(
                    'TÜRK VETERANLAR LİGİ',
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'BarlowCondensed',
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontSize: 18,
                      letterSpacing: 2.6,
                      decoration: TextDecoration.none,
                      shadows: [
                        Shadow(color: Color(0x66000000), blurRadius: 4),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
