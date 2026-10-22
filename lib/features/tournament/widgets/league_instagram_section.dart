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
    required this.importNews,
    required this.lastSyncedAt,
    required this.lastError,
  });

  final String username;
  final DateTime? expiresAt;
  final bool canPublish;

  /// Gönderiler Haberler'e otomatik aktarılır mı ("Haberlere aktar").
  final bool importNews;
  final DateTime? lastSyncedAt;
  final String? lastError;
}

/// Turnuva formundaki "Instagram Paylaşımı" bölümü (admin + kurucu başkan).
///
/// "Bağla" Instagram yetkilendirme sayfasını tarayıcıda açar; dönüşte
/// instagram-oauth-callback belirteci kaydeder. Uygulamaya geri dönülünce
/// durum yenilenir (bkz. migration 20261020140000_instagram_accounts).
const _importHint =
    '15 dakikada bir yeni gönderiler kontrol edilir. Açıklamasında #ligmasasi '
    'ya da bir bölgenin etiketi olan gönderi hemen haber olur; olmayan, '
    'Bekleyen Onaylar\'da onayınızı bekler.';

/// Aktif sezonun bölgesi ve Instagram etiketi (# olmadan).
class _RegionTag {
  const _RegionTag({required this.id, required this.name, this.tag});

  final String id;
  final String name;
  final String? tag;
}

/// "Haberlere aktar" açıkken gönderiler 15 dakikada bir aktif sezonun
/// haberlerine düşer (instagram-sync, migration 20261020150000).
class LeagueInstagramSection extends StatefulWidget {
  const LeagueInstagramSection({super.key, required this.leagueId});

  final String leagueId;

  @override
  State<LeagueInstagramSection> createState() => _LeagueInstagramSectionState();
}

