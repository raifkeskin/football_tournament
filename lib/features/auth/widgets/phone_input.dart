import 'package:flutter/services.dart';

/// Telefon girişini 10 haneye indirger: rakam dışı her şey atılır, 10'dan
/// uzunsa son 10 hane alınır ("+90 532…", "0 532…", "0532…" → "532…").
/// Kısa girişte (yazarken) baştaki 0'lar atılır.
String normalizePhoneToRaw10(String input) {
  final d = input.replaceAll(RegExp(r'\D'), '');
  if (d.length > 10) return d.substring(d.length - 10);
  return d.replaceFirst(RegExp(r'^0+'), '');
}

/// 10 haneli numarayı "0 (5xx) xxx xx xx" biçiminde gösterir.
String formatPhoneRaw10(String raw10) {
  final p = raw10.trim();
  if (p.length != 10) return p.isEmpty ? '-' : p;
  return '0 (${p.substring(0, 3)}) ${p.substring(3, 6)} '
      '${p.substring(6, 8)} ${p.substring(8)}';
}

/// Telefon alanı maskesi: yazarken ya da yapıştırırken "(5XX) XXX XX XX"
/// biçimine sokar. Tüm telefon alanları bunu kullanır.
class PhoneMaskFormatter extends TextInputFormatter {
  /// Kayıtlı numarayı (herhangi bir biçimde) alan metnine çevirir.
  static String formatFromRaw(String raw) =>
      _formatFromRaw10(normalizePhoneToRaw10(raw));

  static String _formatFromRaw10(String raw10) {
    final clipped = raw10.length > 10 ? raw10.substring(0, 10) : raw10;
    final a = clipped.length >= 3 ? clipped.substring(0, 3) : clipped;
    final b = clipped.length > 3
        ? clipped.substring(3, clipped.length >= 6 ? 6 : clipped.length)
        : '';
    final c = clipped.length > 6
        ? clipped.substring(6, clipped.length >= 8 ? 8 : clipped.length)
        : '';
    final d = clipped.length > 8 ? clipped.substring(8) : '';
    final sb = StringBuffer();
    if (a.isNotEmpty) {
      sb.write('(');
      sb.write(a);
      if (a.length == 3) sb.write(') ');
    }
    if (b.isNotEmpty) {
      sb.write(b);
      if (b.length == 3) sb.write(' ');
    }
    if (c.isNotEmpty) {
      sb.write(c);
      if (c.length == 2) sb.write(' ');
    }
    if (d.isNotEmpty) sb.write(d);
    return sb.toString().trimRight();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatFromRaw(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
