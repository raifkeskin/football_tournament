import 'package:flutter/material.dart';

/// Uygulamanın tüm bilgi balonları (SnackBar) tek yerden: her balon
/// [duration] sonra kendiliğinden kaybolur ("Geri al" gibi düğmesi olsa da),
/// yenisi gelince eskisi beklemeden kapanır. MaterialApp.builder'da en dışta.
class AppSnackMessenger extends ScaffoldMessenger {
  const AppSnackMessenger({super.key, required super.child});

  static const duration = Duration(seconds: 2);

  @override
  ScaffoldMessengerState createState() => _AppSnackMessengerState();
}

class _AppSnackMessengerState extends ScaffoldMessengerState {
  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    removeCurrentSnackBar();
    final s = snackBar;
    return super.showSnackBar(
      SnackBar(
        key: s.key,
        content: s.content,
        backgroundColor: s.backgroundColor,
        elevation: s.elevation,
        margin: s.margin,
        padding: s.padding,
        width: s.width,
        shape: s.shape,
        hitTestBehavior: s.hitTestBehavior,
        behavior: s.behavior,
        action: s.action,
        actionOverflowThreshold: s.actionOverflowThreshold,
        showCloseIcon: s.showCloseIcon,
        closeIconColor: s.closeIconColor,
        duration: AppSnackMessenger.duration,
        persist: false,
        animation: s.animation,
        onVisible: s.onVisible,
        dismissDirection: s.dismissDirection,
        clipBehavior: s.clipBehavior,
      ),
      snackBarAnimationStyle: snackBarAnimationStyle,
    );
  }
}
