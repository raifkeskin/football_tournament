import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:football_tournament/features/auth/widgets/phone_input.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';

/// Turnuva sahibi (davet) satırı.
class _Owner {
  const _Owner({
    required this.phone,
    required this.name,
    required this.hasAccount,
  });

  final String phone;
  final String name;
  final bool hasAccount;
}

/// "5321234567" → "532 123 45 67".
String _formatPhone(String raw) {
  if (raw.length != 10) return raw;
  return '${raw.substring(0, 3)} ${raw.substring(3, 6)} '
      '${raw.substring(6, 8)} ${raw.substring(8)}';
}

/// Turnuva formundaki "Turnuva Sahipleri" (yalnız admin) ya da sezon
/// bölgesindeki "Bölge Sorumluları" (turnuva sahibi / admin) bölümü.
///
/// Sahipler ad soyad + telefonla eklenir; değişiklikler anında kaydedilir.
/// Telefonun hesabı yoksa kişi kayıt olup onaylandığında sahiplik otomatik
/// bağlanır (bkz. migration 20261006100000_league_owner_invites).
class LeagueOwnersSection extends StatefulWidget {
  const LeagueOwnersSection({super.key, required String leagueId})
    : _id = leagueId,
      _region = false;

  /// Bölge sorumluları (turnuva sahibi ve admin yönetir; bkz. migration
  /// 20261008130000_season_regions).
  const LeagueOwnersSection.region({super.key, required String regionId})
    : _id = regionId,
      _region = true;

  final String _id;
  final bool _region;

  String get _rpcSuffix => _region ? 'region_owner' : 'league_owner';
  String get _idParam => _region ? 'p_region_id' : 'p_league_id';
  String get _title => _region ? 'Bölge Sorumluları' : 'Turnuva Sahipleri';
  String get _what => _region ? 'bölgeyi' : 'turnuvayı';

  @override
  State<LeagueOwnersSection> createState() => _LeagueOwnersSectionState();
}

class _LeagueOwnersSectionState extends State<LeagueOwnersSection> {
  final _sb = Supabase.instance.client;
  late Future<List<_Owner>> _owners = _load();
  bool _busy = false;

  Future<List<_Owner>> _load() async {
    final rows = await _sb.rpc(
      'list_${widget._rpcSuffix}s',
      params: {widget._idParam: widget._id},
    );
    return [
      for (final r in rows as List)
        _Owner(
          phone: (r['phone_raw10'] ?? '').toString(),
          name: (r['full_name'] ?? '').toString(),
          hasAccount: r['has_account'] == true,
        ),
    ];
  }

  // setState içinden Future dönmemeli; atama blok içinde yapılır.
  void _reload() => setState(() {
    _owners = _load();
  });

