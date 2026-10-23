import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';

// Admin: talepten teklif (ilk teklif ya da revize). Kayıt yeni bir sürüm
// açar; ardından WhatsApp hazır mesajla açılır, admin yalnız "gönder"e basar.
// Teklif sayfası web'de (ligmasasi.com/teklif), uygulamada fiyat yok.

const kOfferBaseUrl = 'https://ligmasasi.com/teklif?t=';

String formatTl(num v) {
  final whole = v.round();
  final s = whole.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '₺${whole < 0 ? '-' : ''}$b';
}

/// Talep sahibine WhatsApp'ta hazır teklif mesajı açar.
Future<void> openOfferWhatsApp({
  required String phoneRaw10,
  required String contactName,
  required String code,
  required String token,
  required bool revised,
}) {
  final first = contactName.trim().split(RegExp(r'\s+')).first;
  final text =
      'Merhaba $first, Lig Masası\'na ilginiz için teşekkürler. $code '
      'numaralı talebiniz için ${revised ? 'güncellenmiş ' : ''}teklifimiz '
      'hazır:\n$kOfferBaseUrl$token';
  return launchUrl(
    Uri.parse('https://wa.me/90$phoneRaw10?text=${Uri.encodeComponent(text)}'),
    mode: LaunchMode.externalApplication,
  );
}

/// Teklif düzenleyici. [last] varsa revize (değerleri ondan başlar).
/// Kaydedilirse true döner.
Future<bool> showOfferEditor(
  BuildContext context, {
  required Map<String, dynamic> request,
  Map<String, dynamic>? last,
}) async {
  Map<String, dynamic> settings = const {};
  try {
    final s = await Supabase.instance.client.rpc('offer_settings_get');
    if (s is Map) settings = Map<String, dynamic>.from(s);
  } catch (_) {}
  if (!context.mounted) return false;
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _OfferEditorDialog(request: request, last: last, settings: settings),
  );
  return saved == true;
}

class _OfferEditorDialog extends StatefulWidget {
  const _OfferEditorDialog({
    required this.request,
    required this.last,
    required this.settings,
  });

  final Map<String, dynamic> request;
  final Map<String, dynamic>? last;
  final Map<String, dynamic> settings;

  @override
  State<_OfferEditorDialog> createState() => _OfferEditorDialogState();
}

class _OfferEditorDialogState extends State<_OfferEditorDialog> {
  late final TextEditingController _list;
  late final TextEditingController _discount;
  late final TextEditingController _matches;
  late final TextEditingController _note;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final l = widget.last;
    num pick(Object? a, Object? b, num d) =>
        num.tryParse('${a ?? ''}') ?? num.tryParse('${b ?? ''}') ?? d;
    _list = TextEditingController(
      text: pick(
        l?['list_price'],
        widget.settings['offer_list_price'],
        1000,
      ).round().toString(),
    );
    _discount = TextEditingController(
      text: pick(
        l?['discount_pct'],
        widget.settings['offer_first_discount_pct'],
        0,
      ).round().toString(),
    );
    _matches = TextEditingController(
      text: pick(
        l?['match_count'],
        widget.request['est_matches'],
        1,
      ).round().toString(),
    );
    _note = TextEditingController(text: (l?['note'] ?? '').toString());
    for (final c in [_list, _discount, _matches]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_list, _discount, _matches, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  num get _listV => num.tryParse(_list.text) ?? 0;
  num get _discV => num.tryParse(_discount.text) ?? 0;
  int get _matchV => int.tryParse(_matches.text) ?? 0;
  num get _per => (_listV * (1 - _discV / 100) * 100).round() / 100;

  Future<void> _save() async {
    if (_listV <= 0 || _matchV <= 0) {
      setState(() => _error = 'Fiyat ve maç sayısı gerekli.');
      return;
    }
    if (_discV < 0 || _discV >= 100) {
      setState(() => _error = 'İndirim 0–99 arasında olmalı.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = widget.request;
    try {
      final res = await Supabase.instance.client.rpc(
        'tournament_offer_save',
        params: {
          'p_request_id': r['id'],
          'p_list_price': _listV,
          'p_discount_pct': _discV,
          'p_match_count': _matchV,
          'p_note': _note.text,
        },
      );
      final m = Map<String, dynamic>.from(res as Map);
      await openOfferWhatsApp(
        phoneRaw10: (r['phone_raw10'] ?? '').toString(),
        contactName: (r['contact_name'] ?? '').toString(),
        code: (r['code'] ?? '').toString(),
        token: m['token'].toString(),
        revised: (m['version'] as num) > 1,
      );
      if (mounted) Navigator.pop(context, true);
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
          _error = 'Kaydedilemedi: $e';
        });
      }
    }
  }

