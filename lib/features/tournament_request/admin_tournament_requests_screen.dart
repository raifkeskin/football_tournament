import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/app_session.dart';
import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import 'convert_dialog.dart';
import 'offer_editor.dart';
import 'tournament_request.dart';

/// Admin: gelen turnuva talepleri. Durum ve not admin tarafından tutulur;
/// görüşme telefon / WhatsApp ile yapılır.
class AdminTournamentRequestsScreen extends StatefulWidget {
  const AdminTournamentRequestsScreen({super.key});

  @override
  State<AdminTournamentRequestsScreen> createState() =>
      _AdminTournamentRequestsScreenState();
}

const _statuses = <(String, String, Color)>[
  ('new', 'Yeni', kRequestGold),
  ('contacted', 'Görüşüldü', Color(0xFF60A5FA)),
  ('offered', 'Teklif verildi', Color(0xFFA78BFA)),
  ('won', 'Kazanıldı', kAdminAccent),
  ('lost', 'Olmadı', Color(0xFF94A3B8)),
  ('cancelled', 'İptal', Color(0xFF64748B)),
];

const _openStatuses = {'new', 'contacted', 'offered'};

/// Teklif sayfasından gelen cevap (tournament_offers.response).
const _responses = <String, (String, Color)>{
  'accepted': ('Kabul edildi', kAdminAccent),
  'revision': ('Revize istendi', kRequestGold),
  'rejected': ('Reddedildi', Color(0xFFF87171)),
};

(String, Color) _statusLook(String s) {
  for (final x in _statuses) {
    if (x.$1 == s) return (x.$2, x.$3);
  }
  return (s, Colors.white54);
}

const _kindNames = {
  'halisaha': 'Halı saha',
  'okul': 'Okul',
  'sirket': 'Şirket',
  'dernek': 'Dernek',
  'master': 'Master',
  'diger': 'Diğer',
};

const _extraNames = {
  'setup': 'Kurulumu siz yapın',
  'live_draw': 'Canlı kura',
  'instagram': 'Instagram paylaşımları',
};

String _summary(Map<String, dynamic> r) {
  final groups = (r['group_count'] as int?) ?? 1;
  return [
    _kindNames[r['kind']] ?? '',
    if (r['team_count'] != null) '${r['team_count']} takım',
    groups > 1 ? '$groups grup' : 'tek lig',
    r['double_round'] == true ? 'çift devre' : 'tek devre',
    if (r['knockout'] == true) 'eleme',
    (r['players_format'] ?? '').toString(),
    if (r['est_matches'] != null) '~${r['est_matches']} maç',
  ].where((s) => s.isNotEmpty).join(' · ');
}

