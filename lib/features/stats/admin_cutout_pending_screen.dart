import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/admin_page.dart';
import '../../core/widgets/web_safe_image.dart';

const _card = Color(0xFF1E293B);
const _muted = Color(0xFF94A3B8);
const _soft = Color(0xFFE2E8F0);
const _accent = Color(0xFF10B981);
const _warn = Color(0xFFF59E0B);

/// Admin Dekupe Bekleyenler: fotoğrafı olup dizilişte dekupesi olmayan
/// oyuncular (admin_cutout_pending). Dekupe Mac'te betikle üretilir;
/// üretilemeyenler (yüz yok / düşük çözünürlük) ayrı bölümde, sebebiyle.
class AdminCutoutPendingScreen extends StatefulWidget {
  const AdminCutoutPendingScreen({super.key});

  @override
  State<AdminCutoutPendingScreen> createState() =>
      _AdminCutoutPendingScreenState();
}

class _AdminCutoutPendingScreenState extends State<AdminCutoutPendingScreen> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final r = await Supabase.instance.client.rpc('admin_cutout_pending');
    return [
      for (final e in (r as List? ?? const []))
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  /// Kullanılamayan fotoğrafı kaldırır; hesabı olan oyuncuya bildirim gider.
  Future<void> _remove(Map<String, dynamic> r) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Fotoğrafı kaldır',
      message:
          '${r['full_name']} oyuncusunun fotoğrafı kaldırılacak. Hesabı varsa '
          'yeni fotoğraf yüklemesi için bildirim gider.',
      confirmLabel: 'KALDIR',
      cancelLabel: 'VAZGEÇ',
      icon: Icons.hide_image_outlined,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client.rpc(
        'admin_remove_player_photo',
        params: {'p_player_id': r['player_id']},
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Fotoğraf kaldırıldı.')),
      );
      await _refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Kaldırılamadı: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Dekupe Bekleyenler',
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                'Okunamadı: ${snap.error}',
                style: const TextStyle(color: _muted),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _accent),
            );
          }
          final pending = [
            for (final r in snap.data!)
              if ((r['skip_reason'] ?? '').toString().isEmpty) r,
          ];
          final skipped = [
            for (final r in snap.data!)
              if ((r['skip_reason'] ?? '').toString().isNotEmpty) r,
          ];
          return RefreshIndicator(
            color: _accent,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
              children: [
                _note(),
                _section('BEKLEYEN · ${pending.length}'),
                if (pending.isEmpty)
                  _empty('Bekleyen yok, tüm fotoğrafların dekupesi hazır.')
                else
                  for (final r in pending) _row(r),
                if (skipped.isNotEmpty) ...[
                  _section('ÜRETİLEMEDİ · ${skipped.length}'),
                  for (final r in skipped) _row(r),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _note() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Text(
      'Fotoğrafı yeni eklenen ya da değişen oyuncular dekupe üretilene kadar '
      'dizilişte daire görünür. Dekupe Mac\'te üretilir: '
      'python3 scripts/make_cutouts.py --all --apply',
      style: TextStyle(color: _muted, fontSize: 13, height: 1.35),
    ),
  );

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
    child: Text(
      t,
      style: const TextStyle(
        color: _muted,
        fontSize: 12.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    ),
  );

  Widget _empty(String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
    child: Text(t, style: const TextStyle(color: _muted, fontSize: 14)),
  );

  Widget _row(Map<String, dynamic> r) {
    final reason = (r['skip_reason'] ?? '').toString();
    final team = (r['team_name'] ?? '').toString();
    final changed = DateTime.tryParse(
      (r['photo_changed_at'] ?? '').toString(),
    )?.toLocal();
    final sub = [
      if (team.isNotEmpty) team,
      if (reason.isNotEmpty)
        reason
      else if (changed != null)
        '${changed.day.toString().padLeft(2, '0')}.'
            '${changed.month.toString().padLeft(2, '0')} '
            '${changed.hour.toString().padLeft(2, '0')}:'
            '${changed.minute.toString().padLeft(2, '0')}',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          WebSafeImage(
            url: (r['photo_url'] ?? '').toString(),
            width: 44,
            height: 44,
            isCircle: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (r['full_name'] ?? '').toString(),
                  style: const TextStyle(
                    color: _soft,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: TextStyle(
                      color: reason.isNotEmpty ? _warn : _muted,
                      fontSize: 12.5,
                    ),
                  ),
              ],
            ),
          ),
          if (reason.isNotEmpty)
            IconButton(
              tooltip: 'Fotoğrafı kaldır',
              onPressed: () => _remove(r),
              icon: const Icon(Icons.hide_image_outlined, color: _warn),
            ),
        ],
      ),
    );
  }
}
