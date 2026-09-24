import 'package:flutter/material.dart';

class MasterClassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MasterClassAppBar({
    super.key,
    required this.title,
    this.actions, // Sağ tarafa eklenebilecek esnek butonlar (takvim vb.)
    this.bottom,  // Altına eklenebilecek özel alanlar (tarih şeridi vb.)
  });

  final String title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      // Tüm sayfalarda ortak olan sol menü (Hamburger) tetikleyicisi
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu, color: Colors.white, size: 28),
          onPressed: () {
            ScaffoldState? scaffold = Scaffold.maybeOf(ctx);
            if (scaffold != null && !scaffold.hasDrawer) {
              scaffold = scaffold.context.findAncestorStateOfType<ScaffoldState>();
            }
            scaffold?.openDrawer();
          },
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      actions: actions,
      bottom: bottom,
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0.0));
}