import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/admin_page.dart';
import '../services/live_draw_service.dart';

/// Yönetim Paneli › Canlı Kuralar: hangi turnuva, sezon ve grup için kura
/// çekildiği; planlı / süren kurayı iptal, tamamlanmış kurayı geri alma
/// (kuranın yazdığı maçlar silinir, grup yeniden kuraya açılır).
class AdminLiveDrawsScreen extends StatefulWidget {
  const AdminLiveDrawsScreen({super.key});

  @override
  State<AdminLiveDrawsScreen> createState() => _AdminLiveDrawsScreenState();
}

class _AdminLiveDrawsScreenState extends State<AdminLiveDrawsScreen> {
  List<LiveDrawSummary>? _draws;
  String? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await LiveDrawService.instance.list();
      if (!mounted) return;
      setState(() {
        _draws = list;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Kuralar yüklenemedi: $e');
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _place(LiveDrawSummary d) => [
    d.leagueName,
    d.seasonName,
    if ((d.regionName ?? '').isNotEmpty) d.regionName!,
    d.groupName,
  ].where((e) => e.isNotEmpty).join(' · ');

  Future<void> _cancel(LiveDrawSummary d) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Kurayı İptal Et',
      message:
          '${_place(d)}\n\nKura iptal edilir ve kura haberi yayından kalkar. '
          'Fikstüre maç yazılmaz.',
      confirmLabel: 'İPTAL ET',
      icon: Icons.cancel_rounded,
    );
    if (!ok) return;
    await _run(d, () async {
      await LiveDrawService.instance.cancel(d.id);
      _toast('Kura iptal edildi.');
    });
  }

  Future<void> _revert(LiveDrawSummary d) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Kurayı Geri Al',
      message:
          '${_place(d)}\n\nKuranın fikstüre yazdığı ${d.drawMatches} maç '
          'silinir ve kura haberi yayından kalkar. Grup için yeniden kura '
          'çekilebilir.',
      confirmLabel: 'GERİ AL',
      icon: Icons.undo_rounded,
    );
    if (!ok) return;
    await _run(d, () async {
      final n = await LiveDrawService.instance.revert(d.id);
      _toast('Kura geri alındı, $n maç silindi.');
    });
  }

  Future<void> _run(LiveDrawSummary d, Future<void> Function() action) async {
    setState(() => _busyId = d.id);
    try {
      await action();
    } on PostgrestException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('İşlem yapılamadı: $e');
    }
    if (!mounted) return;
    setState(() => _busyId = null);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final draws = _draws;
    final Widget body;
    if (_error != null) {
      body = _Message(text: _error!);
    } else if (draws == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (draws.isEmpty) {
      body = const _Message(text: 'Henüz canlı kura çekilmemiş.');
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          itemCount: draws.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final d = draws[i];
            return _DrawCard(
              draw: d,
              place: _place(d),
              busy: _busyId == d.id,
              onCancel: _busyId == null ? () => _cancel(d) : null,
              onRevert: _busyId == null ? () => _revert(d) : null,
            );
          },
        ),
      );
    }
    return AdminPageScaffold(title: 'Canlı Kuralar', body: body);
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white60, fontSize: 14),
      ),
    ),
  );
}

class _DrawCard extends StatelessWidget {
  const _DrawCard({
    required this.draw,
    required this.place,
    required this.busy,
    required this.onCancel,
    required this.onRevert,
  });

  final LiveDrawSummary draw;
  final String place;
  final bool busy;
  final VoidCallback? onCancel;
  final VoidCallback? onRevert;

  static const _card = Color(0xFF1E293B);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (draw.status) {
      'scheduled' => ('Planlandı', const Color(0xFF60A5FA)),
      'running' => ('Sürüyor', const Color(0xFFEF4444)),
      'done' => ('Tamamlandı', kAdminAccent),
      _ => ('İptal edildi', Colors.white38),
    };
    final when = DateFormat('d MMMM yyyy, HH:mm', 'tr_TR').format(draw.startAt);
    final info = <String>[
      '${draw.teamCount} takım',
      if (draw.status == 'done')
        '${draw.drawMatches} maç fikstürde'
      else
        '${draw.totalMatches} maç',
      if (draw.startedMatches > 0) '${draw.startedMatches} maç başladı',
    ].join(' · ');

    Widget? action;
    if (busy) {
      action = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      );
    } else if (draw.status == 'scheduled' || draw.status == 'running') {
      action = OutlinedButton.icon(
        onPressed: onCancel,
        icon: const Icon(Icons.cancel_rounded, size: 18),
        label: const Text('İptal et'),
        style: OutlinedButton.styleFrom(
          foregroundColor: kAdminDanger,
          side: BorderSide(color: kAdminDanger.withValues(alpha: 0.6)),
        ),
      );
    } else if (draw.status == 'done' &&
        draw.drawMatches > 0 &&
        draw.startedMatches == 0) {
      action = OutlinedButton.icon(
        onPressed: onRevert,
        icon: const Icon(Icons.undo_rounded, size: 18),
        label: const Text('Kurayı geri al'),
        style: OutlinedButton.styleFrom(
          foregroundColor: kAdminDanger,
          side: BorderSide(color: kAdminDanger.withValues(alpha: 0.6)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  when,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            place,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            info,
            style: const TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
          if (draw.status == 'done' && draw.startedMatches > 0) ...[
            const SizedBox(height: 6),
            const Text(
              'Maçlar başladığı için kura geri alınamaz.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: action),
          ],
        ],
      ),
    );
  }
}
