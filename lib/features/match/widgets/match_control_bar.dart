import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../models/match.dart';

/// Maç yönetimi şeridi (yalnız maçı yönetebilenler: admin, turnuva sahibi,
/// bölge sorumlusu, gözlemci). Olay girişi, devreler ve skor tek kişinin
/// ekranında açıktır; diğerleri kimin yönettiğini görür ve devir ister,
/// yöneten onaylar. Kurallar veritabanında (match_control_* RPC'leri):
/// gözlemci girince yönetim boşsa ona geçer; devir isteğine 30 sn cevap
/// gelmezse ya da yöneten 2 dk görünmezse onaysız devralınır.
class MatchControlBar extends StatefulWidget {
  const MatchControlBar({
    super.key,
    required this.match,
    required this.onChanged,
  });

  final MatchModel match;

  /// Yönetim bende mi (giriş düğmeleri buna göre açılır).
  final ValueChanged<bool> onChanged;

  @override
  State<MatchControlBar> createState() => _MatchControlBarState();
}

class _MatchControlBarState extends State<MatchControlBar> {
  static const _info = Color(0xFF60A5FA);
  static const _amber = Color(0xFFFBBF24);
  final _sb = Supabase.instance.client;

  Map<String, dynamic>? _s;
  Timer? _poll;
  bool _busy = false;
  bool _autoTried = false;
  bool _dialogOpen = false;
  bool? _lastMine;

  @override
  void initState() {
    super.initState();
    _load();
    // Devir isteği ve el değiştirme birkaç saniyede görünsün.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  String get _id => widget.match.id;

  void _apply(dynamic raw) {
    if (!mounted || raw is! Map) return;
    final s = Map<String, dynamic>.from(raw);
    final mine = s['mine'] == true;
    final was = _lastMine;
    setState(() => _s = s);
    if (was != mine) {
      _lastMine = mine;
      widget.onChanged(mine);
      if (was == true && !mine) {
        _snack(
          'Maçın yönetimi ${s['controller_name'] ?? 'başka bir sorumluya'} geçti.',
        );
      }
    }
    // Gözlemci öncelikli: yönetim boşsa gözlemciye kendiliğinden geçer.
    if (!_autoTried && s['controller'] == null && s['observer'] == true) {
      _autoTried = true;
      _call('match_control_take');
    }
    if (mine && s['req_user'] != null && !_dialogOpen) {
      _showRequest(s);
    }
  }

  Future<void> _load() async {
    if (_busy) return;
    try {
      _apply(await _sb.rpc('match_control_state', params: {'p_match_id': _id}));
    } catch (_) {}
  }

  Future<void> _call(String fn, {Map<String, dynamic>? extra}) async {
    setState(() => _busy = true);
    try {
      _apply(await _sb.rpc(fn, params: {'p_match_id': _id, ...?extra}));
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('İşlem yapılamadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Yönetenin ekranında: devir isteği, 30 sn geri sayımla.
  Future<void> _showRequest(Map<String, dynamic> s) async {
    _dialogOpen = true;
    final name = (s['req_name'] ?? 'Bir sorumlu').toString();
    var left = (s['req_left'] as num?)?.toInt() ?? 30;
    Timer? tick;
    final approve = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
            left--;
            if (left <= 0) {
              tick?.cancel();
              if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
              return;
            }
            setD(() {});
          });
          return AlertDialog(
            backgroundColor: const Color(0xFF111A2C),
            title: Text(
              '$name yönetimi devralmak istiyor',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Onaylarsan olay girişi $name\'e geçer; sen maçı izlemeye '
                  'devam edersin. Cevap vermezsen $left sn sonra onaysız '
                  'devralabilir.',
                  style: const TextStyle(color: kAdminMuted, height: 1.4),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: left / 30,
                    minHeight: 5,
                    color: _amber,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Reddet'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kAdminAccent),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Onayla, devret'),
              ),
            ],
          );
        },
      ),
    );
    tick?.cancel();
    if (approve != null) {
      await _call('match_control_answer', extra: {'p_approve': approve});
    }
    _dialogOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const SizedBox.shrink();
    final mine = s['mine'] == true;
    final ctrl = s['controller'];
    final name = (s['controller_name'] ?? '').toString();

    if (ctrl == null) {
      return _frame(
        color: Colors.white24,
        icon: Icons.sports_rounded,
        title: 'Maçı şu an kimse yönetmiyor',
        subtitle: 'Olay girmek için yönetimi alın.',
        action: _button(
          'Maçı yönet',
          kAdminAccent,
          () => _call('match_control_take'),
        ),
      );
    }
    if (mine) {
      // Yer kaplamasın: küçük rozet; devre butonları yanında durur.
      return Container(
        height: 32,
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          color: kAdminAccent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: kAdminAccent.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sports_rounded, color: kAdminAccent, size: 15),
            const SizedBox(width: 5),
            const Flexible(
              child: Text(
                'Yönetiyorsun',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF9FE8C9),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _busy ? null : () => _call('match_control_release'),
              child: const Text(
                'Bırak',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (s['req_mine'] == true) {
      return _frame(
        color: _amber,
        icon: Icons.hourglass_top_rounded,
        title: '$name onayı bekleniyor',
        subtitle: 'Devir isteği gönderildi · ${s['req_left'] ?? ''} sn',
        action: _button(
          'Geri çek',
          Colors.white24,
          () => _call('match_control_cancel'),
          outlined: true,
        ),
      );
    }
    final online = s['online'] == true;
    final force = s['can_force'] == true;
    return _frame(
      color: _info,
      icon: Icons.lock_outline_rounded,
      title: 'Maçı $name yönetiyor',
      subtitle: online
          ? 'Çevrimiçi · giriş düğmeleri yalnız onda açık'
          : '2 dakikadır görünmüyor',
      action: force
          ? _button('Devral', kAdminAccent, () => _call('match_control_take'))
          : _button('Devral', _info, () => _call('match_control_request')),
    );
  }

  Widget _frame({
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget action,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kAdminMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          action,
        ],
      ),
    );
  }

  Widget _button(
    String label,
    Color color,
    VoidCallback onTap, {
    bool outlined = false,
  }) {
    return SizedBox(
      height: 34,
      child: outlined
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: color),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: _busy ? null : onTap,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: color == kAdminAccent
                    ? const Color(0xFF052E22)
                    : const Color(0xFF06213F),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: _busy ? null : onTap,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
    );
  }
}
