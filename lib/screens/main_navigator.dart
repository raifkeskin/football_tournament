import 'package:flutter/material.dart';

import 'groups_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'stats_screen.dart';

/// Alt menü çubuğu ve dört ana ekran arasında geçiş.
class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _aktifSekme = 0;

  /// Sekme sırasıyla eşleşen ekranlar; [IndexedStack] ile durum korunur.
  static const List<Widget> _ekranlar = [
    HomeScreen(),
    GroupsScreen(),
    StatsScreen(),
    ProfileScreen(),
  ];

  void _sekmeDegistir(int index) {
    setState(() => _aktifSekme = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _aktifSekme,
        children: _ekranlar,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _aktifSekme,
        onTap: _sekmeDegistir,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Ana Sayfa',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.groups_outlined),
            activeIcon: Icon(Icons.groups),
            label: 'Gruplar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            activeIcon: Icon(Icons.bar_chart),
            label: 'İstatistik',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