String _date(String? iso) {
  final t = DateTime.tryParse(iso ?? '')?.toLocal();
  if (t == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
}

class _AdminTournamentRequestsScreenState
    extends State<AdminTournamentRequestsScreen> {
  List<Map<String, dynamic>> _rows = const [];
  bool _busy = true;
  bool _onlyOpen = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _busy = true);
    try {
      final rows = await Supabase.instance.client
          .from('tournament_requests')
          .select()
          .order('created_at', ascending: false)
          .limit(300);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(rows);
        _error = null;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Talepler yüklenemedi: $e';
        _busy = false;
      });
    }
  }

  Future<void> _update(String id, Map<String, dynamic> values) async {
    try {
      await Supabase.instance.client
          .from('tournament_requests')
          .update(values)
          .eq('id', id);
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;
    if (!session.isAdmin) {
      return const AdminPageScaffold(
        title: 'Turnuva Talepleri',
        body: Center(
          child: Text(
            'Bu sayfaya erişim yetkiniz yok.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    final rows = _onlyOpen
        ? _rows.where((r) => _openStatuses.contains(r['status'])).toList()
        : _rows;
    return AdminPageScaffold(
      title: 'Turnuva Talepleri',
      actions: [
        AdminBarAction(
          icon: Icons.tune_rounded,
          tooltip: 'Teklif Ayarları',
          onPressed: () => showOfferSettings(context),
        ),
        AdminBarAction(
          icon: Icons.refresh_rounded,
          tooltip: 'Yenile',
          onPressed: _busy ? null : _reload,
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                for (final f in const [(true, 'Açık'), (false, 'Tümü')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.$2),
                      selected: _onlyOpen == f.$1,
                      onSelected: (_) => setState(() => _onlyOpen = f.$1),
                    ),
                  ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(color: kAdminAccent),
          Expanded(
            child: _error != null
                ? Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: kAdminDanger),
                    ),
                  )
                : rows.isEmpty && !_busy
                ? const Center(
                    child: Text(
                      'Talep yok.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _card(rows[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final (label, color) = _statusLook((r['status'] ?? '').toString());
    final title = (r['name'] ?? '').toString().trim();
    return Material(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _detail(r),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    (r['code'] ?? '').toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (r['info_only'] == true) ...[
                    const SizedBox(width: 8),
                    const Text(
                      'bilgi',
                      style: TextStyle(color: kRequestGold, fontSize: 12),
                    ),
                  ],
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
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
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  (r['contact_name'] ?? '').toString(),
                  (r['phone'] ?? '').toString(),
                ].join(' · '),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (title.isNotEmpty)
                Text(
                  [
                    title,
                    (r['city'] ?? '').toString(),
                  ].where((s) => s.trim().isNotEmpty).join(' · '),
                  style: const TextStyle(color: Colors.white70),
                ),
              const SizedBox(height: 4),
              Text(
                _summary(r),
                style: const TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
              Text(
                _date(r['created_at']?.toString()),
                style: const TextStyle(color: Colors.white38, fontSize: 11.5),
              ),
              if (_responses[r['offer_response']] case (
                final text,
                final c,
              )) ...[
                const SizedBox(height: 4),
                Text(
                  'Teklif cevabı: $text · '
                  '${_date(r['offer_responded_at']?.toString())}',
                  style: TextStyle(
                    color: c,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _detail(Map<String, dynamic> r) async {
    final id = r['id'].toString();
    final raw = (r['phone_raw10'] ?? '').toString();
    var offers = const <Map<String, dynamic>>[];
    try {
      final rows = await Supabase.instance.client
          .from('tournament_offers')
          .select()
          .eq('request_id', id)
          .order('version', ascending: false);
      offers = List<Map<String, dynamic>>.from(rows);
    } catch (_) {}
    final leagueId = (r['league_id'] ?? '').toString();
    var leagueName = '';
    if (leagueId.isNotEmpty) {
      try {
        final l = await Supabase.instance.client
            .from('leagues')
            .select('name')
            .eq('id', leagueId)
            .maybeSingle();
        leagueName = (l?['name'] ?? '').toString();
      } catch (_) {}
    }
    if (!mounted) return;
    final last = offers.isEmpty ? null : offers.first;
    final token = (r['offer_token'] ?? '').toString();
    final extras = ((r['extras'] as List?) ?? const [])
        .map((e) => _extraNames[e] ?? e.toString())
        .join(', ');
    Widget row(IconData icon, String label, String? value) =>
        (value ?? '').trim().isEmpty
        ? const SizedBox.shrink()
        : AdminFieldRow(
            icon: icon,
            label: label,
            child: Text(
              value!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kAdminBg,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(c).size.height * 0.85,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(
                '${r['code']} · ${_statusLook(r['status'].toString()).$1}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.call_rounded),
                      label: const Text('Ara'),
                      onPressed: raw.isEmpty
                          ? null
                          : () => launchUrl(Uri.parse('tel:0$raw')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.chat_rounded),
                      label: const Text('WhatsApp'),
                      onPressed: raw.isEmpty
                          ? null
                          : () => launchUrl(
                              Uri.parse('https://wa.me/90$raw'),
                              mode: LaunchMode.externalApplication,
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AdminFormSection(
                title: 'Teklif',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (offers.isNotEmpty)
                      AdminFieldGroup(
                        children: [
                          for (final o in offers)
                            AdminFieldRow(
                              icon: o['viewed_at'] != null
                                  ? Icons.mark_email_read_outlined
                                  : Icons.request_quote_outlined,
                              label:
                                  '${o['version'] == 1 ? 'İlk teklif' : 'Revize ${(o['version'] as num) - 1}'}'
                                  ' · ${_date(o['created_at']?.toString())}'
                                  '${o['viewed_at'] != null ? ' · görüldü' : ''}',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${formatTl(num.parse('${o['per_match_price']}'))} / maç'
                                    ' · ${o['match_count']} maç'
                                    ' · ${formatTl(num.parse('${o['total']}'))}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (_responses[o['response']] case (
                                    final text,
                                    final c,
                                  ))
                                    Text(
                                      [
                                        '$text · '
                                            '${_date(o['responded_at']?.toString())}',
                                        (o['response_reason'] ?? '').toString(),
                                        (o['response_note'] ?? '').toString(),
                                      ].where((e) => e.isNotEmpty).join('\n'),
                                      style: TextStyle(
                                        color: c,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 10),
                    AdminPrimaryButton(
                      label: last == null ? 'TEKLİF HAZIRLA' : 'REVİZE ET',
                      icon: Icons.request_quote_outlined,
                      onPressed: () async {
                        final saved = await showOfferEditor(
                          c,
                          request: r,
                          last: last,
                        );
                        if (!saved || !c.mounted) return;
                        Navigator.pop(c);
                        await _reload();
                      },
                    ),
                    if (token.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      AdminSecondaryButton(
                        label: 'LİNKİ TEKRAR GÖNDER',
                        onPressed: () => openOfferWhatsApp(
                          phoneRaw10: raw,
                          contactName: (r['contact_name'] ?? '').toString(),
                          code: (r['code'] ?? '').toString(),
                          token: token,
                          revised: offers.length > 1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              AdminFormSection(
                title: 'Turnuva',
                child: leagueId.isEmpty
                    ? AdminPrimaryButton(
                        label: 'TURNUVAYA DÖNÜŞTÜR',
                        icon: Icons.emoji_events_outlined,
                        onPressed: () async {
                          final name = await showConvertRequestDialog(
                            c,
                            request: r,
                          );
                          if (name == null || !c.mounted) return;
                          Navigator.pop(c);
                          await _reload();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '$name oluşturuldu. Kurucu başkana '
                                'detaydan WhatsApp ile haber verebilirsin.',
                              ),
                            ),
                          );
                        },
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AdminFieldGroup(
                            children: [
                              row(
                                Icons.emoji_events_outlined,
                                'Oluşturuldu · '
                                '${_date(r['converted_at']?.toString())}',
                                leagueName.isEmpty ? '—' : leagueName,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          AdminSecondaryButton(
                            label: 'KURUCU BAŞKANA WHATSAPP\'TAN BİLDİR',
                            onPressed: raw.isEmpty
                                ? null
                                : () => openOwnerWelcomeWhatsApp(
                                    phoneRaw10: raw,
                                    contactName: (r['contact_name'] ?? '')
                                        .toString(),
                                    leagueName: leagueName,
                                  ),
                          ),
                        ],
                      ),
              ),
              AdminFieldGroup(
                children: [
                  row(
                    Icons.person_outline_rounded,
                    'Ad soyad',
                    r['contact_name']?.toString(),
                  ),
                  row(Icons.phone_outlined, 'Telefon', r['phone']?.toString()),
                  row(
                    Icons.apartment_outlined,
                    'Kurum',
                    r['organization']?.toString(),
                  ),
                  row(
                    Icons.emoji_events_outlined,
                    'Turnuva',
                    r['name']?.toString(),
                  ),
                  row(Icons.place_outlined, 'Şehir', r['city']?.toString()),
                  row(
                    Icons.event_outlined,
                    'Başlangıç',
                    r['start_hint']?.toString(),
                  ),
                  row(Icons.account_tree_outlined, 'Format', _summary(r)),
                  row(Icons.add_task_rounded, 'Ek istekler', extras),
                  row(
                    Icons.edit_note_rounded,
                    'Açıklama',
                    r['note']?.toString(),
                  ),
                  row(
                    Icons.sticky_note_2_outlined,
                    'Admin notu',
                    r['admin_note']?.toString(),
                  ),
                  row(
                    Icons.schedule_rounded,
                    'Gönderildi',
                    '${_date(r['created_at']?.toString())} · '
                        '${r['platform'] ?? '?'} ${r['app_version'] ?? ''}',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AdminPrimaryButton(
                label: 'DURUMU DEĞİŞTİR',
                icon: Icons.flag_outlined,
                onPressed: () async {
                  final picked = await showAdminOptionPicker<String>(
                    context: c,
                    title: 'Durum',
                    items: [for (final s in _statuses) s.$1],
                    labelBuilder: (s) => _statusLook(s).$1,
                    selected: r['status']?.toString(),
                  );
                  if (picked == null || !c.mounted) return;
                  Navigator.pop(c);
                  await _update(id, {'status': picked});
                },
              ),
              const SizedBox(height: 10),
              AdminSecondaryButton(
                label: 'NOT EKLE / DÜZENLE',
                onPressed: () async {
                  final note = await showAdminTextInputDialog(
                    context: c,
                    title: 'Admin notu',
                    icon: Icons.sticky_note_2_outlined,
                    label: 'Not',
                    fieldIcon: Icons.edit_note_rounded,
                    initialValue: (r['admin_note'] ?? '').toString(),
                  );
                  if (note == null || !c.mounted) return;
                  Navigator.pop(c);
                  await _update(id, {
                    'admin_note': note.trim().isEmpty ? null : note.trim(),
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
