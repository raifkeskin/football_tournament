import 'package:flutter/material.dart';

/// Sağ alttaki büyüteçle açılan arama / filtre alanı: liste aşağı
/// kaydırılmışken alan yukarıda kalıp görünmüyordu. Alan çizildikten sonra
/// içinde bulunduğu listeyi en üste kaydırır ve alana odaklanır.
void revealSearchField(FocusNode focus) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = focus.context;
    final pos = ctx == null ? null : Scrollable.maybeOf(ctx)?.position;
    if (pos != null && pos.pixels > pos.minScrollExtent) {
      pos.animateTo(
        pos.minScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    focus.requestFocus();
  });
}
