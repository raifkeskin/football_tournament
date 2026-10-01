import 'package:flutter/material.dart';

import 'admin_page.dart';

// Yönetim formlarının ortak parçaları (Fikstür Planlama, Ceza, Takım popup'ı).
// Görünüm Sezon / Grup listelerindeki kartlarla aynı dili kullanır.

const kAdminMuted = Color(0xFF94A3B8);
const kAdminAmber = Color(0xFFFBBF24);

/// Seçim listelerinde kullanılan seçenek.
typedef AdminOption = ({String id, String name, bool isDefault});

/// Tek seçenek varsa onu, yoksa "varsayılan" işaretli olanı döner; ikisi de
/// yoksa null (kullanıcı seçer).
String? autoPickOption(List<AdminOption> options) {
  if (options.length == 1) return options.first.id;
  for (final o in options) {
    if (o.isDefault) return o.id;
  }
  return null;
}

String _trUpper(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Form metin alanları için ortak görünüm.
InputDecoration adminInputDecoration({
  String? label,
  String? hint,
  IconData? icon,
  bool alignLabelWithHint = false,
}) {
  OutlineInputBorder border(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    alignLabelWithHint: alignLabelWithHint,
    labelStyle: const TextStyle(color: kAdminMuted),
    floatingLabelStyle: const TextStyle(
      color: kAdminAccent,
      fontWeight: FontWeight.w700,
    ),
    hintStyle: const TextStyle(color: Colors.white38),
    prefixIcon: icon == null ? null : Icon(icon, color: kAdminAccent, size: 20),
    filled: true,
    fillColor: Colors.black.withValues(alpha: 0.3),
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: border(Colors.white.withValues(alpha: 0.1)),
    enabledBorder: border(Colors.white.withValues(alpha: 0.1)),
    disabledBorder: border(Colors.white.withValues(alpha: 0.05)),
    focusedBorder: border(kAdminAccent),
  );
}

/// Popup başlığı: ikon + başlık (+ alt başlık), altında ayraç.
class AdminDialogHeader extends StatelessWidget {
  const AdminDialogHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: kAdminAccent, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kAdminMuted, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        const Divider(color: Colors.white24, height: 1),
      ],
    );
  }
}

/// Başlıklı form bölümü: yeşil büyük harf başlık ve altında içerik.
class AdminFormSection extends StatelessWidget {
  const AdminFormSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _trUpper(title),
                    style: const TextStyle(
                      color: kAdminAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Satırları tek kartta, aralarında ince çizgiyle toplar.
class AdminFieldGroup extends StatelessWidget {
  const AdminFieldGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 62,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// [AdminFieldGroup] içindeki satır iskeleti: solda ikon kutusu, ortada
/// etiket + değer, sağda [trailing].
class AdminFieldRow extends StatelessWidget {
  const AdminFieldRow({
    super.key,
    required this.icon,
    required this.label,
    required this.child,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 62),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: kAdminAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: kAdminAccent, size: 19),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: kAdminMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      child,
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dokununca seçim popup'ı açan satır. [onTap] null ise pasif görünür;
/// [locked] ise değer kilitli (soluklaşmaz, kilit ikonu gösterir).
class AdminSelectRow extends StatelessWidget {
  const AdminSelectRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.locked = false,
    this.loading = false,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback? onTap;
  final bool locked;
  final bool loading;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasValue = (value ?? '').trim().isNotEmpty;
    final Widget trailing;
    if (loading) {
      trailing = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: kAdminAccent),
      );
    } else if (locked) {
      trailing = const Icon(
        Icons.lock_outline_rounded,
        color: Colors.white38,
        size: 18,
      );
    } else if (hasValue && onClear != null && onTap != null) {
      trailing = IconButton(
        tooltip: 'Temizle',
        visualDensity: VisualDensity.compact,
        onPressed: onClear,
        icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
      );
    } else {
      trailing = const Icon(
        Icons.chevron_right_rounded,
        color: Colors.white54,
      );
    }
    return AdminFieldRow(
      icon: icon,
      label: label,
      enabled: locked || onTap != null,
      onTap: locked ? null : onTap,
      trailing: trailing,
      child: Text(
        hasValue ? value! : placeholder,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: hasValue ? Colors.white : Colors.white38,
          fontSize: 15,
          fontWeight: hasValue ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

/// Ortada açılan seçim listesi. Seçilen öğeyi döner; dışarı dokunulursa null.
Future<T?> showAdminOptionPicker<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String Function(T) labelBuilder,
  T? selected,
  String emptyText = 'Kayıt bulunamadı.',
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.7,
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: adminDialogDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            Flexible(
              child: items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        emptyText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(
                        color: Colors.white12,
                        height: 1,
                        indent: 20,
                        endIndent: 20,
                      ),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isSelected = item == selected;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 24,
                          ),
                          title: Text(
                            labelBuilder(item),
                            style: TextStyle(
                              color: isSelected ? kAdminAccent : Colors.white,
                              fontWeight: isSelected
                                  ? FontWeight.w900
                                  : FontWeight.w600,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: kAdminAccent,
                                )
                              : null,
                          onTap: () => Navigator.pop(ctx, item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Ana eylem butonu (KAYDET).
class AdminPrimaryButton extends StatelessWidget {
  const AdminPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: kAdminAccent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: kAdminAccent.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// İkincil buton (VAZGEÇ).
class AdminSecondaryButton extends StatelessWidget {
  const AdminSecondaryButton({
    super.key,
    required this.onPressed,
    this.label = 'VAZGEÇ',
  });

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
