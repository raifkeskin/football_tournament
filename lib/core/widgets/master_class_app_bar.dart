import 'package:flutter/material.dart';

class MasterClassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;

  const MasterClassAppBar({
    super.key,
    required this.title,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    // Sayfaya dışarıdan yönlendirmeyle (push) mi gelindiğini kontrol et
    final canPop = Navigator.canPop(context);

    return AppBar(
      backgroundColor: Colors.transparent, // Tüm sayfalarda ortak şeffaf üst bar
      elevation: 0,
      centerTitle: true,
      iconTheme: const IconThemeData(color: Colors.white),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 20,
        ),
      ),
      leading: Builder(
        builder: (ctx) => IconButton(
          // Yönlendirmeyle gelindiyse geri oku, normal sekmedeyse 3 çizgi (menü) göster
          icon: Icon(
            canPop ? Icons.arrow_back_ios_new_rounded : Icons.menu,
            color: Colors.white,
            size: 26,
          ),
          onPressed: () {
            if (canPop) {
              // Ana sayfadan vs. geldiysek önceki sayfaya güvenle dön
              Navigator.pop(ctx);
            } else {
              // YENİ VE KESİN ÇÖZÜM:
              // Önce en yakındaki Scaffold'u (Örn: Fikstür'ün kendi Scaffold'u) bul
              ScaffoldState? scaffold = Scaffold.maybeOf(ctx);
              
              // Eğer bu Scaffold'un bir yan menüsü (Drawer) yoksa, 
              // hiyerarşideki en üst root Scaffold'a (MainNavigator'a) çık!
              if (scaffold != null && !scaffold.hasDrawer) {
                scaffold = ctx.findRootAncestorStateOfType<ScaffoldState>();
              }
              
              if (scaffold != null && scaffold.hasDrawer) {
                scaffold.openDrawer();
              } else {
                // Güvenlik ağı: Hiçbir şekilde menü bulunamazsa ana sekmeye dön
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            }
          },
        ),
      ),
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}