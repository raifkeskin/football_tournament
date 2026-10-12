import 'package:flutter/material.dart';

import 'admin_form.dart';
import 'app_name_band.dart';
import 'master_class_app_bar.dart';

// Yönetim ekranlarının ortak renkleri
const kAdminBg = Color(0xFF0F172A);
const kAdminAccent = Color(0xFF10B981);
const kAdminDanger = Color(0xFFF87171);

/// Sağ alttaki eylem düğmesi olan listelerin alt boşluğu: liste sonuna
/// inildiğinde son eleman düğmenin altında kalmaz.
const kAdminFabClearance = 96.0;

/// Üst üste birden fazla eylem düğmesi varsa her ek (küçük) düğme için
/// eklenecek boşluk.
const kAdminFabStep = 56.0;

/// Yönetim ekranlarının ortak iskeleti: koyu zemin; geri düğmesi üst bandın
/// solunda, [title] bantta uygulama adının altında küçük puntoyla. Eylem
/// düğmeleri ([actions]) sağ altta yuvarlak düğme olarak durur.
class AdminPageScaffold extends StatelessWidget {
  const AdminPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.bandBack = true,
  });

  final String title;
  final Widget body;
  final List<AdminBarAction>? actions;

  /// false: eski başlık çubuğu (giriş bandı açıkken görünen şifre / kayıt
  /// ekranları; orada sayfa bandı gösterilmez).
  final bool bandBack;

  @override
  Widget build(BuildContext context) {
    if (bandBack) {
      final acts = actions ?? const <AdminBarAction>[];
      return BandBackPage(
        subtitle: title,
        child: Scaffold(
          backgroundColor: kAdminBg,
          body: SafeArea(top: false, child: body),
          floatingActionButton: acts.isEmpty
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < acts.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      acts[i].fab(small: i < acts.length - 1),
                    ],
                  ],
                ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: kAdminBg,
      extendBodyBehindAppBar: true,
      appBar: MasterClassAppBar(title: title, actions: actions),
      body: Stack(children: [SafeArea(child: body)]),
    );
  }
}

/// Başlık çubuğu için beyaz ikon butonu (ör. sağ üstteki "Ekle").
class AdminBarAction extends StatelessWidget {
  const AdminBarAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Sağ alttaki yuvarlak düğme hâli (son eylem büyük, diğerleri küçük).
  Widget fab({bool small = false}) {
    final enabled = onPressed != null;
    return FloatingActionButton(
      heroTag: null,
      mini: small,
      tooltip: tooltip,
      onPressed: onPressed,
      backgroundColor: enabled ? kAdminAccent : const Color(0xFF334155),
      foregroundColor: enabled ? Colors.white : Colors.white38,
      child: Icon(icon, size: small ? 20 : 26),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white, size: 26),
    );
  }
}

/// Liste satırlarındaki küçük kare eylem butonu (düzenle / sil).
class AdminSmallAction extends StatelessWidget {
  const AdminSmallAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

/// Liste için ortak koyu kart.
BoxDecoration adminCardDecoration() => BoxDecoration(
  color: Colors.black.withValues(alpha: 0.3),
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
);

/// Ortada açılan gradientli popup çerçevesi.
BoxDecoration adminDialogDecoration() => BoxDecoration(
  borderRadius: BorderRadius.circular(24),
  gradient: const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E293B), Color(0xFF064E3B)],
  ),
  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
  boxShadow: const [
    BoxShadow(color: Colors.black54, blurRadius: 15, offset: Offset(0, 8)),
  ],
);

/// Standart onay popup'ı (ör. silme). Onaylanırsa true döner.
Future<bool> showAdminConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'SİL',
  bool destructive = true,
  IconData icon = Icons.delete_outline_rounded,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: AdminDialogCloseOverlay(
        onClose: () => Navigator.pop(ctx, false),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: adminDialogDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: destructive ? kAdminDanger : kAdminAccent,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: destructive
                        ? const Color(0xFFDC2626)
                        : kAdminAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    confirmLabel,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return ok == true;
}

/// Alttan açılan panel yerine ortada açılan standart popup. [builder]
/// içeriği (liste/form) üretir; içerikte `Navigator.pop(context, sonuç)`
/// kullanılabilir. Dışarı dokunmak popup'ı kapatır.
Future<T?> showAdminPopup<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: (mq.size.height - mq.viewInsets.bottom) * 0.85,
          ),
          padding: const EdgeInsets.only(top: 14),
          clipBehavior: Clip.antiAlias,
          decoration: adminDialogDecoration(),
          child: builder(ctx),
        ),
      );
    },
  );
}

/// Fikstür ekranındaki filtre kapsülü: seçili filtrelerin özeti. Birden fazla
/// filtresi olan yönetim ekranlarında tek filtre girişi olarak kullanılır;
/// dokununca [showAdminFilterDialog] açılmalı.
class AdminFilterBar extends StatelessWidget {
  const AdminFilterBar({
    super.key,
    required this.summary,
    required this.onTap,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 12),
  });

  final String summary;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Center(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white24),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.tune_rounded, color: kAdminAccent, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white70,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ortada açılan filtre penceresi (Fikstür ile aynı görünüm).
///
/// [fieldsBuilder] seçicileri üretir ve her yenilemede yeniden çağrılır;
/// seçiciler değişikliği ekrana hemen uygular, sonra `refresh` ile pencereyi
/// yeniler (ör. turnuva değişince sezon listesi). "Filtreleri Uygula" yalnızca
/// pencereyi kapatır.
Future<void> showAdminFilterDialog({
  required BuildContext context,
  required List<Widget> Function(BuildContext context, VoidCallback refresh)
  fieldsBuilder,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        void refresh() {
          if (ctx.mounted) setDialogState(() {});
        }

        final fields = fieldsBuilder(ctx, refresh);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: adminDialogDecoration(),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < fields.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    fields[i],
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAdminAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Filtreleri Uygula',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
