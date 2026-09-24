import 'package:flutter/material.dart';
import 'dart:ui'; // Cam efekti (BackdropFilter) için eklendi

import '../../match/screens/fixture_screen.dart';
import '../../team/screens/groups_screen.dart';
import 'home_screen.dart';
import '../../player/screens/profile_screen.dart';
import '../../player/screens/stats_screen.dart';

/// Sol yan menü (Drawer) ile dört ana ekran arasında geçiş.
class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  late int _aktifSekme = widget.initialTabIndex;

  void _sekmeDegistir(int index) {
    setState(() {
      _aktifSekme = index;
    });
    // Menüden bir sayfa seçildiğinde çekmeceyi (Drawer) otomatik kapat
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ekranlar = <Widget>[
      const HomeScreen(),
      const FixtureScreen(),
      const GroupsScreen(),
      const StatsScreen(),
      ProfileScreen(
        onRequestHomeTab: () {
          setState(() {
            _aktifSekme = 0;
          });
        },
      ),
    ];

    // Menü Seçenekleri Tanımlaması
    final menuItems = const [
      ('Ana Sayfa', Icons.home_outlined),
      ('Fikstür', Icons.calendar_month_outlined),
      ('Gruplar', Icons.groups_outlined),
      ('İstatistik', Icons.bar_chart_outlined),
      ('Profil', Icons.person_outline),
    ];

    return Scaffold(
      extendBody: true,

      // SOL YAN MENÜ (DRAWER) ENTEGRASYONU
      drawer: Drawer(
        backgroundColor:
            Colors.transparent, // Arka plan şeffaf (Cam efekti için gerekli)
        elevation: 0,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 12.0,
            sigmaY: 12.0,
          ), // Cam efekti bulanıklığı
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1E293B), // Üst sol lacivert
                  Color(0xFF064E3B), // Alt sağ koyu zümrüt yeşili
                ],
              ),
              border: Border(
                right: BorderSide(
                  color: Colors.white.withOpacity(
                    0.1,
                  ), // Menü ile ekran arasına ince şık çizgi
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // MENÜ ÜST KISMI (Logo veya Kullanıcı Bilgisi)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.1),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.sports_soccer,
                            size: 36,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Master Class Lig',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hoş Geldiniz',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Divider(color: Colors.white.withOpacity(0.15), height: 1),
                  const SizedBox(height: 16),

                  // MENÜ LİSTESİ (Sayfalar)
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: menuItems.length,
                      itemBuilder: (context, index) {
                        final isSelected = _aktifSekme == index;
                        final label = menuItems[index].$1;
                        final icon = menuItems[index].$2;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: isSelected
                                ? const Color(0xFF10B981).withOpacity(0.15)
                                : Colors.transparent,
                            border: isSelected
                                ? Border.all(
                                    color: const Color(
                                      0xFF10B981,
                                    ).withOpacity(0.5),
                                    width: 1,
                                  )
                                : Border.all(color: Colors.transparent),
                          ),
                          child: ListTile(
                            leading: Icon(
                              icon,
                              color: isSelected
                                  ? const Color(0xFF10B981)
                                  : Colors.white70,
                              size: 26,
                            ),
                            title: Text(
                              label,
                              style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFF10B981)
                                    : Colors.white,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            onTap: () => _sekmeDegistir(index),
                          ),
                        );
                      },
                    ),
                  ),

                  // ÇIKIŞ YAP BUTONU
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withOpacity(0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.logout, size: 20),
                      label: const Text(
                        'Çıkış Yap',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        // TODO: Çıkış yapma işlemleri (Auth servisi ile) buraya eklenebilir.
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      // ANA EKRAN GÖSTERİMİ
      body: IndexedStack(index: _aktifSekme, children: ekranlar),
    );
  }
}
