import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin_page.dart';
import '../utils/team_colors.dart';

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

/// [AdminFieldRow] içindeki metin alanları için: çerçeve ve dolgu yok, satır
/// kartın parçası gibi görünür. Temanın etkin/odaklı/pasif çerçeve ve dolgu
/// ayarları da kapatılır (yalnızca `border: InputBorder.none` yetmiyor).
InputDecoration adminInlineInputDecoration({
  String? hint,
  String? prefixText,
}) => InputDecoration(
  isDense: true,
  filled: false,
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
  errorBorder: InputBorder.none,
  focusedErrorBorder: InputBorder.none,
  contentPadding: const EdgeInsets.only(top: 2),
  hintText: hint,
  hintStyle: const TextStyle(color: Colors.white38),
  prefixText: prefixText,
  prefixStyle: const TextStyle(
    color: Colors.white70,
    fontSize: 15,
    fontWeight: FontWeight.w700,
  ),
);

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
      trailing = const Icon(Icons.chevron_right_rounded, color: Colors.white54);
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

/// Tek alanlı giriş popup'ı (ör. forma no). Kaydedilirse girilen metni,
/// vazgeçilirse null döner.
Future<String?> showAdminTextInputDialog({
  required BuildContext context,
  required String title,
  required IconData icon,
  required String label,
  required IconData fieldIcon,
  String initialValue = '',
  String? hint,
  String? subtitle,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
  String confirmLabel = 'KAYDET',
  bool obscureText = false,

  /// Hata mesajı dönerse popup kapanmaz, mesaj alanın altında görünür.
  String? Function(String value)? validator,
}) async {
  final controller = TextEditingController(text: initialValue);
  String? error;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void submit() {
          final e = validator?.call(controller.text);
          if (e != null) {
            setState(() => error = e);
            return;
          }
          Navigator.pop(ctx, controller.text);
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: adminDialogDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminDialogHeader(icon: icon, title: title, subtitle: subtitle),
                const SizedBox(height: 18),
                AdminFieldGroup(
                  children: [
                    AdminFieldRow(
                      icon: fieldIcon,
                      label: label,
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        obscureText: obscureText,
                        keyboardType: keyboardType,
                        inputFormatters: inputFormatters,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => submit(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: adminInlineInputDecoration(hint: hint),
                      ),
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: kAdminDanger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                AdminPrimaryButton(label: confirmLabel, onPressed: submit),
                const SizedBox(height: 10),
                AdminSecondaryButton(onPressed: () => Navigator.pop(ctx)),
              ],
            ),
          ),
        );
      },
    ),
  );
  // Kapanış animasyonu bitene kadar alan controller'ı kullanır.
  Future<void>.delayed(const Duration(milliseconds: 600), controller.dispose);
  return result;
}

/// Tek düğmeli bilgi / hata popup'ı.
Future<void> showAdminInfoDialog({
  required BuildContext context,
  required String title,
  required String message,
  IconData icon = Icons.error_outline_rounded,
  Color iconColor = kAdminDanger,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: adminDialogDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: iconColor, size: 22),
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
            const SizedBox(height: 12),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 22),
            AdminPrimaryButton(
              label: 'TAMAM',
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Formlardaki renk satırı: renk kutusu + hex kodu; dokununca renk seçici.
class AdminColorRow extends StatelessWidget {
  const AdminColorRow({
    super.key,
    required this.label,
    required this.hex,
    required this.onTap,
    this.onClear,
    this.icon = Icons.palette_outlined,
  });

  final String label;
  final String? hex;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(hex);
    return AdminFieldRow(
      icon: icon,
      label: label,
      onTap: onTap,
      trailing: color != null && onClear != null && onTap != null
          ? IconButton(
              tooltip: 'Temizle',
              visualDensity: VisualDensity.compact,
              onPressed: onClear,
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white54,
                size: 20,
              ),
            )
          : const Icon(Icons.chevron_right_rounded, color: Colors.white54),
      // Kullanıcı renk kodu bilmez; yalnızca seçilen renk gösterilir.
      child: color == null
          ? const Text(
              'Renk seçin',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            )
          : Container(
              height: 26,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
              ),
            ),
    );
  }
}

