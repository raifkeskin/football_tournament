import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Şifre kuralları: giriş/şifre belirleme ekranlarında ortak.
class PasswordRules {
  PasswordRules._();

  static bool lengthOk(String v) => v.length >= 6 && v.length <= 10;

  static bool hasDigitOrSpecial(String v) => RegExp(r'[^A-Za-z]').hasMatch(v);

  /// Kolay tahmin edilen şifre (123456, 111111, 121212, telefonun bir
  /// parçası...). [phone] kişinin numarası (rakamlar; ülke kodu olabilir).
  static bool isWeak(String v, {String? phone}) {
    final p = v.toLowerCase();
    if (_common.contains(p)) return true;
    if (!RegExp(r'^\d+$').hasMatch(p)) return false;
    // Kısa bir parçanın tekrarı: 111111, 121212, 123123.
    for (var k = 1; k <= 3; k++) {
      if (p.length % k == 0 && p == p.substring(0, k) * (p.length ~/ k)) {
        return true;
      }
    }
    // Ardışık rakamlar: 123456, 456789, 987654, 3456789.
    bool step(int d) {
      for (var i = 1; i < p.length; i++) {
        if (p.codeUnitAt(i) - p.codeUnitAt(i - 1) != d) return false;
      }
      return true;
    }

    if (step(1) || step(-1)) return true;
    // Telefon numarasının içinden bir dizi.
    final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10 && digits.contains(p)) return true;
    return false;
  }

  static const _common = {
    '112233',
    '102030',
    '159753',
    '147258',
    '147258369',
    '159357',
    '123321',
    'abc123',
    'qwerty1',
    'qwe123',
    'asd123',
    'sifre1',
    'sifre123',
    'şifre1',
    'şifre123',
    'parola1',
    'parola123',
  };

  static const weakMessage =
      'Bu şifre çok kolay tahmin edilir (123456, 111111, telefon numaranız '
      'gibi). Lütfen başka bir şifre seçin.';
}

/// Şifre alanında açılan klavye: rakam (varsayılan) ya da harf. Son seçim
/// cihazda hatırlanır; harfli şifresi olan tek dokunuşla geçer.
class PasswordKeyboard {
  PasswordKeyboard._();

  static const _prefKey = 'password_numeric_keyboard';

  /// true: rakam klavyesi.
  static final numeric = ValueNotifier<bool>(true);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      numeric.value = prefs.getBool(_prefKey) ?? true;
    } catch (_) {}
  }

  static TextInputType get type =>
      numeric.value ? TextInputType.number : TextInputType.visiblePassword;

  static Future<void> toggle(FocusNode focus) async {
    numeric.value = !numeric.value;
    // Açık klavye yeni türe ancak alan yeniden odaklanınca geçer.
    if (focus.hasFocus) {
      focus.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, numeric.value);
    } catch (_) {}
  }
}

/// Şifre alanının sağındaki "ABC / 123" düğmesi (diğer klavyeye geçer).
class PasswordKeyboardToggle extends StatelessWidget {
  const PasswordKeyboardToggle({super.key, required this.focus});

  final FocusNode focus;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PasswordKeyboard.numeric,
      builder: (context, numeric, _) => Padding(
        padding: const EdgeInsets.only(left: 6, right: 4),
        child: Tooltip(
          message: numeric ? 'Harf klavyesi' : 'Rakam klavyesi',
          child: Material(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => PasswordKeyboard.toggle(focus),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  numeric ? 'ABC' : '123',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
