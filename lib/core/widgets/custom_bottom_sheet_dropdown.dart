import 'package:flutter/material.dart';

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

  void _showBottomSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // %80 kuralı için şart
      useSafeArea: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8, // Maksimum %80 yükseklik
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext ctx) {
        return Column(
          mainAxisSize: MainAxisSize.min, // İçeriği kadar uza, max %80'de dur
          children: [
            // Üst Başlık
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '$labelText Seçin',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
            const Divider(height: 1),
            // Seçenekler Listesi
            Flexible(
              child: items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        'Kayıt bulunamadı.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isSelected = item == value;
                        
                        return ListTile(
                          title: Text(
                            itemLabelBuilder(item),
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                              color: isSelected ? cs.primary : cs.onSurface,
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(Icons.check_circle_rounded, color: cs.primary)
                              : null,
                          onTap: () {
                            onChanged(item);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Ekranda gösterilecek metin: Seçiliyse ismini al, değilse boş bırak (hint kullan)
    final displayText = value != null ? itemLabelBuilder(value as T) : (hintText ?? '');

    return GestureDetector(
      onTap: () => _showBottomSheet(context),
      child: AbsorbPointer(
        child: TextFormField(
          key: ValueKey(value), // Sihirli dokunuş: Değer değişince anında günceller
          initialValue: displayText,
          decoration: InputDecoration(
            labelText: labelText,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
            suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: cs.primary, width: 1.6),
            ),
            filled: true,
            fillColor: cs.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}