import 'dart:async';

import 'package:flutter/material.dart';

/// Doğrulama kodunun kalan süresi (varsayılan 3 dakika). Kod yeniden
/// gönderilince [key] değiştirilerek sayaç baştan başlatılır.
class OtpCountdown extends StatefulWidget {
  const OtpCountdown({super.key, this.seconds = 180});

  final int seconds;

  @override
  State<OtpCountdown> createState() => _OtpCountdownState();
}

class _OtpCountdownState extends State<OtpCountdown> {
  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left = _left > 0 ? _left - 1 : 0);
      if (_left == 0) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expired = _left == 0;
    final mm = (_left ~/ 60).toString().padLeft(2, '0');
    final ss = (_left % 60).toString().padLeft(2, '0');
    final color = expired
        ? const Color(0xFFF87171)
        : _left <= 30
        ? const Color(0xFFFBBF24)
        : const Color(0xFF94A3B8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              expired
                  ? 'Kodun süresi doldu. Yeni kod isteyin.'
                  : 'Kodun geçerlilik süresi: $mm:$ss',
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
