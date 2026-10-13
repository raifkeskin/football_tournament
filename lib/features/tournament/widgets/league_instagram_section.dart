import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';

/// Bağlı Instagram hesabının özeti (belirteç sunucuda kalır).
class _IgStatus {
  const _IgStatus({
    required this.username,
    required this.expiresAt,
    required this.canPublish,
  });

  final String username;
  final DateTime? expiresAt;
  final bool canPublish;
}

/// Turnuva formundaki "Instagram Paylaşımı" bölümü (admin + kurucu başkan).
///
/// "Bağla" Instagram yetkilendirme sayfasını tarayıcıda açar; dönüşte
/// instagram-oauth-callback belirteci kaydeder. Uygulamaya geri dönülünce
/// durum yenilenir (bkz. migration 20261020140000_instagram_accounts).
class LeagueInstagramSection extends StatefulWidget {
  const LeagueInstagramSection({super.key, required this.leagueId});

  final String leagueId;

  @override
  State<LeagueInstagramSection> createState() => _LeagueInstagramSectionState();
}

class _LeagueInstagramSectionState extends State<LeagueInstagramSection> {
  final _sb = Supabase.instance.client;
  late Future<_IgStatus?> _status = _load();
  late final AppLifecycleListener _lifecycle;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Tarayıcıdan dönünce bağlantı sonucunu göster.
    _lifecycle = AppLifecycleListener(onResume: _reload);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<_IgStatus?> _load() async {
    final rows = await _sb.rpc(
      'league_instagram_status',
      params: {'p_league_id': widget.leagueId},
    );
    final list = rows as List;
    if (list.isEmpty) return null;
    final r = list.first as Map;
    return _IgStatus(
      username: (r['username'] ?? '').toString(),
      expiresAt: DateTime.tryParse((r['expires_at'] ?? '').toString()),
      canPublish: r['can_publish'] == true,
    );
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _status = _load();
    });
  }

  Future<void> _connect() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final res = await _sb.functions.invoke(
        'instagram-connect',
        body: {'league_id': widget.leagueId},
      );
      final url = (res.data as Map?)?['url']?.toString();
      if (url == null) throw 'Adres alınamadı.';
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on FunctionException catch (e) {
      final d = e.details;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            d is Map && d['error'] != null
                ? d['error'].toString()
                : 'Bağlantı başlatılamadı (${e.status}).',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Bağlantı başlatılamadı: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect(_IgStatus s) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Instagram Bağlantısını Kaldır',
      message:
          '@${s.username} hesabına uygulamadan artık paylaşım yapılamayacak. '
          'Instagram hesabınız ve paylaşımlarınız etkilenmez.',
      confirmLabel: 'KALDIR',
      icon: Icons.link_off_rounded,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await _sb.rpc(
        'disconnect_league_instagram',
        params: {'p_league_id': widget.leagueId},
      );
      _reload();
    } on PostgrestException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _date(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    return AdminFormSection(
      title: 'Instagram Paylaşımı',
      trailing: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      child: FutureBuilder<_IgStatus?>(
        future: _status,
        builder: (context, snap) {
          final s = snap.data;
          final loading = snap.connectionState != ConnectionState.done;
          final String value;
          final String? note;
          if (loading) {
            value = '…';
            note = null;
          } else if (snap.hasError) {
            value = 'Durum okunamadı';
            note = null;
          } else if (s == null) {
            value = 'Bağlı değil';
            note =
                'Haberleri bu turnuvanın Instagram hesabında yayınlamak için '
                'hesabı bir kez bağlayın. Hesap profesyonel (işletme veya '
                'içerik üreticisi) olmalı.';
          } else {
            value = '@${s.username}';
            final expired =
                s.expiresAt != null && s.expiresAt!.isBefore(DateTime.now());
            note = !s.canPublish
                ? 'Paylaşım izni verilmemiş. Bağlantıyı kaldırıp tekrar '
                      'bağlayın ve "içerik yayınlama" iznini açık bırakın.'
                : expired
                ? 'Erişim süresi doldu. Tekrar bağlayın.'
                : s.expiresAt != null
                ? 'Erişim ${_date(s.expiresAt!)} tarihine kadar geçerli.'
                : null;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminFieldGroup(
                children: [
                  AdminFieldRow(
                    icon: Icons.camera_alt_outlined,
                    label: 'Bağlı hesap',
                    trailing: loading
                        ? null
                        : s == null
                        ? TextButton(
                            onPressed: _busy ? null : _connect,
                            child: const Text(
                              'BAĞLA',
                              style: TextStyle(
                                color: kAdminAccent,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                        : AdminSmallAction(
                            icon: Icons.link_off_rounded,
                            tooltip: 'Bağlantıyı kaldır',
                            color: kAdminDanger,
                            onTap: _busy ? null : () => _disconnect(s),
                          ),
                    child: Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    note,
                    style: const TextStyle(
                      color: kAdminMuted,
                      fontSize: 12,
                      height: 1.35,
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
