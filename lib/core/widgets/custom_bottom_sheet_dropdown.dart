import 'package:flutter/material.dart';

import 'admin_form.dart';

/// Seçim alanı: dokununca seçenekler ortada açılan temalı popup'ta listelenir.
/// Alan görünümü uygulamadaki diğer metin alanlarıyla aynıdır (tema).
/// (Adı geçmişten kalma; artık alttan açılan panel kullanmıyor.)
class CustomBottomSheetDropdown<T> extends StatelessWidget {
  final String labelText;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabelBuilder;
  final void Function(T?) onChanged;
  final String? hintText;
  final IconData? prefixIcon;

  const CustomBottomSheetDropdown({
    super.key,
    required this.labelText,
    required this.value,
    required this.items,
    required this.itemLabelBuilder,
    required this.onChanged,
    this.hintText,
    this.prefixIcon,
  });

  Future<void> _showPicker(BuildContext context) async {
    final picked = await showAdminOptionPicker<T>(
      context: context,
      title: '$labelText Seçin',
      items: items,
      labelBuilder: itemLabelBuilder,
      selected: value,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final displayText = value != null
        ? itemLabelBuilder(value as T)
        : (hintText ?? '');

    return GestureDetector(
      onTap: () => _showPicker(context),
      child: AbsorbPointer(
        child: TextFormField(
          key: ValueKey(value), // değer değişince alan güncellensin
          initialValue: displayText,
          // Dekorasyon uygulama temasından gelir: diğer alanlarla aynı görünüm.
          decoration: InputDecoration(
            labelText: labelText,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
            suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
          ),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
