import 'package:flutter/material.dart';

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
          // Kırmızı-beyaz bant; yazı tipi uygulamaya gömülü (pubspec fonts).
          Container(
            padding: EdgeInsets.only(top: top),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF8B0A1F),
                  Color(0xFFC8102E),
                  Color(0xFF8B0A1F),
                ],
              ),
              border: Border(
                bottom: BorderSide(color: Colors.white, width: 2),
              ),
            ),
            child: const SizedBox(
              height: 26,
              child: Center(
                child: Text(
                  'TÜRK VETERANLAR LİGİ',
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'BarlowCondensed',
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontSize: 15,
                    letterSpacing: 3,
                    decoration: TextDecoration.none,
                  ),
                ),
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
