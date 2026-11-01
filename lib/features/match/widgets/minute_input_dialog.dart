import 'package:flutter/material.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';

/// Elle dakika girişi. [allowAdded] ise "30+2" de yazılabilir.
/// Geçersiz ya da boş girişte null döner.
Future<({int minute, int? added})?> showMinuteInputDialog(
  BuildContext context, {
  required String title,
  int? minute,
  int? added,
  bool allowAdded = true,
  String? hint,
}) async {
  final ctrl = TextEditingController(
    text: minute == null ? '' : (added == null ? '$minute' : '$minute+$added'),
  );
  ({int minute, int? added})? parse() {
    final t = ctrl.text.replaceAll(' ', '');
    final m = RegExp(
      allowAdded ? r'^(\d{1,3})(?:\+(\d{1,2}))?$' : r'^(\d{1,3})$',
    ).firstMatch(t);
    if (m == null) return null;
    final base = int.parse(m.group(1)!);
    final extra = m.group(2) == null ? null : int.parse(m.group(2)!);
    if (base < 1 || base > 200 || (extra != null && extra < 1)) return null;
    return (minute: base, added: extra);
  }

  final result = await showDialog<({int minute, int? added})>(
    context: context,
    builder: (ctx) {
      void done() {
        final v = parse();
        if (v != null) Navigator.pop(ctx, v);
      }

      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 48),
        child: AdminDialogCloseOverlay(
          onClose: () => Navigator.pop(ctx),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: adminDialogDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (hint != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kAdminMuted, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: allowAdded
                      ? TextInputType.datetime
                      : TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: allowAdded ? 6 : 3,
                  onSubmitted: (_) => done(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: allowAdded ? 'ör. 23 ya da 30+2' : 'ör. 23',
                    hintStyle: const TextStyle(
                      color: Colors.white24,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                AdminPrimaryButton(
                  label: 'TAMAM',
                  icon: Icons.check_rounded,
                  onPressed: done,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result;
}
