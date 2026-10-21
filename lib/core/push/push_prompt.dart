import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'native_push.dart';
import 'push_service.dart';

/// Ne zaman soruldu: girişten sonra ana ekranda ya da ilk takım takibinde.
enum PushPromptReason { login, follow }

/// "Bildirimlere izin ver" sorusu (uygulama sürümü). Her neden için cihaz
/// başına bir kez sorulur; bildirim zaten açıksa ya da kullanıcı izni
/// engellemişse hiç çıkmaz (engelliyse profildeki kart yönlendirir).
class PushPrompt {
  PushPrompt._();

  static bool _showing = false;

  static Future<void> maybeShow(
    BuildContext context,
    PushPromptReason reason,
  ) async {
    if (!NativePush.supported || _showing) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (reason == PushPromptReason.login &&
        (user == null || user.isAnonymous)) {
      return;
    }
    final key = 'push_prompt_${reason.name}';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(key) ?? false) return;
    await PushService.refresh();
    if (PushService.state() == PushState.denied) return;
    if (await PushService.isSubscribed()) return;
    await prefs.setBool(key, true);
    if (!context.mounted) return;
    _showing = true;
    try {
      await _sheet(context, reason);
    } finally {
      _showing = false;
    }
  }

  static Future<void> _sheet(
    BuildContext context,
    PushPromptReason reason,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final allow = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (c) {
        final cs = Theme.of(c).colorScheme;
        Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(text)),
            ],
          ),
        );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.notifications_active_rounded,
                  size: 40,
                  color: cs.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  reason == PushPromptReason.follow
                      ? 'Takımının maçlarını kaçırma'
                      : 'Maçlarından anında haberin olsun',
                  textAlign: TextAlign.center,
                  style: Theme.of(c).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                line(Icons.sports_soccer_rounded, 'Goller ve maç sonuçları'),
                line(Icons.event_rounded, 'Maç saati ve değişiklikler'),
                line(Icons.how_to_reg_rounded, 'Katılım sorgusu ve esame'),
                line(Icons.article_rounded, 'Turnuva haberleri'),
                const SizedBox(height: 8),
                Text(
                  'Hangi bildirimlerin geleceğini daha sonra Bildirim '
                  'Ayarları\'ndan seçebilirsin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Bildirimlere izin ver'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Şimdi değil'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (allow != true) return;
    try {
      await PushService.enable();
      messenger.showSnackBar(
        const SnackBar(content: Text('Telefon bildirimleri açıldı.')),
      );
    } catch (e) {
      final denied = e.toString().contains('permission-denied');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            denied
                ? 'İzin verilmedi. Daha sonra profilinden açabilirsin.'
                : 'Bildirimler açılamadı. Profilinden tekrar deneyebilirsin.',
          ),
        ),
      );
    }
  }
}
