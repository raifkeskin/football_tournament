import 'package:flutter/material.dart';

import '../../match/screens/fixture_screen.dart';
import '../../team/screens/groups_screen.dart';
import 'home_screen.dart';
import '../../player/screens/profile_screen.dart';
import '../../player/screens/stats_screen.dart';

/// Alt menü çubuğu ve dört ana ekran arasında geçiş.
class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  late int _aktifSekme = widget.initialTabIndex;
  bool _isBarVisible = true;

  void _sekmeDegistir(int index) {
    setState(() => _aktifSekme = index);
  }

  void _toggleBar() {
    setState(() => _isBarVisible = !_isBarVisible);
  }

  @override
  Widget build(BuildContext context) {
    final ekranlar = <Widget>[
      const HomeScreen(),
      const FixtureScreen(),
      const GroupsScreen(),
      const StatsScreen(),
      ProfileScreen(onRequestHomeTab: () => _sekmeDegistir(0)),
    ];

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(index: _aktifSekme, children: ekranlar),
          _HideShowBarButton(
            isBarVisible: _isBarVisible,
            onTap: _toggleBar,
          ),
          _FloatingNavBar(
            currentIndex: _aktifSekme,
            onTap: _sekmeDegistir,
            isBarVisible: _isBarVisible,
          ),
        ],
      ),
    );
  }
}

class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({
    required this.currentIndex,
    required this.onTap,
    required this.isBarVisible,
  });

  final int currentIndex;
  final void Function(int index) onTap;
  final bool isBarVisible;

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF1E293B);
    const active = Color(0xFF10B981);
    const inactive = Color(0xFF64748B);
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    const visibleBottom = 30.0;
    final items = const [
      ('Ana Sayfa', Icons.home_outlined),
      ('Fikstür', Icons.calendar_month_outlined),
      ('Gruplar', Icons.groups_outlined),
      ('İstatistik', Icons.bar_chart_outlined),
      ('Profil', Icons.person_outline),
    ];

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      left: 20,
      right: 20,
      bottom: isBarVisible ? (visibleBottom + bottomPad) : (-110 + bottomPad),
      child: Material(
        color: Colors.transparent,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(40),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 16,
                offset: Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(items.length, (i) {
              final selected = i == currentIndex;
              final color = selected ? active : inactive;
              final (label, icon) = items[i];
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(32),
                  onTap: () => onTap(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: color, size: 24),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _HideShowBarButton extends StatelessWidget {
  const _HideShowBarButton({
    required this.isBarVisible,
    required this.onTap,
  });

  final bool isBarVisible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      right: 18,
      bottom: isBarVisible ? (30 + bottomPad + 74) : (18 + bottomPad),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: isBarVisible ? 0.95 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 14,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(
                isBarVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
