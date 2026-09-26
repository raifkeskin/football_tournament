import 'package:flutter/material.dart';

class CustomPopupSelector<T> extends StatelessWidget {
  final String label;
  final T? selectedValue;
  final List<T?> items;
  final String Function(T?) labelBuilder;
  final Function(T?) onChanged;

  const CustomPopupSelector({
    super.key,
    required this.label,
    required this.selectedValue,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Benzersiz değerleri ayırır
    final uniqueItems = <T?>[];
    final seenValues = <T?>{};
    for (final item in items) {
      if (!seenValues.contains(item)) {
        seenValues.add(item);
        uniqueItems.add(item);
      }
    }

    final isValid = uniqueItems.contains(selectedValue);
    final safeValue = isValid
        ? selectedValue
        : (uniqueItems.isNotEmpty ? uniqueItems.first : null);

    final displayText = uniqueItems.contains(safeValue)
        ? labelBuilder(safeValue)
        : 'Seçiniz';

    return InkWell(
      onTap: () {
        _showSelectionDialog(
          context: context,
          title: label,
          items: uniqueItems,
          selectedValue: safeValue,
          labelBuilder: labelBuilder,
          onChanged: onChanged,
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
          filled: true,
          fillColor: Colors.black.withOpacity(0.4),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                displayText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  void _showSelectionDialog({
    required BuildContext context,
    required String title,
    required List<T?> items,
    required T? selectedValue,
    required String Function(T?) labelBuilder,
    required Function(T?) onChanged,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent, // Arka plan şeffaf
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1E293B), // Üst sol lacivert
                  Color(0xFF064E3B), // Alt sağ koyu zümrüt yeşili
                ],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
              ), 
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 15,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Text(
                    '$title Seç',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(color: Colors.white24),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (context, index) => const Divider(
                      color: Colors.white12, 
                      height: 1,
                      indent: 24, 
                      endIndent: 24,
                    ),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final isSelected = item == selectedValue;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                        ),
                        title: Text(
                          labelBuilder(item),
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFF10B981)
                                : Colors.white,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Color(0xFF10B981))
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onTap: () {
                          Navigator.pop(context); // Tıklandığı an popup kapanır
                          if (!isSelected) {
                            onChanged(item); // Ve yeni seçim hemen filtreye uygulanır
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}