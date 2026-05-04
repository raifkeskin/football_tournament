import 'package:flutter/material.dart';

class FootballScaffold extends StatelessWidget {
  final String headerImage; // Üstteki stad/çim resmi
  final String? bodyImage;  // Alttaki panel resmi (Opsiyonel)
  final Widget body;        // Ekranın asıl içeriği
  final String? title;      // AppBar başlığı
  final List<Widget>? actions; // Sağ üst butonlar
  final Widget? floatingActionButton;

  const FootballScaffold({
    super.key,
    required this.headerImage,
    required this.body,
    this.bodyImage,
    this.title,
    this.actions,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, // AppBar'ın arkasına resim geçmesi için
      appBar: title != null 
        ? AppBar(
            title: Text(title!, style: const TextStyle(fontWeight: FontWeight.w900)),
            centerTitle: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: actions,
          ) 
        : null,
      floatingActionButton: floatingActionButton,
      body: Stack(
        children: [
          // 1. KATMAN: Arka Plan Resmi (Tüm ekranı kaplayan veya Header olan)
          Positioned.fill(
            child: Image.asset(headerImage, fit: BoxFit.cover),
          ),
          // 2. KATMAN: Karartma Gradient (Okunabilirlik için)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.4),
                    const Color(0xFF0F172A).withOpacity(0.9),
                  ],
                ),
              ),
            ),
          ),
          // 3. KATMAN: İçerik
          SafeArea(
            bottom: false,
            child: bodyImage != null 
              ? Column(
                  children: [
                    const SizedBox(height: 120), // Header boşluğu
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withOpacity(0.8),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                          image: DecorationImage(
                            image: AssetImage(bodyImage!),
                            fit: BoxFit.cover,
                            opacity: 0.1, // Alt resim çok baskın olmasın diye
                          ),
                        ),
                        child: body,
                      ),
                    ),
                  ],
                )
              : body, // Alt panel istenmezse doğrudan body basılır
          ),
        ],
      ),
    );
  }
}