/// [AdminColorRow]'ın kompakt hâli: iki renk yan yana sığsın diye ikon
/// kutusu yok; etiket üstte, seçilen renk altta.
class AdminColorTile extends StatelessWidget {
  const AdminColorTile({
    super.key,
    required this.label,
    required this.hex,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String? hex;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(hex);
    final canClear = color != null && onClear != null && onTap != null;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: kAdminMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: color == null
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 3),
                              child: Text(
                                'Renk seçin',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : Container(
                              height: 26,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                              ),
                            ),
                    ),
                    SizedBox(
                      width: 32,
                      height: 26,
                      child: canClear
                          ? IconButton(
                              tooltip: 'Temizle',
                              padding: EdgeInsets.zero,
                              iconSize: 18,
                              onPressed: onClear,
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white54,
                              ),
                            )
                          : const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white54,
                              size: 20,
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _kColorPresets = <String>[
  '#FFFFFF',
  '#111827',
  '#6B7280',
  '#C8102E',
  '#8B0000',
  '#E85D1F',
  '#FFD200',
  '#F6C700',
  '#00843D',
  '#0B5D1E',
  '#6CC24A',
  '#00A3E0',
  '#003DA5',
  '#0B1F4D',
  '#6A1B9A',
  '#A51C30',
  '#FDB913',
  '#00B5AD',
  '#F472B6',
  '#7C2D12',
];

/// Ortada açılan renk seçici: hazır renkler + hex kodu. Seçilen "#RRGGBB"
/// döner; vazgeçilirse null.
Future<String?> showAdminColorPicker({
  required BuildContext context,
  required String title,
  String? initial,
}) async {
  final hexCtrl = TextEditingController(
    text: parseHexColor(initial) == null
        ? ''
        : colorToHex(parseHexColor(initial)!),
  );
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final current = parseHexColor(hexCtrl.text);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: adminDialogDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminDialogHeader(icon: Icons.palette_outlined, title: title),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final h in _kColorPresets)
                      GestureDetector(
                        onTap: () => setState(() => hexCtrl.text = h),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: parseHexColor(h),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: current != null && colorToHex(current) == h
                                  ? kAdminAccent
                                  : Colors.white.withValues(alpha: 0.25),
                              width: current != null && colorToHex(current) == h
                                  ? 3
                                  : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // Hazır renklerde olmayan tonlar için: ton + açıklık kaydırıcı.
                _ColorSliders(
                  color: current,
                  onChanged: (c) =>
                      setState(() => hexCtrl.text = colorToHex(c)),
                ),
                const SizedBox(height: 22),
                AdminPrimaryButton(
                  label: 'SEÇ',
                  onPressed: current == null
                      ? null
                      : () => Navigator.pop(ctx, colorToHex(current)),
                ),
                const SizedBox(height: 10),
                AdminSecondaryButton(onPressed: () => Navigator.pop(ctx)),
              ],
            ),
          ),
        );
      },
    ),
  );
  Future<void>.delayed(const Duration(milliseconds: 600), hexCtrl.dispose);
  return result;
}

/// Renk seçicide ton ve açıklık kaydırıcıları + seçilen rengin önizlemesi.
class _ColorSliders extends StatelessWidget {
  const _ColorSliders({required this.color, required this.onChanged});

  final Color? color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(color ?? const Color(0xFFE85D1F));
    // Gri tonlarda (beyaz/siyah) ton değişince renk görünsün diye doygunluk
    // yükseltilir.
    final sat = hsl.saturation < 0.2 ? 0.85 : hsl.saturation;

    Widget track(List<Color> colors, double value, ValueChanged<double> on) {
      return SizedBox(
        height: 32,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              height: 14,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                gradient: LinearGradient(colors: colors),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 0,
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                overlayShape: SliderComponentShape.noOverlay,
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              ),
              child: Slider(value: value, onChanged: on),
            ),
          ],
        ),
      );
    }

    return AdminFieldGroup(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: color ?? Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                alignment: Alignment.center,
                child: color == null
                    ? const Text(
                        'Renk seçin',
                        style: TextStyle(color: Colors.white38),
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              track(
                [
                  for (var h = 0; h <= 360; h += 60)
                    HSLColor.fromAHSL(1, h.toDouble(), 0.9, 0.5).toColor(),
                ],
                hsl.hue / 360,
                (v) => onChanged(
                  HSLColor.fromAHSL(
                    1,
                    v * 360,
                    sat,
                    hsl.lightness.clamp(0.15, 0.85),
                  ).toColor(),
                ),
              ),
              track(
                [
                  Colors.black,
                  HSLColor.fromAHSL(1, hsl.hue, sat, 0.5).toColor(),
                  Colors.white,
                ],
                hsl.lightness,
                (v) => onChanged(hsl.withLightness(v).toColor()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