  Future<void> _add() async {
    final input = await _showAddOwnerDialog(context, region: widget._region);
    if (input == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await _sb.rpc(
        'add_${widget._rpcSuffix}',
        params: {
          widget._idParam: widget._id,
          'p_full_name': input.name,
          'p_phone': input.phone,
        },
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result == 'linked'
                ? '${input.name} ${widget._region ? 'bölge sorumlusu' : 'turnuva sahibi'} yapıldı.'
                : '${input.name} eklendi. Kayıt olup onaylandığında '
                      '${widget._what} yönetebilecek.',
          ),
        ),
      );
      _reload();
    } on PostgrestException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Eklenemedi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(_Owner o) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Sahipliği Kaldır',
      message:
          '${o.name} (${_formatPhone(o.phone)}) bu ${widget._what} artık '
          'yönetemeyecek. Hesabı silinmez.',
      confirmLabel: 'KALDIR',
      icon: Icons.person_remove_outlined,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await _sb.rpc(
        'remove_${widget._rpcSuffix}',
        params: {widget._idParam: widget._id, 'p_phone': o.phone},
      );
      _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Kaldırılamadı: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminFormSection(
      title: widget._title,
      child: FutureBuilder<List<_Owner>>(
        future: _owners,
        builder: (context, snap) {
          final owners = snap.data ?? const <_Owner>[];
          return AdminFieldGroup(
            children: [
              if (snap.connectionState == ConnectionState.waiting)
                AdminSelectRow(
                  icon: Icons.manage_accounts_outlined,
                  label: widget._region ? 'Sorumlular' : 'Sahipler',
                  value: null,
                  placeholder: 'Yükleniyor…',
                  loading: true,
                  onTap: null,
                )
              else if (snap.hasError)
                AdminFieldRow(
                  icon: Icons.error_outline_rounded,
                  label: 'Sahipler',
                  onTap: _reload,
                  trailing: const Icon(
                    Icons.refresh_rounded,
                    color: Colors.white54,
                  ),
                  child: const Text(
                    'Liste okunamadı, yeniden deneyin.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              for (final o in owners)
                AdminFieldRow(
                  icon: o.hasAccount
                      ? Icons.verified_user_outlined
                      : Icons.hourglass_empty_rounded,
                  label: o.hasAccount
                      ? _formatPhone(o.phone)
                      : '${_formatPhone(o.phone)} · kayıt bekleniyor',
                  trailing: IconButton(
                    tooltip: 'Kaldır',
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy ? null : () => _remove(o),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white54,
                      size: 20,
                    ),
                  ),
                  child: Text(
                    o.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              AdminFieldRow(
                icon: Icons.person_add_alt_1_outlined,
                label: owners.isEmpty
                    ? (widget._region ? 'Henüz sorumlu yok' : 'Henüz sahip yok')
                    : (widget._region ? 'Yeni sorumlu' : 'Yeni sahip'),
                onTap: _busy ? null : _add,
                trailing: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kAdminAccent,
                        ),
                      )
                    : const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white54,
                      ),
                child: const Text(
                  'Ad soyad ve telefonla ekle',
                  style: TextStyle(
                    color: kAdminAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Ad soyad + telefon girişi; iptalde null.
Future<({String name, String phone})?> _showAddOwnerDialog(
  BuildContext context, {
  bool region = false,
}) async {
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final result = await showDialog<({String name, String phone})>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final digits = phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
        final valid =
            nameCtrl.text.trim().length >= 3 &&
            RegExp(r'^0?5\d{9}$').hasMatch(digits);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: AdminDialogCloseOverlay(
            onClose: () => Navigator.pop(ctx),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: adminDialogDecoration(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminDialogHeader(
                    icon: Icons.person_add_alt_1_outlined,
                    title: region
                        ? 'Bölge Sorumlusu Ekle'
                        : 'Turnuva Sahibi Ekle',
                    subtitle:
                        'Kişi bu telefonla Kayıt Ol\'dan kayıt olup '
                        'onaylandığında ${region ? 'bölgeyi' : 'turnuvayı'} '
                        'yönetebilir.',
                  ),
                  const SizedBox(height: 16),
                  AdminFieldGroup(
                    children: [
                      AdminFieldRow(
                        icon: Icons.person_outline_rounded,
                        label: 'Ad Soyad',
                        child: TextField(
                          controller: nameCtrl,
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: adminInlineInputDecoration(
                            hint: 'Örn. Ahmet Yılmaz',
                          ),
                        ),
                      ),
                      AdminFieldRow(
                        icon: Icons.phone_iphone_rounded,
                        label: 'Cep Telefonu',
                        child: TextField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [PhoneMaskFormatter()],
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: adminInlineInputDecoration(
                            hint: '(5XX) XXX XX XX',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  AdminPrimaryButton(
                    label: 'EKLE',
                    onPressed: !valid
                        ? null
                        : () => Navigator.pop(ctx, (
                            name: nameCtrl.text.trim(),
                            phone: digits,
                          )),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  Future<void>.delayed(const Duration(milliseconds: 600), () {
    nameCtrl.dispose();
    phoneCtrl.dispose();
  });
  return result;
}