class _LeagueInstagramSectionState extends State<LeagueInstagramSection> {
  final _sb = Supabase.instance.client;
  late Future<_IgStatus?> _status = _load();
  late Future<List<_RegionTag>> _regions = _loadRegions();
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
      importNews: r['import_news'] == true,
      lastSyncedAt: DateTime.tryParse((r['last_synced_at'] ?? '').toString()),
      lastError: (r['last_error'] ?? '').toString().trim().isEmpty
          ? null
          : r['last_error'].toString(),
    );
  }

  /// Aktif sezonun bölgeleri (bölge yoksa boş; etiket satırları çıkmaz).
  Future<List<_RegionTag>> _loadRegions() async {
    final seasons = await _sb
        .from('seasons')
        .select('id, is_active')
        .eq('league_id', widget.leagueId)
        .isFilter('deleted_at', null)
        .order('start_date', ascending: false);
    if (seasons.isEmpty) return const [];
    final season = seasons.firstWhere(
      (x) => x['is_active'] == true,
      orElse: () => seasons.first,
    );
    final rows = await _sb
        .from('season_regions')
        .select('id, name, instagram_tag')
        .eq('season_id', season['id'])
        .order('sort_order');
    return [
      for (final r in rows)
        _RegionTag(
          id: r['id'].toString(),
          name: (r['name'] ?? '').toString(),
          tag: (r['instagram_tag'] ?? '').toString().trim().isEmpty
              ? null
              : r['instagram_tag'].toString(),
        ),
    ];
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _status = _load();
      _regions = _loadRegions();
    });
  }

  /// Bölgenin Instagram etiketini düzenler (boş bırakılırsa kaldırılır).
  Future<void> _editRegionTag(_RegionTag r) async {
    final messenger = ScaffoldMessenger.of(context);
    final value = await showAdminTextInputDialog(
      context: context,
      title: 'Bölge Etiketi',
      subtitle: r.name,
      icon: Icons.tag_rounded,
      label: 'Etiket',
      fieldIcon: Icons.tag_rounded,
      hint: 'ör. anadolu',
      initialValue: r.tag ?? '',
      validator: (v) {
        final t = v.trim().replaceFirst(RegExp(r'^#'), '');
        if (t.isEmpty) return null;
        if (!RegExp(r'^[\p{L}\p{N}_]{2,40}$', unicode: true).hasMatch(t)) {
          return 'Boşluksuz yazın: harf, rakam ve alt çizgi (2-40).';
        }
        return null;
      },
    );
    if (value == null || !mounted) return;
    final t = value.trim().replaceFirst(RegExp(r'^#'), '');
    setState(() => _busy = true);
    try {
      await _sb
          .from('season_regions')
          .update({'instagram_tag': t.isEmpty ? null : t})
          .eq('id', r.id);
      _reload();
    } on PostgrestException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Bölge etiketleri: açıklamada bölgenin etiketi geçen gönderi hemen o
  /// bölgenin haberi olur.
  Widget _regionTags() => FutureBuilder<List<_RegionTag>>(
    future: _regions,
    builder: (context, snap) {
      final regions = snap.data ?? const <_RegionTag>[];
      if (regions.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminFieldGroup(
              children: [
                for (final r in regions)
                  AdminFieldRow(
                    icon: Icons.tag_rounded,
                    label: 'Bölge etiketi · ${r.name}',
                    onTap: _busy ? null : () => _editRegionTag(r),
                    trailing: const Icon(
                      Icons.edit_outlined,
                      color: kAdminMuted,
                      size: 18,
                    ),
                    child: Text(
                      r.tag == null ? 'Yok' : '#${r.tag}',
                      style: TextStyle(
                        color: r.tag == null ? kAdminMuted : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                'Açıklamasında bölgenin etiketi geçen gönderi hemen o bölgenin '
                'haberi olur. Birden fazla bölgenin etiketi geçerse tüm '
                'turnuvada görünür.',
                style: TextStyle(
                  color: kAdminMuted,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

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
          '@${s.username} gönderileri artık Haberler\'e aktarılmayacak; '
          'aktarılmış haberler kalır. Instagram hesabınız etkilenmez.',
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

  /// Aktarımı aç/kapat; açılınca son gönderiler hemen çekilir.
  Future<void> _setImport(bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await _sb.rpc(
        'set_league_instagram_import',
        params: {'p_league_id': widget.leagueId, 'p_on': on},
      );
      if (on) {
        final res = await _sb.functions.invoke(
          'instagram-sync',
          body: {'league_id': widget.leagueId},
        );
        final n = ((res.data as Map?)?['imported'] as num?)?.toInt() ?? 0;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              n > 0
                  ? '$n Instagram gönderisi Haberler\'e eklendi.'
                  : 'Yeni gönderi yok; yenileri Haberler\'e düşecek.',
            ),
          ),
        );
      }
    } on FunctionException catch (e) {
      final d = e.details;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            d is Map && d['error'] != null
                ? d['error'].toString()
                : 'Gönderiler çekilemedi (${e.status}).',
          ),
        ),
      );
    } on PostgrestException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Ayar kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
      _reload();
    }
  }

  static String _time(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
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
                'Turnuvanın Instagram gönderilerini Haberler\'de göstermek için '
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
                  if (s != null)
                    AdminFieldRow(
                      icon: Icons.newspaper_outlined,
                      label: 'Haberlere aktar',
                      onTap: _busy ? null : () => _setImport(!s.importNews),
                      trailing: Switch.adaptive(
                        value: s.importNews,
                        activeTrackColor: kAdminAccent,
                        onChanged: _busy ? null : _setImport,
                      ),
                      child: Text(
                        s.importNews
                            ? 'Açık · gönderiler Haberler\'e düşer'
                            : 'Kapalı',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              if (s != null && s.importNews)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text(
                    s.lastError != null
                        ? 'Son aktarım başarısız: ${s.lastError}'
                        : s.lastSyncedAt != null
                        ? 'Son kontrol ${_time(s.lastSyncedAt!)} · $_importHint'
                        : _importHint,
                    style: TextStyle(
                      color: s.lastError != null ? kAdminDanger : kAdminMuted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              if (s != null && s.importNews) _regionTags(),
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