  Widget _num(
    IconData icon,
    String label,
    TextEditingController c, {
    String? suffix,
  }) => AdminFieldRow(
    icon: icon,
    label: label,
    child: TextField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      decoration: adminInlineInputDecoration().copyWith(suffixText: suffix),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final revise = widget.last != null;
    final teams = (widget.request['team_count'] as num?)?.toInt() ?? 0;
    final total = _per * _matchV;
    TextStyle v([Color c = Colors.white]) =>
        TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w800);
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
                  icon: Icons.request_quote_outlined,
                  title: revise
                      ? 'Revize ${widget.last!['version']}'
                      : 'Teklif Hazırla',
                  subtitle:
                      '${widget.request['code']} · '
                      '${widget.request['contact_name']}',
                ),
                const SizedBox(height: 16),
                AdminFieldGroup(
                  children: [
                    _num(
                      Icons.sell_outlined,
                      'Liste fiyatı (maç başı)',
                      _list,
                      suffix: '₺',
                    ),
                    _num(
                      Icons.percent_rounded,
                      'İndirim',
                      _discount,
                      suffix: '%',
                    ),
                    _num(Icons.sports_soccer_rounded, 'Maç sayısı', _matches),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kAdminAccent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: kAdminAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      for (final (k, val, c) in [
                        ('Maç başı', formatTl(_per), Colors.white),
                        (
                          'Takım başına, maç başı',
                          formatTl(_per / 2),
                          Colors.white,
                        ),
                        if (teams > 0)
                          (
                            'Takım başına sezon',
                            formatTl(total / teams),
                            Colors.white,
                          ),
                        ('Sezon toplamı', formatTl(total), kAdminAmber),
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  k,
                                  style: const TextStyle(color: kAdminMuted),
                                ),
                              ),
                              Text(val, style: v(c)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AdminFieldGroup(
                  children: [
                    AdminFieldRow(
                      icon: Icons.edit_note_rounded,
                      label: 'Teklif notu · isteğe bağlı',
                      child: TextField(
                        controller: _note,
                        minLines: 2,
                        maxLines: 5,
                        maxLength: 1500,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: adminInlineInputDecoration(
                          hint:
                              'Örn. Kurulumu biz yapıyoruz, fikstürü '
                              'birlikte çıkaralım.',
                        ).copyWith(counterText: ''),
                      ),
                    ),
                  ],
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
                  label: 'KAYDET VE WHATSAPP\'TA GÖNDER',
                  icon: Icons.send_rounded,
                  busy: _busy,
                  onPressed: _save,
                ),
                const SizedBox(height: 6),
                const Text(
                  'WhatsApp hazır mesajla açılır; göndermek için "gönder"e '
                  'basman yeterli.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kAdminMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Admin: IBAN, hesap sahibi, banka, varsayılan liste fiyatı ve ilk
/// turnuva indirimi. Yalnız adminler görür; teklif sayfası ödeme kısmında.
Future<void> showOfferSettings(BuildContext context) async {
  Map<String, dynamic> s = const {};
  try {
    final r = await Supabase.instance.client.rpc('offer_settings_get');
    if (r is Map) s = Map<String, dynamic>.from(r);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ayarlar okunamadı: $e')));
    }
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _OfferSettingsDialog(initial: s),
  );
}

class _OfferSettingsDialog extends StatefulWidget {
  const _OfferSettingsDialog({required this.initial});

  final Map<String, dynamic> initial;

  @override
  State<_OfferSettingsDialog> createState() => _OfferSettingsDialogState();
}

class _OfferSettingsDialogState extends State<_OfferSettingsDialog> {
  static const _fields = [
    ('offer_iban', Icons.account_balance_outlined, 'IBAN', false),
    ('offer_account_name', Icons.person_outline_rounded, 'Hesap sahibi', false),
    ('offer_bank', Icons.account_balance_wallet_outlined, 'Banka', false),
    (
      'offer_list_price',
      Icons.sell_outlined,
      'Liste fiyatı (maç başı ₺)',
      true,
    ),
    (
      'offer_first_discount_pct',
      Icons.percent_rounded,
      'İlk turnuva indirimi (%)',
      true,
    ),
  ];

  late final Map<String, TextEditingController> _c = {
    for (final f in _fields)
      f.$1: TextEditingController(
        text: (widget.initial[f.$1] ?? '').toString(),
      ),
  };
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'offer_settings_set',
        params: {
          'p_values': {for (final e in _c.entries) e.key: e.value.text.trim()},
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Kaydedilemedi: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                const AdminDialogHeader(
                  icon: Icons.request_quote_outlined,
                  title: 'Teklif Ayarları',
                  subtitle:
                      'Ödeme bilgisi teklif sayfasında yalnız teklif '
                      'kabul edildikten sonra görünür.',
                ),
                const SizedBox(height: 16),
                AdminFieldGroup(
                  children: [
                    for (final f in _fields)
                      AdminFieldRow(
                        icon: f.$2,
                        label: f.$3,
                        child: TextField(
                          controller: _c[f.$1],
                          keyboardType: f.$4
                              ? TextInputType.number
                              : TextInputType.text,
                          inputFormatters: f.$4
                              ? [FilteringTextInputFormatter.digitsOnly]
                              : null,
                          textCapitalization: f.$1 == 'offer_iban'
                              ? TextCapitalization.characters
                              : TextCapitalization.words,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: adminInlineInputDecoration(
                            hint: f.$1 == 'offer_iban' ? 'TR00 0000 …' : null,
                          ),
                        ),
                      ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kAdminDanger),
                  ),
                ],
                const SizedBox(height: 16),
                AdminPrimaryButton(
                  label: 'KAYDET',
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
