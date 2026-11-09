import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../auth/registration/registration_service.dart'
    show RegistrationService;
import '../team/screens/team_squad_screen.dart' show BirthDateInputFormatter;
import 'id_card_reader.dart' show tcValid;
import 'identity_service.dart';
import 'verified_badge.dart';

/// Kimlik ibrazı onayı bekleyen kayıtlar. Yetkili, kişinin girdiği bilgileri
/// kimlikle gözle karşılaştırır; yanlışsa düzeltir, sonra onaylar ya da
/// reddeder. Onaylanan profil turuncu tikli olur.
class IbrazPendingScreen extends StatefulWidget {
  const IbrazPendingScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'IbrazPendingScreen'),
      builder: (_) => const IbrazPendingScreen(),
    ),
  );

  /// Panel şeridi ve sayaç yenilensin diye onay/ret sonrası artar.
  static final changed = ValueNotifier<int>(0);

  @override
  State<IbrazPendingScreen> createState() => _IbrazPendingScreenState();
}

class _IbrazPendingScreenState extends State<IbrazPendingScreen> {
  SupabaseClient get _sb => Supabase.instance.client;

  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _sb.rpc('ibraz_pending_list');
      if (!mounted) return;
      setState(() {
        _items = [
          for (final e in (r as List? ?? const []))
            Map<String, dynamic>.from(e as Map),
        ];
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Liste yüklenemedi. Aşağı çekerek yenileyin.';
        });
      }
    }
  }

  static String _birthText(dynamic v) {
    final d = DateTime.tryParse((v ?? '').toString());
    return d == null ? '' : DateFormat('dd-MM-yyyy').format(d);
  }

  String _ago(dynamic v) {
    final d = DateTime.tryParse((v ?? '').toString());
    if (d == null) return '';
    final diff = DateTime.now().difference(d.toLocal());
    if (diff.inDays >= 1) return '${diff.inDays} gün önce';
    if (diff.inHours >= 1) return '${diff.inHours} sa önce';
    return 'az önce';
  }

  Future<void> _review(Map<String, dynamic> row) async {
    final first = TextEditingController(text: (row['name'] ?? '').toString());
    final last = TextEditingController(text: (row['surname'] ?? '').toString());
    final birth = TextEditingController(text: _birthText(row['birth']));
    final tc = TextEditingController(text: (row['tc'] ?? '').toString());
    String? error;
    var busy = false;

    final done = await showAdminPopup<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          Future<void> approve() async {
            DateTime? b;
            try {
              b = birth.text.length == 10
                  ? DateFormat('dd-MM-yyyy').parseStrict(birth.text)
                  : null;
            } catch (_) {
              b = null;
            }
            if (!tcValid(tc.text.trim())) {
              setD(() => error = 'TC kimlik numarası geçersiz.');
              return;
            }
            if (b == null) {
              setD(() => error = 'Doğum tarihi GG-AA-YYYY olmalı.');
              return;
            }
            setD(() {
              busy = true;
              error = null;
            });
            try {
              final r = await _sb.rpc(
                'ibraz_approve',
                params: {
                  'p_player': row['id'],
                  'p_first': first.text.trim(),
                  'p_last': last.text.trim(),
                  'p_birth': DateFormat('yyyy-MM-dd').format(b),
                  'p_tc': tc.text.trim(),
                },
              );
              final code = (r ?? '').toString();
              if (code == 'ok') {
                if (ctx.mounted) Navigator.pop(ctx, true);
                return;
              }
              setD(() {
                busy = false;
                error = switch (code) {
                  'tc_taken' =>
                    'Bu TC başka bir onaylı profilde kayıtlı. Çift kayıt olabilir.',
                  'duplicate' =>
                    'Aynı ad soyad ve doğum tarihli başka bir profil var.',
                  'invalid_tc' => 'TC kimlik numarası geçersiz.',
                  'invalid_data' => 'Ad, soyad ve doğum tarihini kontrol edin.',
                  'forbidden' => 'Bu kaydı onaylama yetkiniz yok.',
                  'not_pending' => 'Bu kayıt zaten işlenmiş.',
                  _ => RegistrationService.message(code) ?? 'İşlem başarısız.',
                };
              });
            } catch (_) {
              setD(() {
                busy = false;
                error = 'Bağlantı hatası. Tekrar deneyin.';
              });
            }
          }

          Future<void> reject() async {
            final ok = await showAdminConfirmDialog(
              context: ctx,
              title: 'Kaydı Reddet',
              message:
                  'Kimlik ibrazı onaylanmayacak; profil onaysız kalır ve '
                  'girilen TC silinir. Emin misiniz?',
              confirmLabel: 'Reddet',
              destructive: true,
            );
            if (!ok) return;
            setD(() => busy = true);
            try {
              await _sb.rpc('ibraz_reject', params: {'p_player': row['id']});
              if (ctx.mounted) Navigator.pop(ctx, true);
            } catch (_) {
              setD(() {
                busy = false;
                error = 'Bağlantı hatası. Tekrar deneyin.';
              });
            }
          }

          Widget field(
            IconData icon,
            String label,
            TextEditingController c, {
            List<TextInputFormatter>? formatters,
            TextInputType? type,
            TextCapitalization cap = TextCapitalization.none,
          }) => AdminFieldRow(
            icon: icon,
            label: label,
            child: TextField(
              controller: c,
              enabled: !busy,
              keyboardType: type,
              inputFormatters: formatters,
              textCapitalization: cap,
              onChanged: (_) => setD(() => error = null),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              decoration: adminInlineInputDecoration(hint: label),
            ),
          );

          return AdminDialogCloseOverlay(
            onClose: busy ? null : () => Navigator.pop(ctx, false),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: AdminDialogHeader(
                    icon: Icons.verified_user_outlined,
                    title: 'İbrazla Onay',
                    subtitle: 'Bilgileri kimlik kartıyla karşılaştır',
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AdminFormSection(
                          title: 'Kişinin girdiği bilgiler',
                          child: AdminFieldGroup(
                            children: [
                              field(
                                Icons.credit_card_rounded,
                                'TC Kimlik No',
                                tc,
                                type: TextInputType.number,
                                formatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(11),
                                ],
                              ),
                              field(
                                Icons.person_outline_rounded,
                                'Ad',
                                first,
                                cap: TextCapitalization.words,
                              ),
                              field(
                                Icons.person_outline_rounded,
                                'Soyad',
                                last,
                                cap: TextCapitalization.words,
                              ),
                              field(
                                Icons.cake_outlined,
                                'Doğum Tarihi',
                                birth,
                                type: TextInputType.number,
                                formatters: [BirthDateInputFormatter()],
                              ),
                            ],
                          ),
                        ),
                        const Text(
                          'Yanlış girilmiş alan varsa kimlikteki gibi düzelt.',
                          style: TextStyle(color: kAdminMuted, fontSize: 12.5),
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: kAdminDanger,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: OutlinedButton(
                            onPressed: busy ? null : reject,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kAdminDanger,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.14),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'REDDET',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AdminPrimaryButton(
                          label: 'ONAYLA',
                          busy: busy,
                          onPressed: busy ? null : approve,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (done == true) {
      IdentityService.invalidate((row['id'] ?? '').toString());
      IbrazPendingScreen.changed.value++;
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPageScaffold(
      title: 'Onay Bekleyenler',
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: kAdminMuted),
                      ),
                    )
                  else if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Text(
                        'Kimlik ibrazı bekleyen kayıt yok.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kAdminMuted, fontSize: 15),
                      ),
                    )
                  else
                    for (final p in _items) _card(p),
                ],
              ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> p) {
    final name = '${p['name'] ?? ''} ${p['surname'] ?? ''}'.trim();
    final team = (p['team'] ?? '').toString();
    final sub = [
      _birthText(p['birth']),
      if (team.isNotEmpty) team,
      _ago(p['requested_at']),
    ].where((e) => e.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFF16213A),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _review(p),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_rounded,
                  color: kIbrazOrange,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: const TextStyle(
                          color: kAdminMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: kAdminMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
