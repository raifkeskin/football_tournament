import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TC kimlik no alanı: ilk 2 ve son 3 hane dışındakiler `*` görünür. Yeni
/// yazılan rakam 1 sn görünür kalır, sonra `*` olur (şifre alanları gibi).
///
/// [controller] ham numarayı (yalnız rakamlar, en çok 11) tutar; ekrandaki
/// maskeli metin ayrı tutulur. Düzenleme sondan yapılır (imleç hep sonda).
class TcMaskedField extends StatefulWidget {
  const TcMaskedField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.style,
    this.decoration,
  });

  final TextEditingController controller;
  final bool enabled;
  final TextStyle? style;
  final InputDecoration? decoration;

  @override
  State<TcMaskedField> createState() => _TcMaskedFieldState();
}

class _TcMaskedFieldState extends State<TcMaskedField> {
  static const _length = 11;
  final _display = TextEditingController();
  Timer? _revealTimer;

  /// Az önce yazılan hanenin yeri (1 sn açık kalır).
  int? _revealAt;

  static bool _alwaysVisible(int i) => i < 2 || i >= _length - 3;

  String _masked() {
    final raw = widget.controller.text;
    final b = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      b.write(_alwaysVisible(i) || i == _revealAt ? raw[i] : '*');
    }
    return b.toString();
  }

  void _sync() {
    final t = _masked();
    if (_display.text == t) return;
    _display.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(covariant TcMaskedField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      _sync();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _revealTimer?.cancel();
    _display.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    final shown = _masked();
    var raw = widget.controller.text;
    if (text.length > shown.length) {
      final added = text.substring(shown.length).replaceAll(RegExp(r'\D'), '');
      raw = raw + added;
      if (raw.length > _length) raw = raw.substring(0, _length);
      _revealAt = added.isEmpty ? null : raw.length - 1;
      _revealTimer?.cancel();
      _revealTimer = Timer(const Duration(seconds: 1), () {
        if (!mounted) return;
        _revealAt = null;
        _sync();
      });
    } else if (text.length < shown.length) {
      raw = raw.substring(0, max(0, raw.length - (shown.length - text.length)));
      _revealAt = null;
    }
    if (raw != widget.controller.text) {
      widget.controller.text = raw;
    }
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _display,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      autocorrect: false,
      enableSuggestions: false,
      // Ortadan seçip düzenleme yok: maskeli metin ham numarayla eşleşmez.
      enableInteractiveSelection: false,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9*]'))],
      onChanged: _onChanged,
      onTap: () => _display.selection = TextSelection.collapsed(
        offset: _display.text.length,
      ),
      style: widget.style,
      decoration: widget.decoration,
    );
  }
}
