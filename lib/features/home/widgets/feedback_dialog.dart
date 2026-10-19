import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/active_tournament.dart';
import '../../../core/services/error_reporter.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';

/// Menüdeki "Sorun Bildir / Öneri Gönder": mesaj `send_feedback` ile
/// kaydedilir, yöneticiye Telegram'dan bildirilir. Ad ve telefon sunucuda
/// hesaptan eklenir.
Future<void> showFeedbackDialog(BuildContext context, {String? role}) async {
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => _FeedbackDialog(role: role),
  );
  if (sent == true && context.mounted) {
    await showAdminInfoDialog(
      context: context,
      icon: Icons.check_circle_rounded,
      iconColor: kAdminAccent,
      title: 'Teşekkürler',
      message: 'Mesajınız bize ulaştı. Gerekirse sizinle iletişime geçeceğiz.',
    );
  }
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog({this.role});

  final String? role;

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.length < 3) {
      setState(() => _error = 'Lütfen mesajınızı yazın.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'send_feedback',
        params: {
          'p_message': text,
          'p_platform': ErrorReporter.platform,
          'p_app_version': ErrorReporter.version,
          'p_role': widget.role,
          'p_league_name': ActiveTournament.theme.value?.name,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message.startsWith('Çok fazla')
              ? e.message
              : 'Gönderilemedi, lütfen tekrar deneyin.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Gönderilemedi, bağlantınızı kontrol edin.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: AdminDialogCloseOverlay(
        onClose: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: adminDialogDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AdminDialogHeader(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Sorun Bildir / Öneri Gönder',
                subtitle: 'Gördüğünüz bir hatayı ya da önerinizi yazın.',
              ),
              const SizedBox(height: 18),
              AdminFieldGroup(
                children: [
                  AdminFieldRow(
                    icon: Icons.edit_note_rounded,
                    label: 'Mesajınız',
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      minLines: 4,
                      maxLines: 8,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: adminInlineInputDecoration(
                        hint: 'Örn. Maç takviminde saat yanlış görünüyor',
                      ).copyWith(counterText: ''),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: kAdminDanger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              AdminPrimaryButton(
                label: 'GÖNDER',
                icon: Icons.send_rounded,
                busy: _busy,
                onPressed: _busy ? null : _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
