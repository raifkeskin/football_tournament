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

    // YENİ MENÜ LİSTESİ: İkon ve Resim yolları eklendi
    final menuItems = [
      {'label': 'Ana Sayfa', 'icon': Icons.home_outlined, 'image': 'assets/anasayfa.jpg'}, // Mevcut ana sayfa resmin
      {'label': 'Fikstür', 'icon': Icons.calendar_month_outlined, 'image': 'assets/images/admin_fixture.jpg'},
      {'label': 'Puan Durumu', 'icon': Icons.groups_outlined, 'image': 'assets/images/admin_team.jpg'},
      {'label': 'İstatistik', 'icon': Icons.bar_chart_outlined, 'image': 'assets/images/admin_tournament.jpg'},
      {'label': 'Profil', 'icon': Icons.person_outline, 'image': 'assets/images/admin_license.jpg'},
    ];

    return Scaffold(
      extendBody: true,
      drawer: Drawer(
        backgroundColor: Colors.transparent, 
        elevation: 0,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
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
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // MENÜ ÜST KISMI
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.1),
                            border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                          ),
                          child: const Icon(Icons.sports_soccer, size: 36, color: Colors.white),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Master Lig',
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

                  // YENİ RESİMLİ MENÜ KARTLARI
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: menuItems.length,
                      itemBuilder: (context, index) {
                        final item = menuItems[index];
                        final isSelected = _aktifSekme == index;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _DrawerImageMenuCard(
                            title: item['label'] as String,
                            icon: item['icon'] as IconData,
                            imagePath: item['image'] as String,
                            isSelected: isSelected,
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.logout, size: 20),
                      label: const Text('Çıkış Yap', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () {
                        // Çıkış yapma işlemleri
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: IndexedStack(index: _aktifSekme, children: ekranlar),
    );
  }
}

// YAN MENÜ İÇİN ÖZEL RESİMLİ KART WIDGET'I
class _DrawerImageMenuCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String imagePath;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerImageMenuCard({
    required this.title,
    required this.icon,
    required this.imagePath,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64, // Admin panelindeki 80'den biraz daha ince, menüye tam uyar
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? const Color(0xFF10B981) : Colors.white.withOpacity(0.1),
          width: isSelected ? 1.5 : 1.0,
        ),
        boxShadow: isSelected
            ? [BoxShadow(color: const Color(0xFF10B981).withOpacity(0.3), blurRadius: 8)]
            : const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
        image: DecorationImage(
          image: AssetImage(imagePath),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(isSelected ? 0.6 : 0.8), // Seçili olan biraz daha aydınlık
            BlendMode.darken,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF10B981).withOpacity(0.2) : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: isSelected ? const Color(0xFF10B981) : Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? const Color(0xFF10B981) : Colors.white,
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF10B981), size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}