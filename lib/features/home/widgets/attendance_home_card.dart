import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';

/// Ana sayfa: oyuncunun açık Katılım Durum Sorgulamaları; "Geliyorum /
/// Gelemiyorum" buradan işaretlenir. Sorgu sonlandırılınca ya da maç
/// başlayınca kart kalkar (attendance_my_polls).
class AttendanceHomeCard extends StatefulWidget {
  const AttendanceHomeCard({super.key, required this.leagueId});

  final String leagueId;

  /// Ana sayfa yenilenince artırılır.
  static final refresh = ValueNotifier<int>(0);

  @override
  State<AttendanceHomeCard> createState() => _AttendanceHomeCardState();
}

class _AttendanceHomeCardState extends State<AttendanceHomeCard> {
  /// Turnuva başına son liste: ekrana dönüşte kart beklemeden görünür.
  static final Map<String, List<Map<String, dynamic>>> _cache = {};

  List<Map<String, dynamic>> _polls = const [];
  String? _busy;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _polls = _cache[widget.leagueId] ?? const [];
    AttendanceHomeCard.refresh.addListener(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = AppSession.of(context).value.user?.id;
    if (uid != _uid) {
      _uid = uid;
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant AttendanceHomeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leagueId != widget.leagueId) {
      _polls = _cache[widget.leagueId] ?? const [];
      _load();
    }
  }

  @override
  void dispose() {
    AttendanceHomeCard.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (_uid == null) {
      if (_polls.isNotEmpty && mounted) setState(() => _polls = const []);
      return;
    }
    final league = widget.leagueId;
    try {
      final rows = await Supabase.instance.client.rpc(
        'attendance_my_polls',
        params: {'p_league_id': league},
      );
      final list = [
        for (final r in (rows as List? ?? const []))
          Map<String, dynamic>.from(r as Map),
      ];
      _cache[league] = list;
      if (mounted && league == widget.leagueId) setState(() => _polls = list);
    } catch (_) {}
  }

  Future<void> _answer(Map<String, dynamic> p, String status) async {
    if (_busy != null || p['status'] == status) return;
    setState(() => _busy = '${p['id']}');
    try {
      await Supabase.instance.client.rpc(
        'attendance_set',
        params: {
          'p_poll_id': p['id'],
          'p_player_id': p['player_id'],
          'p_status': status,
        },
      );
      p['status'] = status;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydedilemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String _when(Map<String, dynamic> p) {
    final d = DateTime.tryParse('${p['date'] ?? ''}');
    final t = '${p['time'] ?? ''}';
    return [
      if (d != null) DateFormat('d MMM EEE', 'tr_TR').format(d),
      if (t.length >= 5) t.substring(0, 5),
      if ((p['pitch'] ?? '').toString().isNotEmpty) p['pitch'],
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null || _polls.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [for (final p in _polls) _card(p)],
    );
  }

  Widget _card(Map<String, dynamic> p) {
    final status = p['status']?.toString();
    final busy = _busy == '${p['id']}';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (status == null ? kAdminAccent : Colors.white24).withValues(
            alpha: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.how_to_reg_rounded, color: kAdminAccent, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Katılım Durum Sorgulama',
                  style: TextStyle(
                    color: kAdminAccent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              if (status == null)
                const Text(
                  'Cevap bekleniyor',
                  style: TextStyle(color: Color(0xFFFBBF24), fontSize: 11.5),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${p['home']} – ${p['away']}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _when(p),
            style: const TextStyle(color: kAdminMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _choice(
                  'Geliyorum',
                  kAdminAccent,
                  status == 'yes',
                  busy ? null : () => _answer(p, 'yes'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _choice(
                  'Gelemiyorum',
                  kAdminDanger,
                  status == 'no',
                  busy ? null : () => _answer(p, 'no'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _choice(String label, Color color, bool on, VoidCallback? onTap) {
    return Material(
      color: on ? color : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? color : Colors.white24, width: 1.5),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
