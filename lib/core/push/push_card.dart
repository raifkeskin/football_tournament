import 'package:flutter/material.dart';

import '../widgets/admin_form.dart';
import '../widgets/admin_page.dart';
import '../../features/notifications/notification_settings_screen.dart';
import 'push_service.dart';

/// Profildeki bildirim kartı: izin/abonelik durumuna göre aç-kapat ya da
/// yönlendirme (iPhone'da "Ana Ekrana Ekle", engellenmişse ayarlar).
class PushCard extends StatefulWidget {
  const PushCard({super.key, this.showSettingsLink = true});

  /// Kartın altında "Bildirim ayarları" bağlantısı (ayarlar ekranının
  /// kendisinde gösterilmez).
  final bool showSettingsLink;

  @override
  State<PushCard> createState() => _PushCardState();
}

class _PushCardState extends State<PushCard> {
  PushState _state = PushService.state();
  bool _subscribed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh(resync: true);
  }

  Future<void> _refresh({bool resync = false}) async {
    final state = PushService.state();
    final subscribed =
        state == PushState.granted && await PushService.isSubscribed();
    if (resync && subscribed) await PushService.resync();
    if (!mounted) return;
    setState(() {
      _state = state;
      _subscribed = subscribed;
    });
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      final denied = e.toString().contains('permission-denied');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            denied ? 'Bildirim izni verilmedi.' : 'Bildirimler açılamadı: $e',
          ),
        ),
      );
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = _card();
    if (!widget.showSettingsLink) return card ?? const SizedBox.shrink();
    final link = Material(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => NotificationSettingsScreen.open(context),
        child: const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 10, 12),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, color: kAdminAccent),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Bildirim ayarları',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
    if (card == null) return link;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [card, const SizedBox(height: 8), link],
    );
  }

  Widget? _card() {
    if (_state == PushState.unsupported) return null;

    final on = _state == PushState.granted && _subscribed;
    final String title;
    final String text;
    Widget? action;
    switch (_state) {
      case PushState.iosInstall:
        title = 'Bildirimler';
        text =
            'iPhone\'da bildirim almak için Safari\'de Paylaş → "Ana Ekrana '
            'Ekle" ile uygulamayı ekleyin ve ana ekrandaki simgeden açın.';
      case PushState.denied:
        title = 'Bildirimler engellendi';
        text =
            'Bildirim izni bu tarayıcıda kapalı. Tarayıcı / site ayarlarından '
            'bildirimlere izin verip sayfayı yenileyin.';
      default:
        title = on ? 'Bildirimler açık' : 'Bildirimleri aç';
        text = on
            ? 'Bu cihaz bildirim alıyor. Hangi bildirimlerin geleceğini '
                  'ayarlardan seçebilirsiniz.'
            : 'Maç saati, gol, maç sonucu ve haberler için bu cihazda '
                  'bildirim alın.';
        action = _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: kAdminAccent,
                ),
              )
            : TextButton(
                onPressed: () => on
                    ? _run(PushService.disable, 'Bildirimler kapatıldı.')
                    : _run(PushService.enable, 'Bildirimler açıldı.'),
                style: TextButton.styleFrom(
                  foregroundColor: on ? Colors.white70 : kAdminAccent,
                ),
                child: Text(on ? 'Kapat' : 'Aç'),
              );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(
            on
                ? Icons.notifications_active_outlined
                : Icons.notifications_none_rounded,
            color: on ? kAdminAccent : kAdminMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(color: kAdminMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 6), action],
        ],
      ),
    );
  }
}
