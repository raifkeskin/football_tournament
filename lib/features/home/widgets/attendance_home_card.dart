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

  /// Akordiyon: açık satır, yanıtı değiştirilen satır, tümü gösterilsin mi.
  String? _openId;
  String? _editingId;
  bool _showAll = false;
  bool _autoOpened = false;

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
    if (_busy != null) return;
    if (p['status'] == status) {
      // Aynı cevap: değiştirmeden kapatılır.
      setState(() {
        _openId = null;
        _editingId = null;
      });
      return;
    }
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
      final prev = p['status'];
      if (prev == 'yes') p['yes_count'] = _count(p, 'yes_count') - 1;
      if (prev == 'no') p['no_count'] = _count(p, 'no_count') - 1;
      p['${status}_count'] = _count(p, '${status}_count') + 1;
      p['status'] = status;
      _openId = null;
      _editingId = null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String _when(Map<String, dynamic> p, {bool withPitch = true}) {
    final d = DateTime.tryParse('${p['date'] ?? ''}');
    final t = '${p['time'] ?? ''}';
    return [
      if (d != null) DateFormat('d MMM EEE', 'tr_TR').format(d),
      if (t.length >= 5) t.substring(0, 5),
      if (withPitch && (p['pitch'] ?? '').toString().isNotEmpty) p['pitch'],
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null || _polls.isEmpty) return const SizedBox.shrink();
    // Cevapsızlar üstte, sonra maç sırası (RPC tarih sırasıyla döner).
    final sorted = [
      ..._polls.where((p) => p['status'] == null),
      ..._polls.where((p) => p['status'] != null),
    ];
    // Tek sorgu cevapsızsa satır açık gelir (bir kez; sonra kişi kapatabilir).
    if (!_autoOpened) {
      _autoOpened = true;
      if (sorted.length == 1 && sorted.first['status'] == null) {
        _openId = '${sorted.first['id']}';
      }
    }
    final single = sorted.length == 1;
    final shown = _showAll || sorted.length <= 3 ? sorted : sorted.take(3);
    final rest = sorted.length - shown.length;
    final todo = sorted.where((p) => p['status'] == null).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.how_to_reg_rounded,
                  color: kAdminAccent,
                  size: 18,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Katılım Durum Sorgulama',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: kAdminAccent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                if (single)
                  _countsButton(sorted.first)
                else
                  Text(
                    todo > 0 ? '$todo yanıt bekliyor' : 'Hepsi yanıtlandı',
                    style: const TextStyle(color: kAdminMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
          for (final (i, p) in shown.indexed) ...[
            if (i > 0 || !single)
              Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
            _row(p, single: single),
          ],
          if (rest > 0) ...[
            Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
            InkWell(
              onTap: () => setState(() => _showAll = true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Text(
                  '+$rest sorgu daha',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: kAdminAccent,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _count(Map<String, dynamic> p, String key) =>
      int.tryParse('${p[key] ?? 0}') ?? 0;

  Widget _dots(Map<String, dynamic> p, {double size = 12.5}) {
    Widget dot(Color c) => Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
    );
    final style = TextStyle(
      color: Colors.white,
      fontSize: size,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(kAdminAccent),
        const SizedBox(width: 4),
        Text('${_count(p, 'yes_count')}', style: style),
        const SizedBox(width: 8),
        dot(kAdminDanger),
        const SizedBox(width: 4),
        Text('${_count(p, 'no_count')}', style: style),
      ],
    );
  }

  /// Tek sorguda başlığın sağı: sayılar; basınca liste.
  Widget _countsButton(Map<String, dynamic> p) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(9),
    child: InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => _showList(p),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.list_rounded, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            _dots(p),
          ],
        ),
      ),
    ),
  );

  Widget _statusPill(String? status) {
    if (status == null) {
      return _pill('Yanıtla', const Color(0xFFFBBF24), const Color(0xFF1A1204));
    }
    final yes = status == 'yes';
    final c = yes ? kAdminAccent : kAdminDanger;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(yes ? Icons.check_rounded : Icons.close_rounded, size: 15, color: c),
          const SizedBox(width: 4),
          Text(
            yes ? 'Geliyorsun' : 'Gelemiyorsun',
            style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) => Container(
    height: 28,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    alignment: Alignment.center,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
    child: Text(
      text,
      style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12.5),
    ),
  );

  Widget _row(Map<String, dynamic> p, {required bool single}) {
    final id = '${p['id']}';
    final status = p['status']?.toString();
    final open = _openId == id;
    final editing = _editingId == id;
    final busy = _busy == id;
    final choose = status == null || editing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() {
            _openId = open ? null : id;
            _editingId = null;
          }),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p['home']} – ${p['away']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _when(p, withPitch: false),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: kAdminMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (!single) ...[
                            const Text(
                              '  ·  ',
                              style: TextStyle(color: kAdminMuted, fontSize: 12),
                            ),
                            _dots(p, size: 12),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _statusPill(status),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(
                    Icons.expand_more_rounded,
                    color: kAdminMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  [
                    '${p['team'] ?? ''}',
                    '${p['pitch'] ?? ''}',
                  ].where((e) => e.isNotEmpty).join(' · '),
                  style: const TextStyle(color: kAdminMuted, fontSize: 12.5),
                ),
                if (choose) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _choice(
                          'Geliyorum',
                          kAdminAccent,
                          status == null || status == 'yes',
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
                if (status != null || !single) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (status != null)
                        _link(
                          editing ? 'Vazgeç' : 'Yanıtı değiştir',
                          () => setState(
                            () => _editingId = editing ? null : id,
                          ),
                        ),
                      const Spacer(),
                      if (!single)
                        TextButton.icon(
                          onPressed: () => _showList(p),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.list_rounded, size: 17),
                          label: const Text(
                            'Liste',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _link(String text, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: kAdminMuted,
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
          decoration: TextDecoration.underline,
          decorationColor: kAdminMuted,
        ),
      ),
    ),
  );

  /// Gelen / gelemeyen / cevapsız listesi (kadrodaki herkes görebilir).
  Future<void> _showList(Map<String, dynamic> p) async {
    final future = Supabase.instance.client.rpc(
      'attendance_summary',
      params: {'p_match_id': p['match_id'], 'p_team_id': p['team_id']},
    );
    var tab = 'yes';
    await showAdminPopup<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setPopup) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: FutureBuilder(
            future: future,
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 160,
                  child: Center(
                    child: CircularProgressIndicator(color: kAdminAccent),
                  ),
                );
              }
              final data = snap.data is Map ? snap.data as Map : const {};
              final players = [
                for (final r in (data['players'] as List? ?? const []))
                  Map<String, dynamic>.from(r as Map),
              ];
              final groups = {
                'yes': players.where((x) => x['status'] == 'yes').toList(),
                'no': players.where((x) => x['status'] == 'no').toList(),
                'none': players.where((x) => x['status'] == null).toList(),
              };
              const labels = {
                'yes': 'Geliyor',
                'no': 'Gelemiyor',
                'none': 'Cevapsız',
              };
              const colors = {
                'yes': kAdminAccent,
                'no': kAdminDanger,
                'none': Colors.white70,
              };
              final list = groups[tab]!;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminDialogHeader(
                    icon: Icons.how_to_reg_rounded,
                    title: 'Katılım Listesi',
                    subtitle: '${p['team']} · ${p['home']} – ${p['away']}',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final k in ['yes', 'no', 'none']) ...[
                        if (k != 'yes') const SizedBox(width: 6),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setPopup(() => tab = k),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: tab == k ? colors[k]! : Colors.white24,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '${groups[k]!.length}',
                                    style: TextStyle(
                                      color: tab == k
                                          ? colors[k]
                                          : Colors.white70,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    labels[k]!,
                                    style: TextStyle(
                                      color: tab == k
                                          ? colors[k]
                                          : kAdminMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(ctx).height * 0.45,
                    ),
                    child: list.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(18),
                            child: Text(
                              'Kimse yok.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: kAdminMuted),
                            ),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final x in list)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${x['name'] ?? ''}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14.5,
                                          ),
                                        ),
                                      ),
                                      if ('${x['id']}' == '${p['player_id']}')
                                        const Text(
                                          'SEN',
                                          style: TextStyle(
                                            color: Color(0xFFFBBF24),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 11,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
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
