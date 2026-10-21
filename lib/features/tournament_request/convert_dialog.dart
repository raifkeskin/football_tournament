import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';

// Admin: ödemesi alınan talebi turnuvaya dönüştürür. Lig + ilk sezon
// (+ gruplar) açılır, talep sahibi telefonuyla kurucu başkan olur.
// Format (takım, grup, devre, oyuncu sayısı) talepten gelir; sonradan
// sezon ayarlarından değiştirilebilir.

/// Kurucu başkana WhatsApp'ta hazır "turnuvanız açıldı" mesajı.
Future<void> openOwnerWelcomeWhatsApp({
  required String phoneRaw10,
  required String contactName,
  required String leagueName,
}) {
  final first = contactName.trim().split(RegExp(r'\s+')).first;
  final text =
      'Merhaba $first, $leagueName Lig Masası\'nda açıldı. Uygulamaya '
      '0$phoneRaw10 numarasıyla giriş yaptığınızda kurucu başkan olarak '
      'takımları, fikstürü ve maçları yönetebilirsiniz.\nhttps://ligmasasi.com';
  return launchUrl(
    Uri.parse('https://wa.me/90$phoneRaw10?text=${Uri.encodeComponent(text)}'),
    mode: LaunchMode.externalApplication,
  );
}

/// Dönüştürülürse oluşan lig adını döner.
Future<String?> showConvertRequestDialog(
  BuildContext context, {
  required Map<String, dynamic> request,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ConvertDialog(request: request),
);

class _ConvertDialog extends StatefulWidget {
  const _ConvertDialog({required this.request});

  final Map<String, dynamic> request;

  @override
  State<_ConvertDialog> createState() => _ConvertDialogState();
}

class _ConvertDialogState extends State<_ConvertDialog> {
  late final TextEditingController _name = TextEditingController(
    text: (widget.request['name'] ?? '').toString(),
  );
  final _short = TextEditingController();
  late final TextEditingController _city = TextEditingController(
    text: (widget.request['city'] ?? '').toString(),
  );
  late DateTime _start;
  late DateTime _end;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Varsayılan: önümüzdeki cumartesi, dört ay.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _start = today.add(Duration(days: (DateTime.saturday - today.weekday) % 7));
    _end = _start.add(const Duration(days: 120));
  }

  @override
  void dispose() {
    for (final c in [_name, _short, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _pick({required bool start}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: start ? DateTime(now.year - 1) : _start,
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _start = picked;
        if (_end.isBefore(_start)) {
          _end = _start.add(const Duration(days: 120));
        }
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 3) {
      setState(() => _error = 'Turnuva adı gerekli.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'convert_tournament_request',
        params: {
          'p_request_id': widget.request['id'],
          'p_league_name': name,
          'p_short_name': _short.text.trim(),
          'p_city': _city.text.trim(),
          'p_start_date': _iso(_start),
          'p_end_date': _iso(_end),
        },
      );
      if (mounted) Navigator.pop(context, name);
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Oluşturulamadı: $e';
        });
      }
    }
  }

  Widget _text(
    IconData icon,
    String label,
    TextEditingController c, {
    String? hint,
    int? maxLength,
  }) => AdminFieldRow(
    icon: icon,
    label: label,
    child: TextField(
      controller: c,
      maxLength: maxLength,
      textCapitalization: TextCapitalization.words,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      decoration: adminInlineInputDecoration(
        hint: hint,
      ).copyWith(counterText: ''),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final groups = (r['group_count'] as num?)?.toInt() ?? 1;
    final summary = [
      if (r['team_count'] != null) '${r['team_count']} takım',
      groups > 1 ? '$groups grup' : 'tek grup',
      r['double_round'] == true ? 'çift devre' : 'tek devre',
      (r['players_format'] ?? '').toString(),
    ].where((s) => s.isNotEmpty).join(' · ');
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: AdminDialogCloseOverlay(
        onClose: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: adminDialogDecoration(),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminDialogHeader(
                  icon: Icons.emoji_events_outlined,
                  title: 'Turnuvaya Dönüştür',
                  subtitle: '${r['code']} · ${r['contact_name']}',
                ),
                const SizedBox(height: 16),
                AdminFieldGroup(
                  children: [
                    _text(
                      Icons.emoji_events_outlined,
                      'Turnuva adı',
                      _name,
                      maxLength: 80,
                    ),
                    _text(
                      Icons.short_text_rounded,
                      'Kısa ad · isteğe bağlı',
                      _short,
                      hint: 'Örn. BML',
                      maxLength: 24,
                    ),
                    _text(Icons.place_outlined, 'Şehir', _city, maxLength: 30),
                    AdminSelectRow(
                      icon: Icons.event_outlined,
                      label: 'Sezon başlangıcı',
                      value: _fmt(_start),
                      placeholder: '',
                      onTap: () => _pick(start: true),
                    ),
                    AdminSelectRow(
                      icon: Icons.event_available_outlined,
                      label: 'Sezon bitişi',
                      value: _fmt(_end),
                      placeholder: '',
                      onTap: () => _pick(start: false),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Sezon: $summary\n'
                  'Kurucu başkan: ${r['contact_name']} · ${r['phone']}\n'
                  'Format ve kurallar sonradan sezon ayarlarından '
                  'değiştirilebilir.',
                  style: const TextStyle(
                    color: kAdminMuted,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: kAdminDanger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                AdminPrimaryButton(
                  label: 'TURNUVAYI OLUŞTUR',
                  icon: Icons.check_rounded,
                  busy: _busy,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
