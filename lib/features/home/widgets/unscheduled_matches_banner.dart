import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/app_session.dart';
import '../../match/models/match.dart';
import '../../../core/widgets/admin_form.dart';
import '../../match/widgets/match_schedule_dialog.dart';

/// Oynanacak haftada tarihi ya da stadı girilmemiş maç.
class _Unscheduled {
  _Unscheduled(Map<String, dynamic> r)
    : id = r['id'].toString(),
      home = (r['home_name'] ?? 'Ev Sahibi').toString(),
      away = (r['away_name'] ?? 'Deplasman').toString(),
      week = (r['week'] as num?)?.toInt(),
      date = DateTime.tryParse((r['match_date'] ?? '').toString()),
      time = (r['match_time'] ?? '').toString(),
      noDate = r['missing_date'] == true,
      noPitch = r['missing_pitch'] == true;

  final String id;
  final String home;
  final String away;
  final int? week;
  final DateTime? date;
  final String time;
  final bool noDate;
  final bool noPitch;

  /// "Tarih ve stad girilmedi" / "Stad seçilmedi" / "Tarih girilmedi".
  String get missing => noDate && noPitch
      ? 'Tarih ve stad girilmedi'
      : noPitch
      ? 'Stad seçilmedi'
      : 'Tarih girilmedi';

  String get when {
    final d = date;
    final t = time.length >= 5 ? time.substring(0, 5) : time;
    if (d == null) return missing;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} $t · $missing'.trim();
  }
}

/// Ana sayfada maçın yöneticilerine (admin, kurucu, bölge sorumlusu)
/// "N maçta tarih/stad girilmedi" uyarısı (oynanacak hafta); maça dokununca
/// maç detayı açılır (Tarih Gir / Stad Seç). Girilince kendiliğinden kaybolur.
class UnscheduledMatchesBanner extends StatefulWidget {
  const UnscheduledMatchesBanner({super.key, required this.leagueId});

  final String leagueId;

  static final refresh = ValueNotifier<int>(0);

  @override
  State<UnscheduledMatchesBanner> createState() =>
      _UnscheduledMatchesBannerState();
}

class _UnscheduledMatchesBannerState extends State<UnscheduledMatchesBanner> {
  static const _yellow = Color(0xFFFB923C);
  static final Map<String, List<_Unscheduled>> _cache = {};

  List<_Unscheduled> _items = const [];
  bool _canSee = false;

  @override
  void initState() {
    super.initState();
    _items = _cache[widget.leagueId] ?? const [];
    UnscheduledMatchesBanner.refresh.addListener(_load);
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
  void didUpdateWidget(covariant UnscheduledMatchesBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.leagueId != widget.leagueId) {
      _items = _cache[widget.leagueId] ?? const [];
      _load();
    }
  }

  @override
  void dispose() {
    UnscheduledMatchesBanner.refresh.removeListener(_load);
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
        'unscheduled_matches',
        params: {'p_league_id': league},
      );
      final list = [
        for (final r in (rows as List? ?? const []))
          _Unscheduled(Map<String, dynamic>.from(r as Map)),
      ];
      _cache[league] = list;
      if (mounted && league == widget.leagueId) setState(() => _items = list);
    } catch (_) {
      // Uyarı gösterilemezse ana sayfa etkilenmez.
    }
  }

  /// Maçın tarih / saat / saha pencereni (standart popup) açar; maç
  /// detayına gidilmez.
  Future<void> _openMatch(_Unscheduled u) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final row = await Supabase.instance.client
          .from('matches')
          .select()
          .eq('id', u.id)
          .single();
      if (!mounted) return;
      await showMatchScheduleDialog(
        context,
        match: MatchModel.fromMap(row, u.id),
        onDataChanged: _load,
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Maç açılamadı: $e')));
    }
    await _load();
  }

  Future<void> _openList() async {
    final picked = await showAdminOptionPicker<_Unscheduled>(
      context: context,
      title: 'Tarihi ya da stadı eksik maçlar',
      items: _items,
      labelBuilder: (u) => '${u.home} – ${u.away} · ${u.when}',
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
        color: _yellow.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: n == 1 ? () => _openMatch(_items.first) : _openList,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _yellow.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: _yellow,
                  child: Icon(
                    Icons.edit_calendar_rounded,
                    size: 17,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n == 1
                            ? _items.first.missing
                            : '$n maçta tarih ya da stad eksik',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        n == 1
                            ? '${_items.first.home} – ${_items.first.away}'
                            : [
                                if (_items.first.week != null)
                                  '${_items.first.week}. hafta',
                                'dokun, tarih gir / stad seç',
                              ].join(' · '),
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
                const Icon(Icons.chevron_right_rounded, color: _yellow),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
