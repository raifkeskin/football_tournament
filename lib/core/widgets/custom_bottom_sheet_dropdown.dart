import 'package:flutter/material.dart';

import 'admin_page.dart';

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

  void _showPicker(BuildContext context) {
    showDialog<void>(
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
                  '$labelText Seçin',
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
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Kayıt bulunamadı.',
                          style: TextStyle(color: Colors.white54),
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
                          final isSelected = item == value;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 24,
                            ),
                            title: Text(
                              itemLabelBuilder(item),
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
                            onTap: () {
                              Navigator.pop(ctx);
                              onChanged(item);
                            },
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
