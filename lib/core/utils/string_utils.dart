import 'package:flutter/services.dart';

class StringUtils {
  static String normalizeTrKey(String input) {
    var s = input.trim().toLowerCase();
    s = s
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .replaceAll('i̇', 'i')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }
}

class TurkishUpperCaseTextFormatter extends TextInputFormatter {
  const TurkishUpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final upperCaseText = newValue.text
        .replaceAll('i', 'İ')
        .replaceAll('ı', 'I')
        .replaceAll('ğ', 'Ğ')
        .replaceAll('ü', 'Ü')
        .replaceAll('ş', 'Ş')
        .replaceAll('ö', 'Ö')
        .replaceAll('ç', 'Ç')
        .toUpperCase();

    return TextEditingValue(
      text: upperCaseText,
      selection: newValue.selection,
      composing: newValue.composing,
    );
  }
}
