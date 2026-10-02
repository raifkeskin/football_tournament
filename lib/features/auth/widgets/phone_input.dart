import 'package:flutter/services.dart';

/// "0 (5xx) xxx xx xx" girişini 10 haneye indirger (başta 0 / 90 atılır).
String normalizePhoneToRaw10(String input) {
  var d = input.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('90') && d.length >= 12) d = d.substring(2);
  if (d.startsWith('0')) d = d.substring(1);
  if (d.length > 10) d = d.substring(d.length - 10);
  return d;
}

/// 10 haneli numarayı "0 (5xx) xxx xx xx" biçiminde gösterir.
String formatPhoneRaw10(String raw10) {
  final p = raw10.trim();
  if (p.length != 10) return p.isEmpty ? '-' : p;
  return '0 (${p.substring(0, 3)}) ${p.substring(3, 6)} '
      '${p.substring(6, 8)} ${p.substring(8)}';
}

/// Telefon alanı maskesi: yazarken "(5XX) XXX XX XX" biçimine sokar.
class PhoneMaskFormatter extends TextInputFormatter {
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
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('90')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length > 10) digits = digits.substring(digits.length - 10);
    final formatted = _formatFromRaw10(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
