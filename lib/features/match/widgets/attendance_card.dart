import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../models/match.dart';

/// Kişisel bağlantı sayfası (web/katilim.html).
const _linkBase = 'https://ligmasasi.com/katilim';

/// Katılım Durum Sorgulama: takım sorumlusu maç öncesi kadrosuna sorar;
/// oyuncu buradan ya da WhatsApp'tan gelen kişisel bağlantısından
/// "Geliyorum / Gelemiyorum" işaretler. Başkası adına yalnızca sorumlu
/// işaretler (veritabanı da denetler). Yetkisi olmayana hiçbir şey çizmez.
class AttendanceCard extends StatefulWidget {
  const AttendanceCard({
    super.key,
    required this.match,
    required this.teamId,
    required this.teamName,
    required this.rivalName,
  });

  final MatchModel match;
  final String teamId;
  final String teamName;
  final String rivalName;

  @override
  State<AttendanceCard> createState() => _AttendanceCardState();
}

class _AttendanceCardState extends State<AttendanceCard> {
  final _sb = Supabase.instance.client;
  _Summary? _s;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _sb.rpc(
        'attendance_summary',
        params: {'p_match_id': widget.match.id, 'p_team_id': widget.teamId},
      );
      if (!mounted) return;
      setState(() => _s = raw is Map ? _Summary.fromJson(raw) : null);
    } catch (_) {
      // Sorgu özelliği yoksa ya da yetki yoksa kart görünmez.
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('İşlem yapılamadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _open() => _run(
    () => _sb.rpc(
      'attendance_open',
      params: {'p_match_id': widget.match.id, 'p_team_id': widget.teamId},
    ),
  );

  Future<void> _set(String playerId, String? status) => _run(
    () => _sb.rpc(
      'attendance_set',
      params: {
        'p_poll_id': _s!.pollId,
        'p_player_id': playerId,
        'p_status': status,
      },
    ),
  );

  /// "Cumartesi 25 Ekim 20:00" (tarih yoksa boş).
  String _when() {
    final d = DateTime.tryParse((widget.match.matchDate ?? '').trim());
    if (d == null) return '';
    final day = DateFormat('d MMMM EEEE', 'tr_TR').format(d);
    final t = (widget.match.matchTime ?? '').trim();
    return t.isEmpty ? day : '$day $t';
  }

  String _matchLine() {
    final w = _when();
    return '${widget.teamName} – ${widget.rivalName}${w.isEmpty ? '' : '\n$w'}';
  }

  Future<void> _shareGroup() async {
    await SharePlus.instance.share(
      ShareParams(
        text:
            '⚽ Katılım Durum Sorgulama\n${_matchLine()}\n\n'
            'Katılım durumunu bildir: $_linkBase\n'
            '(İlk seferde sana özel gönderilen bağlantıyı aç.)',
      ),
    );
  }

  Future<void> _sendPersonal(_Player p) async {
    try {
      final token = await _sb.rpc(
        'attendance_player_link',
        params: {
          'p_match_id': widget.match.id,
          'p_team_id': widget.teamId,
          'p_player_id': p.id,
        },
      );
      final first = p.name.split(' ').first;
      final text =
          'Merhaba $first, ${_matchLine().replaceAll('\n', ' · ')} maçı için '
          'katılım durumunu bu bağlantıdan bildirebilirsin:\n'
          '$_linkBase?k=$token\n\n'
          'Bağlantı sana özel, başkasıyla paylaşma. Sonraki maçlarda da '
          'aynı bağlantıyı kullanabilirsin.';
      // Telefonu kayıtlıysa doğrudan o kişinin sohbeti, değilse WhatsApp
      // kişi seçimi açılır.
      final to = p.phone == null ? '' : '90${p.phone}';
      final uri = Uri.parse(
        'https://wa.me/$to?text=${Uri.encodeComponent(text)}',
      );
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) await SharePlus.instance.share(ShareParams(text: text));
    } on PostgrestException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _pickFor(_Player p) async {
    const clear = '';
    final v = await showAdminOptionPicker<String>(
      context: context,
      title: p.name,
      items: const ['yes', 'no', clear],
      labelBuilder: (s) => switch (s) {
        'yes' => 'Geliyor',
        'no' => 'Gelemiyor',
        _ => 'İşareti kaldır',
      },
      selected: p.status ?? clear,
    );
    if (v == null || v == (p.status ?? clear)) return;
    await _set(p.id, v == clear ? null : v);
  }

  Future<void> _toggleClosed() async {
    final s = _s!;
    if (s.closed) {
      await _open();
      return;
    }
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Sorguyu kapat',
      message:
          'Oyuncular artık işaretleme yapamaz. Siz yine de '
          'düzeltebilir ve sorguyu yeniden açabilirsiniz.',
      confirmLabel: 'KAPAT',
      destructive: false,
      icon: Icons.lock_outline_rounded,
    );
    if (!ok) return;
    await _run(
      () => _sb.rpc('attendance_close', params: {'p_poll_id': s.pollId}),
    );
  }

  Future<void> _showList() async {
    await showAdminPopup<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setPopup) {
          // Liste, kartın güncel verisini kullanır; işlemden sonra yenilenir.
          Future<void> act(Future<void> Function() f) async {
            await f();
            setPopup(() {});
          }

          return _AttendanceList(
            summary: _s!,
            title: widget.teamName,
            onPick: (p) => act(() => _pickFor(p)),
            onSend: _sendPersonal,
            onShareGroup: _shareGroup,
            onToggleClosed: () => act(_toggleClosed),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const SizedBox.shrink();
    if (s.pollId == null) {
      // Sorgu yok: yalnızca sorumlu, maç başlamadıysa başlatabilir.
      if (!s.canManage || !s.matchOpen) return const SizedBox.shrink();
      return _frame(
        children: [
          _title(),
          const SizedBox(height: 6),
          const Text(
            'Kadrona maça gelip gelemeyeceğini sor. Hesabı olan oyunculara '
            'bildirim gider; diğerlerine WhatsApp\'tan kişisel bağlantı '
            'gönderebilirsin.',
            style: TextStyle(color: kAdminMuted, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 10),
          _button(
            label: 'Sorguyu başlat',
            icon: Icons.campaign_outlined,
            filled: true,
            onTap: _open,
          ),
        ],
      );
    }

    final me = s.me == null
        ? null
        : s.players.where((p) => p.id == s.me).firstOrNull;
    final canAnswer = me != null && !s.closed && s.matchOpen;
    return _frame(
      children: [
        _title(closed: s.closed),
        const SizedBox(height: 10),
        _Counts(summary: s),
        if (canAnswer) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _choice(
                  'Geliyorum',
                  kAdminAccent,
                  me.status == 'yes',
                  () => _set(me.id, 'yes'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _choice(
                  'Gelemiyorum',
                  kAdminDanger,
                  me.status == 'no',
                  () => _set(me.id, 'no'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _button(
                label: 'Listeyi gör',
                icon: Icons.list_alt_rounded,
                onTap: _showList,
              ),
            ),
            if (s.canManage) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _button(
                  label: 'Gruba paylaş',
                  icon: Icons.share_outlined,
                  onTap: _shareGroup,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _frame({required List<Widget> children}) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    decoration: BoxDecoration(
      color: const Color(0xFF1E293B).withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kAdminAccent.withValues(alpha: 0.35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _title({bool closed = false}) => Row(
    children: [
      const Icon(Icons.how_to_reg_rounded, color: kAdminAccent, size: 18),
      const SizedBox(width: 6),
      Expanded(
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'KATILIM DURUM SORGULAMA'),
              TextSpan(
                text: ' · ${widget.teamName}',
                style: const TextStyle(color: kAdminMuted),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: kAdminAccent,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ),
      if (closed)
        const _Badge(text: 'Kapalı', color: kAdminMuted)
      else if (_busy)
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: kAdminAccent),
        ),
    ],
  );

  Widget _choice(String label, Color color, bool on, VoidCallback onTap) {
    return Material(
      color: on ? color : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: _busy ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? color : Colors.white24, width: 1.5),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: on ? Colors.white : Colors.white70,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _button({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return SizedBox(
      height: 40,
      child: filled
          ? ElevatedButton.icon(
              onPressed: _busy ? null : onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: kAdminAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: Icon(icon, size: 18),
              label: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : OutlinedButton.icon(
              onPressed: _busy ? null : onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: kAdminAccent,
                side: BorderSide(color: kAdminAccent.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: Icon(icon, size: 17),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
    );
  }
}

/// Geliyor / Gelemiyor / Cevapsız sayıları.
class _Counts extends StatelessWidget {
  const _Counts({required this.summary});

  final _Summary summary;

  @override
  Widget build(BuildContext context) {
    final yes = summary.players.where((p) => p.status == 'yes').length;
    final no = summary.players.where((p) => p.status == 'no').length;
    final none = summary.players.length - yes - no;
    Widget item(String n, String label, Color color) => Expanded(
      child: Column(
        children: [
          Text(
            n,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(label, style: const TextStyle(color: kAdminMuted, fontSize: 12)),
        ],
      ),
    );
    return Row(
      children: [
        item('$yes', 'Geliyor', kAdminAccent),
        item('$no', 'Gelemiyor', kAdminDanger),
        item('$none', 'Cevapsız', Colors.white70),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
    ),
  );
}

/// Kadro listesi: durumlarına göre gruplu. Sorumlu satıra dokunup işaretler,
/// WhatsApp düğmesiyle kişisel bağlantı gönderir.
class _AttendanceList extends StatelessWidget {
  const _AttendanceList({
    required this.summary,
    required this.title,
    required this.onPick,
    required this.onSend,
    required this.onShareGroup,
    required this.onToggleClosed,
  });

  final _Summary summary;
  final String title;
  final ValueChanged<_Player> onPick;
  final ValueChanged<_Player> onSend;
  final VoidCallback onShareGroup;
  final VoidCallback onToggleClosed;

  @override
  Widget build(BuildContext context) {
    final manage = summary.canManage;
    final groups = [
      ('Geliyor', kAdminAccent, 'yes'),
      ('Gelemiyor', kAdminDanger, 'no'),
      ('Cevapsız', Colors.white70, null),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 4, 6),
          child: Row(
            children: [
              Expanded(
                child: AdminDialogHeader(
                  icon: Icons.how_to_reg_rounded,
                  title: 'Katılım Durumu',
                  subtitle: title,
                ),
              ),
              AdminDialogCloseButton(
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            children: [
              for (final (label, color, status) in groups)
                if (summary.players.any((p) => p.status == status))
                  AdminFormSection(
                    title:
                        '$label (${summary.players.where((p) => p.status == status).length})',
                    child: AdminFieldGroup(
                      children: [
                        for (final p in summary.players.where(
                          (p) => p.status == status,
                        ))
                          _row(p, color),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        if (manage)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: AdminSecondaryButton(
                    label: summary.closed ? 'YENİDEN AÇ' : 'SORGUYU KAPAT',
                    onPressed: summary.matchOpen ? onToggleClosed : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AdminPrimaryButton(
                    label: 'GRUBA PAYLAŞ',
                    icon: Icons.share_outlined,
                    onPressed: onShareGroup,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(_Player p, Color color) {
    final via = switch (p.via) {
      'link' => 'Bağlantıdan',
      'manager' => 'Sorumlu işaretledi',
      'app' => 'Uygulamadan',
      _ => p.hasAccount ? 'Uygulamada hesabı var' : null,
    };
    return InkWell(
      onTap: summary.canManage ? () => onPick(p) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                p.number == null ? '–' : '${p.number}',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  if (via != null)
                    Text(
                      via,
                      style: const TextStyle(
                        color: kAdminMuted,
                        fontSize: 11.5,
                      ),
                    ),
                ],
              ),
            ),
            if (summary.canManage)
              IconButton(
                tooltip: 'Kişisel bağlantıyı WhatsApp\'tan gönder',
                visualDensity: VisualDensity.compact,
                onPressed: () => onSend(p),
                icon: const Icon(
                  Icons.send_rounded,
                  color: Color(0xFF25D366),
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Summary {
  const _Summary({
    required this.pollId,
    required this.closed,
    required this.matchOpen,
    required this.canManage,
    required this.me,
    required this.players,
  });

  final String? pollId;
  final bool closed;
  final bool matchOpen;
  final bool canManage;
  final String? me;
  final List<_Player> players;

  factory _Summary.fromJson(Map raw) => _Summary(
    pollId: raw['poll_id']?.toString(),
    closed: raw['closed'] == true,
    matchOpen: raw['match_open'] == true,
    canManage: raw['can_manage'] == true,
    me: raw['me']?.toString(),
    players: [
      for (final p in (raw['players'] as List? ?? const []))
        if (p is Map) _Player.fromJson(p),
    ],
  );
}

class _Player {
  const _Player({
    required this.id,
    required this.name,
    required this.number,
    required this.hasAccount,
    required this.phone,
    required this.status,
    required this.via,
  });

  final String id;
  final String name;
  final int? number;
  final bool hasAccount;
  final String? phone;
  final String? status;
  final String? via;

  factory _Player.fromJson(Map raw) => _Player(
    id: raw['id'].toString(),
    name: (raw['name'] ?? '').toString(),
    number: (raw['number'] as num?)?.toInt(),
    hasAccount: raw['has_account'] == true,
    phone: raw['phone']?.toString(),
    status: raw['status']?.toString(),
    via: raw['via']?.toString(),
  );
}
