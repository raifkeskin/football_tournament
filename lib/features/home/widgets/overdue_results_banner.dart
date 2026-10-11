import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../match/models/match.dart';
import '../../match/screens/match_details_screen.dart';

/// Sonucu girilmemiş maç (maç saatinden 2 saat geçmiş, bitmemiş).
class _Overdue {
  _Overdue(Map<String, dynamic> r)
    : id = r['id'].toString(),
      home = (r['home_name'] ?? 'Ev Sahibi').toString(),
      away = (r['away_name'] ?? 'Deplasman').toString(),
      date = DateTime.tryParse((r['match_date'] ?? '').toString()),
      time = (r['match_time'] ?? '').toString();

  final String id;
  final String home;
  final String away;
  final DateTime? date;
  final String time;

  String get when {
    final d = date;
    final t = time.length >= 5 ? time.substring(0, 5) : time;
    if (d == null) return t;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} $t';
  }
}

/// Ana sayfada sorumlulara (admin, kurucu, bölge sorumlusu) "N maçın
/// sonucu girilmedi" uyarısı. Dokununca maçlar listelenir, maça dokununca
/// maç detayı açılır (sağ alttaki menüden hızlı skor ya da maç detayı).
/// Sonuçlar girilince kendiliğinden kaybolur. Diğer kullanıcılar için hiç
/// istek atılmaz.
class OverdueResultsBanner extends StatefulWidget {
  const OverdueResultsBanner({super.key, required this.leagueId});

  final String leagueId;

  /// Ana sayfa yenilenince uyarı da yeniden okunur.
  static final refresh = ValueNotifier<int>(0);

  @override
  State<OverdueResultsBanner> createState() => _OverdueResultsBannerState();
}

class _OverdueResultsBannerState extends State<OverdueResultsBanner> {
  static const _amber = Color(0xFFF59E0B);

  /// Turnuva başına son liste: ekrana dönüşte uyarı beklemeden görünür.
  static final Map<String, List<_Overdue>> _cache = {};

  List<_Overdue> _items = const [];
  Timer? _timer;
  bool _canSee = false;

  @override
  void initState() {
    super.initState();
    _items = _cache[widget.leagueId] ?? const [];
    OverdueResultsBanner.refresh.addListener(_load);
    // Maç saati geçtikçe yeni maçlar listeye girer.
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppSession.of(context).value;
    final canSee = s.isAdmin || s.isLeagueOwner || s.ownedRegions.isNotEmpty;
    if (canSee != _canSee) {
      _canSee = canSee;
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant OverdueResultsBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leagueId != widget.leagueId) {
      _items = _cache[widget.leagueId] ?? const [];
      _load();
    }
  }

  @override
  void dispose() {
    OverdueResultsBanner.refresh.removeListener(_load);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_canSee) {
      if (_items.isNotEmpty && mounted) setState(() => _items = const []);
      return;
    }
    final league = widget.leagueId;
    try {
      final rows = await Supabase.instance.client.rpc(
        'overdue_result_matches',
        params: {'p_league_id': league},
      );
      final list = [
        for (final r in (rows as List? ?? const []))
          _Overdue(Map<String, dynamic>.from(r as Map)),
      ];
      _cache[league] = list;
      if (mounted && league == widget.leagueId) setState(() => _items = list);
    } catch (_) {
      // Uyarı gösterilemezse ana sayfa etkilenmez.
    }
  }

  Future<void> _openMatch(_Overdue o) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final row = await Supabase.instance.client
          .from('matches')
          .select()
          .eq('id', o.id)
          .single();
      if (!mounted) return;
      await nav.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'MatchDetailsScreen'),
          builder: (_) => MatchDetailsScreen(
            match: MatchModel.fromMap(row, o.id),
            isAdmin: AppSession.of(context).value.isAdmin,
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Maç açılamadı: $e')));
    }
    await _load();
  }

  Future<void> _openList() async {
    final picked = await showModalBottomSheet<_Overdue>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(c).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text(
                  'Sonucu girilmemiş maçlar',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  'Maça dokunun; sağ alttaki menüden hızlı skor girin ya da '
                  'maç detayını girip maçı tamamlayın.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final o = _items[i];
                    return Material(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onTap: () => Navigator.pop(c, o),
                        leading: const Icon(
                          Icons.pending_actions_rounded,
                          color: _amber,
                        ),
                        title: Text(
                          '${o.home} – ${o.away}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          o.when,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white54,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) await _openMatch(picked);
  }

  @override
  Widget build(BuildContext context) {
    if (!_canSee || _items.isEmpty) return const SizedBox.shrink();
    final n = _items.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Material(
        color: _amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: n == 1 ? () => _openMatch(_items.first) : _openList,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _amber.withValues(alpha: 0.55)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: _amber),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n == 1
                            ? 'Maç sonucu girilmedi'
                            : '$n maçın sonucu girilmedi',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        n == 1
                            ? '${_items.first.home} – ${_items.first.away} · '
                                  '${_items.first.when}'
                            : 'Hızlı skor girin ya da maç detayını tamamlayın',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: _amber),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
