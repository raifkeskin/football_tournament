import 'package:flutter/material.dart';

class AppBottomSheet {
  /// Standart tasarıma sahip bir BottomSheet gösterir.
  static void show({
    required BuildContext context,
    required String title,
    required Widget child,
    IconData? titleIcon,
    VoidCallback? onSave,
    String saveText = 'KAYDET',
    String cancelText = 'VAZGEÇ',
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Klavye açıldığında yukarı kayması için
      backgroundColor: Colors.transparent,
      builder: (BuildContext c) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF1E293B), // Üst lacivert
                  Color(0xFF1E293B), // Alt lacivert (dilersen yeşile 0xFF064E3B döndürebilirsin)
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Tutma Çubuğu
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Opsiyonel Başlık ve İkon
                if (title.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (titleIcon != null) ...[
                        Icon(titleIcon, color: Colors.white70, size: 24),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 20),
                ],

                // İçerik Alanı
                child,

                const SizedBox(height: 24),

                // Butonlar
                if (onSave != null)
                  ElevatedButton(
                    onPressed: () {
                      onSave();
                      Navigator.pop(c); // Kaydet sonrası kapat
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF064E3B), // Masterclass koyu yeşil
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(saveText, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.pop(c),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withOpacity(0.2)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(cancelText, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}