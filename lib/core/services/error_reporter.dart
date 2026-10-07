import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Uygulama hatalarını yakalar, veritabanına (`log_client_error`) yazar ve
/// ekran yerleşemediğinde "Bir sorun oluştu" kartını açar.
class ErrorReporter {
  ErrorReporter._();

  /// Ekran çizilemedi (yerleşim/çizim hatası): kök kart gösterilir.
  static final broken = ValueNotifier<bool>(false);

  /// Yenile: uygulama ağacı bu sayı değişince baştan kurulur.
  static final epoch = ValueNotifier<int>(0);

  /// Hatanın kimde olduğu (rol) — oturum denetleyicisi verir.
  static String? Function()? roleProvider;

  static String? _version;
  static final _sent = <String>{};
  static const _maxPerSession = 20;

  static void init() {
    unawaited(_loadVersion());

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      report(
        details.exception,
        details.stack,
        context: [
          details.library,
          details.context?.toDescription(),
        ].whereType<String>().join(' · '),
      );
      // Yerleşim/çizim hatası ağacın bir kısmını çizilmez bırakır (boş ekran).
      if (details.library == 'rendering library') _markBroken();
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Yakalanmamış hata: $error');
      report(error, stack, context: 'async');
      return true;
    };

    // Release'de gri kutu yerine kart; debug'da Flutter'ın kırmızı ekranı.
    if (kReleaseMode) {
      ErrorWidget.builder = (details) => const _ErrorTile();
    }
  }

  static Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = '${info.version}+${info.buildNumber}';
    } catch (_) {}
  }

  /// Kartı açar (çerçeve bittikten sonra; çizim sırasında setState olmasın).
  static void _markBroken() {
    if (broken.value) return;
    SchedulerBinding.instance.addPostFrameCallback((_) => broken.value = true);
    SchedulerBinding.instance.scheduleFrame();
  }

  /// Uygulamayı baştan kurar (oturum korunur).
  static void restart() {
    broken.value = false;
    epoch.value++;
  }

  static void dismiss() => broken.value = false;

  static String get _platform =>
      kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

  /// Hatayı bir kez (oturum başına parmak izi) sunucuya yazar.
  static void report(Object error, StackTrace? stack, {String? context}) {
    try {
      final message = error.toString();
      final stackText = stack?.toString() ?? '';
      final fp = _fingerprint(error, message, stackText);
      if (_sent.length >= _maxPerSession || !_sent.add(fp)) return;
      String? role;
      try {
        role = roleProvider?.call();
      } catch (_) {}
      unawaited(
        Supabase.instance.client
            .rpc(
              'log_client_error',
              params: {
                'p_fingerprint': fp,
                'p_message': message,
                'p_stack': _trimStack(stackText),
                'p_context': context,
                'p_platform': _platform,
                'p_app_version': _version,
                'p_role': role,
              },
            )
            .then((_) {}, onError: (_) {}),
      );
    } catch (_) {
      // Hata kaydı uygulamayı asla bozmamalı.
    }
  }

  /// Aynı hata farklı cihazlarda aynı iz: türü, sayılarından arınmış ilk
  /// satırı ve uygulamaya ait ilk birkaç yığın satırı.
  static String _fingerprint(Object error, String message, String stack) {
    final firstLine = message.split('\n').first.replaceAll(RegExp(r'\d+'), '#');
    final frames = stack
        .split('\n')
        .where((l) => l.contains('football_tournament') || l.contains('lib/'))
        .take(3)
        .map((l) => l.replaceAll(RegExp(r'^#\d+\s+'), '').trim())
        .join('|');
    return '${_platform}_${_fnv('${error.runtimeType}|$firstLine|$frames')}';
  }

  /// 32 bit FNV-1a (web'de de aynı sonucu verir).
  static String _fnv(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  static String _trimStack(String stack) {
    final lines = stack.split('\n');
    return lines.take(40).join('\n');
  }
}

/// Ekran yerleşemediğinde içeriğin üstünde çıkan kart.
class ErrorRecoveryOverlay extends StatelessWidget {
  const ErrorRecoveryOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ErrorReporter.epoch,
      builder: (context, epoch, _) => Stack(
        children: [
          Positioned.fill(
            child: KeyedSubtree(key: ValueKey('app_$epoch'), child: child),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: ErrorReporter.broken,
            builder: (context, broken, _) => broken
                ? const Positioned.fill(child: _ErrorCard())
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0F172A),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 14),
          constraints: const BoxConstraints(maxWidth: 380),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFFBBF24),
                size: 44,
              ),
              const SizedBox(height: 12),
              const Text(
                'Bir sorun oluştu',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ekran yüklenirken beklenmeyen bir hata oluştu. Sorun bize '
                'iletildi; yenileyerek devam edebilirsiniz.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: ErrorReporter.restart,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text(
                    'YENİLE',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              TextButton(
                onPressed: ErrorReporter.dismiss,
                child: const Text(
                  'Kapat',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Release'de çizilemeyen parçanın yerine (gri kutu yerine) küçük kart.
class _ErrorTile extends StatelessWidget {
  const _ErrorTile();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: GestureDetector(
        onTap: ErrorReporter.restart,
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFFBBF24),
                size: 18,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: const Text(
                  'Bir sorun oluştu · Yenile',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
