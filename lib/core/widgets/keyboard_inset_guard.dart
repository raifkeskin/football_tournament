import 'package:flutter/material.dart';

/// "Hayalet klavye" koruması: Android bazen klavye kapandığı hâlde alt
/// boşluğu (viewInsets) bildirmeye devam eder; ekranın altı kararır ve
/// sayfa daralır. Seçili bir yazı alanı yoksa klavye boşluğu yok sayılır.
/// Uygulama alta alınınca odak bırakılır, böylece dönüşte eski klavye
/// boşluğu kalmaz.
class KeyboardInsetGuard extends StatefulWidget {
  const KeyboardInsetGuard({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardInsetGuard> createState() => _KeyboardInsetGuardState();
}

class _KeyboardInsetGuardState extends State<KeyboardInsetGuard>
    with WidgetsBindingObserver {
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_onFocus);
    _typing = _textFocused();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocus);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  static bool _textFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null || !ctx.mounted) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  void _onFocus() {
    final typing = _textFocused();
    if (typing != _typing && mounted) setState(() => _typing = typing);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (_typing || mq.viewInsets.bottom == 0) return widget.child;
    return MediaQuery(
      data: mq.copyWith(viewInsets: mq.viewInsets.copyWith(bottom: 0)),
      child: widget.child,
    );
  }
}
