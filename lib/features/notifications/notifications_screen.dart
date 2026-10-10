import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/notification_center.dart';
import '../../core/widgets/admin_page.dart';
import 'notification_router.dart';

class _Item {
  _Item(Map<String, dynamic> r)
    : id = r['id'].toString(),
      title = (r['title'] ?? '').toString(),
      body = (r['body'] ?? '').toString(),
      kind = (r['kind'] ?? '').toString(),
      refId = r['ref_id']?.toString(),
      createdAt =
          DateTime.tryParse((r['created_at'] ?? '').toString())?.toLocal() ??
          DateTime.now(),
      unread = r['read_at'] == null;

  final String id;
  final String title;
  final String body;
  final String kind;
  final String? refId;
  final DateTime createdAt;

  /// Liste açıldığında okunmamış olanlar (ekranda vurgulu kalır).
  final bool unread;
}

/// Zilden açılan bildirim listesi. Açılınca hepsi okundu sayılır; yeni
/// gelenler bu ekranda vurgulu görünür.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<_Item>? _items;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('notifications')
          .select('id, title, body, kind, ref_id, created_at, read_at')
          .order('created_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _items = [for (final r in rows) _Item(r)];
        _failed = false;
      });
      if (_items!.any((i) => i.unread)) {
        await NotificationCenter.markAllRead();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _open(_Item item) =>
      NotificationRouter.open(context, item.kind, item.refId);

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final Widget body;
    if (items == null && !_failed) {
      body = const Center(child: CircularProgressIndicator());
    } else if (items == null) {
      body = _message('Bildirimler yüklenemedi. Aşağı çekip yenileyin.');
    } else if (items.isEmpty) {
      body = _message('Henüz bildiriminiz yok.');
    } else {
      body = ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) =>
            _Tile(item: items[i], onTap: () => _open(items[i])),
      );
    }
    return AdminPageScaffold(
      title: 'Bildirimler',
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }

  Widget _message(String text) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 120),
      const Icon(
        Icons.notifications_none_rounded,
        size: 56,
        color: Colors.white24,
      ),
      const SizedBox(height: 12),
      Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white60, fontSize: 15),
      ),
    ],
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.onTap});

  final _Item item;
  final VoidCallback onTap;

  static (IconData, Color) _look(String kind) => switch (kind) {
    'result' => (Icons.sports_soccer_rounded, const Color(0xFF22C55E)),
    'schedule' => (Icons.event_rounded, const Color(0xFF3B82F6)),
    'reminder' => (Icons.alarm_rounded, const Color(0xFFF59E0B)),
    'news' => (Icons.article_rounded, const Color(0xFFE11D48)),
    'penalty' => (Icons.gavel_rounded, const Color(0xFFEF4444)),
    'penaltyok' => (Icons.gavel_rounded, const Color(0xFFEF4444)),
    'goal' => (Icons.bolt_rounded, const Color(0xFF10B981)),
    'live' => (Icons.play_circle_outline_rounded, const Color(0xFFF87171)),
    'approval' => (Icons.rule_folder_outlined, const Color(0xFFF59E0B)),
    'roster' => (Icons.groups_rounded, const Color(0xFF3B82F6)),
    _ => (Icons.notifications_rounded, const Color(0xFF64748B)),
  };

  static String _when(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'az önce';
    if (d.inHours < 1) return '${d.inMinutes} dk önce';
    if (d.inDays < 1) return '${d.inHours} sa önce';
    if (d.inDays == 1) return 'dün';
    if (d.inDays < 7) return '${d.inDays} gün önce';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _look(item.kind);
    return Material(
      color: item.unread ? const Color(0xFF1F3A3A) : const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: item.unread
                  ? kAdminAccent.withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: item.unread
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _when(item.createdAt),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    if (item.body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (item.unread)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(left: 8, top: 6),
                  decoration: const BoxDecoration(
                    color: kAdminAccent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
