import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/push/notification_prefs.dart';
import '../../../core/push/push_service.dart';
import '../../follows/follow_list_screen.dart';

/// Ana sayfa bildirim daveti: bildirimler varsayılan kapalı; ayda bir
/// hatırlatılır. Kapatılınca o ay bir daha çıkmaz; bildirimi açmış,
/// futbolcu ya da yönetici olana hiç gösterilmez (notif_invite_needed).
class NotifInviteBanner extends StatefulWidget {
  const NotifInviteBanner({
    super.key,
    required this.leagueId,
    required this.leagueName,
  });

  final String leagueId;
  final String leagueName;

  @override
  State<NotifInviteBanner> createState() => _NotifInviteBannerState();
}

class _NotifInviteBannerState extends State<NotifInviteBanner> {
  static const _kDismissed = 'notif_invite_dismissed_month';
  static bool? _neededCache;

  final _sb = Supabase.instance.client;
  bool _show = false;

  String get _month {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final u = _sb.auth.currentUser;
    if (u == null || u.isAnonymous) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_kDismissed) == _month) return;
      final needed =
          _neededCache ?? (await _sb.rpc('notif_invite_needed')) == true;
      _neededCache = needed;
      if (mounted && needed) setState(() => _show = true);
    } catch (_) {
      // Okunamazsa bant çıkmaz.
    }
  }

  Future<void> _dismiss() async {
    setState(() => _show = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDismissed, _month);
    } catch (_) {}
  }

  Future<void> _openSheet() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF16213A),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _InviteSheet(
        leagueId: widget.leagueId,
        leagueName: widget.leagueName,
      ),
    );
    if (done == true && mounted) {
      _neededCache = false;
      setState(() => _show = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF13233F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2E4A7A)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF1E3A8A),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_active_outlined,
                color: Color(0xFFFDE68A),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Maçlardan haberdar olmak ister misin?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Turnuvayı, takımını ya da oyuncunu seç; yalnız '
                    'seçtiklerinin golü ve sonucu gelsin.',
                    style: TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      onPressed: _openSheet,
                      child: const Text(
                        'Bildirimleri seç',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Kapat',
              onPressed: _dismiss,
              icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.leagueId, required this.leagueName});

  final String leagueId;
  final String leagueName;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  bool _league = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    NotificationPrefsService.followedLeagues().then((s) {
      if (mounted) setState(() => _league = s.contains(widget.leagueId));
    }).catchError((_) {});
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await NotificationPrefsService.setFollowedLeague(
        widget.leagueId,
        _league,
      );
      try {
        await PushService.enable();
      } catch (_) {
        // İzin verilmezse tercih yine kaydedilir; ayarlardan açılabilir.
      }
      await Supabase.instance.client.rpc('notif_opt_in');
      nav.pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Bildirimler açıldı.')),
      );
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    }
  }

  Widget _row(String title, String sub, Widget trailing) => Container(
    constraints: const BoxConstraints(minHeight: 56),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFF24324D))),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                sub,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ],
          ),
        ),
        trailing,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    void follows() => FollowListScreen.open(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Neyi takip etmek istersin?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            _row(
              widget.leagueName,
              'Tüm maçların başlama, gol ve sonucu',
              Switch(
                value: _league,
                onChanged: _busy ? null : (v) => setState(() => _league = v),
              ),
            ),
            _row(
              'Takımlar',
              'Seçtiğin takımın maç sonucu',
              TextButton(onPressed: follows, child: const Text('Seç')),
            ),
            _row(
              'Oyuncular',
              'Seçtiğin oyuncunun golü ve asisti',
              TextButton(onPressed: follows, child: const Text('Seç')),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: const Color(0xFF04130D),
                ),
                onPressed: _busy ? null : _enable,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Bildirimleri aç',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Takım ve oyuncuları Takip Listem\'den yıldızla seçersin. '
              'Ayarlar\'dan her zaman değiştirebilirsin.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
