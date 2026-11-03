import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_navigator.dart';
import '../utils/app_activity.dart';

/// Mağazada yeni sürüm varsa uyarır (`app_settings.app_update`).
///
/// Değer: `{"android": {"latest": 120, "min": null, "url": null}, "ios": {…}}`
/// (derleme numaraları). `latest`ten eskiyse altta kapatılabilir "Yeni sürüm
/// mevcut" kartı (Sonra → aynı sürüm için 1 gün sorulmaz); `min`den eskiyse
/// kapatılamayan güncelleme penceresi. Boşsa ya da okunamazsa hiçbir şey
/// çıkmaz. Web her zaman güncel olduğundan denetlenmez.
///
/// Pencereler gezginin katmanına (Overlay) eklenir; ekran geçişleri
/// (açılış → ana sayfa) onları kaldırmaz.
class AppUpdate {
  AppUpdate._();

  static const _kSetting = 'app_update';
  static const _kSnooze = 'app_update_snooze';
  static const _iosUrl =
      'https://apps.apple.com/tr/app/lig-masas%C4%B1/id6820082632';
  static const _androidUrl =
      'https://play.google.com/store/apps/details?id=com.ligmasasi.app';

  static int? _build;
  static DateTime? _last;
  static OverlayEntry? _entry;
  static bool _forced = false;

  static String? get _platform {
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
  }

  static void start() {
    if (_platform == null) return;
    _check(force: true);
    AppActivity.foreground.addListener(() {
      if (AppActivity.foreground.value) _check();
    });
  }

  static Future<void> _check({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _last != null &&
        now.difference(_last!) < const Duration(minutes: 30)) {
      return;
    }
    _last = now;
    try {
      _build ??= int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
      final build = _build;
      if (build == null) return;
      final row = await Supabase.instance.client
          .from('app_settings')
          .select('value')
          .eq('key', _kSetting)
          .maybeSingle();
      final v = row?['value'];
      final p = v is Map ? v[_platform] : null;
      if (p is! Map) return _hide();
      final latest = (p['latest'] as num?)?.toInt();
      final min = (p['min'] as num?)?.toInt();
      final custom = p['url'];
      final url = custom is String && custom.isNotEmpty
          ? custom
          : (_platform == 'ios' ? _iosUrl : _androidUrl);

      if (min != null && build < min) {
        _show(url: url, forced: true);
      } else if (latest != null && build < latest) {
        if (_forced) _hide();
        if (_entry == null && !await _snoozed(latest)) {
          _show(url: url, forced: false, latest: latest);
        }
      } else {
        _hide();
      }
    } catch (e) {
      debugPrint('app_update: $e');
    }
  }

  static Future<bool> _snoozed(int latest) async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_kSnooze)?.split('|');
    if (s == null || s.length != 2 || s[0] != '$latest') return false;
    final at = DateTime.tryParse(s[1]);
    return at != null &&
        DateTime.now().difference(at) < const Duration(days: 1);
  }

  static Future<void> _snooze(int latest) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kSnooze,
      '$latest|${DateTime.now().toIso8601String()}',
    );
  }

  static void _hide() {
    _entry?.remove();
    _entry = null;
    _forced = false;
  }

  static void _show({required String url, required bool forced, int? latest}) {
    if (_entry != null && _forced == forced) return;
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) {
      // Gezgin henüz kurulmadı (açılış); kısa süre sonra yeniden dene.
      Future.delayed(
        const Duration(seconds: 1),
        () => _show(url: url, forced: forced, latest: latest),
      );
      return;
    }
    _hide();
    _forced = forced;
    void open() =>
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    _entry = OverlayEntry(
      builder: (_) => forced
          ? _ForcedUpdate(onUpdate: open)
          : _UpdateCard(
              onUpdate: open,
              onLater: () {
                _hide();
                if (latest != null) _snooze(latest);
              },
            ),
    );
    overlay.insert(_entry!);
  }
}

/// Kapatılamayan güncelleme penceresi (`min` altı).
class _ForcedUpdate extends StatelessWidget {
  const _ForcedUpdate({required this.onUpdate});

  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.system_update, size: 40, color: cs.secondary),
                  const SizedBox(height: 16),
                  Text(
                    'Uygulamayı kullanmaya devam etmek için yeni sürümü '
                    'yüklemeniz gerekiyor.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onUpdate,
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.secondary,
                        foregroundColor: cs.onSecondary,
                      ),
                      child: const Text('Şimdi Güncelle'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Altta kapatılabilir "Yeni sürüm mevcut" kartı (`latest` altı).
class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.onUpdate, required this.onLater});

  final VoidCallback onUpdate;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Material(
              color: cs.surface,
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(
                  children: [
                    Icon(Icons.system_update, color: cs.secondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Yeni sürüm mevcut',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onLater,
                      child: Text(
                        'Sonra',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                    FilledButton(
                      onPressed: onUpdate,
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.secondary,
                        foregroundColor: cs.onSecondary,
                      ),
                      child: const Text('Güncelle'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
