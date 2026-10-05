import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../tournament/models/league.dart';
import '../../tournament/models/league_extras.dart';
import '../../../core/services/app_session.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/app_date_picker.dart';
import '../../../core/widgets/custom_popup_selector.dart';
import '../../../core/widgets/web_safe_image.dart';
import 'package:football_tournament/core/widgets/picked_image.dart';

class AdminManageNewsScreen extends StatefulWidget {
  const AdminManageNewsScreen({super.key});

  @override
  State<AdminManageNewsScreen> createState() => _AdminManageNewsScreenState();
}

class _AdminManageNewsScreenState extends State<AdminManageNewsScreen> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final Set<String> _busyIds = {};
  late final Stream<List<League>> _leaguesStream = _leagueService
      .watchLeagues();

  /// Kullanıcının yönetebildiği turnuvalar (admin: hepsi, sahibi: kendi).
  List<League> _tournaments = const [];
  String? _selectedTournamentId;
  _NewsStatus _status = _NewsStatus.all;

  /// Filtrede "Tümü" (bütün yönetilebilen turnuvalar).
  static const _allTournaments = '';

  /// Bölgeler (id → ad, turnuva); haber isteğe bağlı bir bölgeye bağlanır.
  Map<String, ({String name, String leagueId})> _regions = const {};

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  Future<void> _loadRegions() async {
    try {
      final rows = await Supabase.instance.client
          .from('season_regions')
          .select('id, name, sort_order, seasons(league_id)')
          .order('sort_order', ascending: true);
      if (!mounted) return;
      setState(() {
        _regions = {
          for (final r in rows)
            (r['id'] ?? '').toString(): (
              name: (r['name'] ?? '').toString(),
              leagueId: ((r['seasons'] as Map?)?['league_id'] ?? '').toString(),
            ),
        };
      });
    } catch (e) {
      debugPrint('Bölgeler okunamadı: $e');
    }
  }

  /// Kullanıcının bu turnuvada haber girebileceği bölgeler. Kurucu/admin
  /// tüm bölgeleri seçebilir; bölge sorumlusu yalnızca kendininkileri.
  List<String> _regionsFor(String leagueId) {
    final session = AppSession.of(context).value;
    final full = session.canManageLeague(leagueId);
    final mine = {for (final r in session.ownedRegions) r.id};
    return [
      for (final e in _regions.entries)
        if (e.value.leagueId == leagueId && (full || mine.contains(e.key)))
          e.key,
    ];
  }

  String _tournamentName(String? id) {
    for (final l in _tournaments) {
      if (l.id == id) return l.name;
    }
    return '';
  }

  String _statusLabel(_NewsStatus s) => switch (s) {
    _NewsStatus.all => 'Tümü',
    _NewsStatus.live => 'Yayında',
    _NewsStatus.passive => 'Pasif',
  };

  Future<void> _openFilters() {
    return showAdminFilterDialog(
      context: context,
      fieldsBuilder: (ctx, refresh) => [
        CustomPopupSelector<String>(
          label: 'Turnuva',
          selectedValue: _selectedTournamentId,
          items: [_allTournaments, ..._tournaments.map((l) => l.id)],
          labelBuilder: (id) =>
              id == _allTournaments ? 'Tümü' : _tournamentName(id),
          onChanged: (v) {
            setState(() => _selectedTournamentId = v);
            refresh();
          },
        ),
        CustomPopupSelector<_NewsStatus>(
          label: 'Durum',
          selectedValue: _status,
          items: _NewsStatus.values,
          labelBuilder: (v) => _statusLabel(v ?? _NewsStatus.all),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _status = v);
            refresh();
          },
        ),
      ],
    );
  }

  String _tarihYaz(DateTime? createdAt) {
    final d = createdAt;
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _toggle(String newsId, bool next) async {
    setState(() => _busyIds.add(newsId));
    try {
      await _leagueService.setNewsPublished(newsId: newsId, isPublished: next);
      if (mounted) {
        _snack(next ? 'Haber yayınlandı.' : 'Haber yayından kaldırıldı.');
      }
    } catch (e) {
      if (mounted) _snack('Hata: $e');
    } finally {
      if (mounted) setState(() => _busyIds.remove(newsId));
    }
  }

  /// Haber ekleme / düzenleme için ortak popup ([item] null ise ekleme).
  Future<void> _openNewsForm({NewsItem? item}) async {
    final isEdit = item != null;
    final controller = TextEditingController(text: item?.content ?? '');
    // Fotoğraflar (en fazla 5): kayıtlı adresler ve yeni seçilen dosyalar,
    // gösterim sırasıyla. İlki kapak olur.
    const maxPhotos = 5;
    final existingUrls = [...?item?.imageUrls];
    final photos = <Object>[...existingUrls]; // String (adres) | XFile
    var publishNow = true;
    var saving = false;
    // Ekleme: filtredeki turnuva önerilir ama popup'ta değiştirilebilir.
    var formTournamentId = isEdit
        ? item.tournamentId
        : (_selectedTournamentId ?? '').trim();
    DateTime? publishUntil = item?.publishUntil;
    // Bölge sorumlusu turnuvanın tamamına haber giremez: bölge zorunlu.
    bool regionRequired(String tId) =>
        !AppSession.of(context).value.canManageLeague(tId);
    String? defaultRegion(String tId) {
      if (!regionRequired(tId)) return null;
      final list = _regionsFor(tId);
      return list.isEmpty ? null : list.first;
    }

    var formRegionId = isEdit ? item.regionId : defaultRegion(formTournamentId);

    Future<void> pickRegion(StateSetter setLocal) async {
      final options = _regionsFor(formTournamentId);
      final required = regionRequired(formTournamentId);
      final picked = await showAdminOptionPicker<String>(
        context: context,
        title: 'Bölge Seçin',
        items: [if (!required) '', ...options],
        labelBuilder: (id) =>
            id.isEmpty ? 'Tüm turnuva' : (_regions[id]?.name ?? ''),
        selected: formRegionId ?? (required ? null : ''),
      );
      if (picked != null) {
        setLocal(() => formRegionId = picked.isEmpty ? null : picked);
      }
    }

    Future<void> pickTournament(StateSetter setLocal) async {
      final picked = await showAdminOptionPicker<String>(
        context: context,
        title: 'Turnuva Seçin',
        items: _tournaments.map((l) => l.id).toList(),
        labelBuilder: _tournamentName,
        selected: formTournamentId.isEmpty ? null : formTournamentId,
      );
      if (picked != null) {
        setLocal(() {
          formTournamentId = picked;
          formRegionId = defaultRegion(picked);
        });
      }
    }

    Future<void> pickUntil(StateSetter setLocal) async {
      final now = DateTime.now();
      final d = await showAppDatePicker(
        context: context,
        initialDate: publishUntil ?? now.add(const Duration(days: 7)),
        firstYear: now.year,
        lastYear: now.year + 2,
        title: 'Yayın Bitiş Tarihi',
      );
      if (d == null) return;
      // Seçilen günün sonuna kadar yayında kalır.
      final end = DateTime(d.year, d.month, d.day, 23, 59, 59);
      if (!end.isAfter(now)) {
        _snack('Bitiş tarihi bugünden önce olamaz.');
        return;
      }
      setLocal(() => publishUntil = end);
    }

    Future<void> pickPhotos(StateSetter setLocal) async {
      final room = maxPhotos - photos.length;
      if (room <= 0) return;
      // Yüklemeden önce ayrıca küçültülür (bkz. SupabaseImageUploadService).
      final files = await ImagePicker().pickMultiImage(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
        limit: room > 1 ? room : null,
      );
      if (files.isEmpty) return;
      if (files.length > room) {
        _snack('En fazla $maxPhotos fotoğraf eklenebilir.');
      }
      setLocal(() => photos.addAll(files.take(room)));
    }

    Future<void> save(BuildContext ctx, StateSetter setLocal) async {
      final text = controller.text.trim();
      if (text.isEmpty) {
        _snack('Lütfen bir haber metni girin.');
        return;
      }
      final tId = formTournamentId.trim();
      if (!isEdit && tId.isEmpty) {
        _snack('Lütfen turnuva seçin.');
        return;
      }
      if (regionRequired(tId) && formRegionId == null) {
        _snack('Lütfen bölge seçin.');
        return;
      }
      setLocal(() => saving = true);
      if (isEdit) setState(() => _busyIds.add(item.id));
      try {
        // Yeni dosyalar sırası korunarak yüklenir.
        final urls = <String>[];
        for (final p in photos) {
          if (p is String) {
            urls.add(p);
            continue;
          }
          final url = await SupabaseImageUploadService().uploadImage(
            p as XFile,
            folder: MediaFolder.news,
          );
          if (url == null) {
            throw Exception('Fotoğraf yüklenemedi, tekrar deneyin.');
          }
          urls.add(url);
        }
        if (isEdit) {
          await _leagueService.updateNews(
            newsId: item.id,
            content: text,
            imageUrls: urls,
            publishUntil: publishUntil,
            regionId: formRegionId,
          );
        } else {
          await _leagueService.addNews(
            tournamentId: tId,
            content: text,
            imageUrls: urls,
            isPublished: publishNow,
            publishUntil: publishUntil,
            regionId: formRegionId,
          );
        }
        // Formdan kaldırılan eski fotoğraflar depodan da silinir.
        for (final old in existingUrls) {
          if (!urls.contains(old)) {
            await SupabaseImageUploadService().deleteImageByUrl(old);
          }
        }
        if (ctx.mounted) Navigator.pop(ctx);
        if (mounted) _snack(isEdit ? 'Haber güncellendi.' : 'Haber eklendi.');
      } catch (e) {
        if (mounted) _snack('Hata: $e');
        if (ctx.mounted) setLocal(() => saving = false);
      } finally {
        if (isEdit && mounted) setState(() => _busyIds.remove(item.id));
      }
    }

    Widget photoField(StateSetter setLocal) {
      Widget thumb(Object p, int i) {
        final Widget image = p is String
            ? WebSafeImage(url: p, fit: BoxFit.cover)
            : (kIsWeb
                  ? Image.network((p as XFile).path, fit: BoxFit.cover)
                  : Image(
                      image: pickedImageProvider(p as XFile),
                      fit: BoxFit.cover,
                    ));
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              fit: StackFit.expand,
              children: [
                image,
                if (i == 0)
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Kapak',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 2,
                  top: 2,
                  child: _PhotoButton(
                    icon: Icons.close_rounded,
                    color: kAdminDanger,
                    tooltip: 'Fotoğrafı kaldır',
                    onTap: saving
                        ? null
                        : () => setLocal(() => photos.removeAt(i)),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < photos.length; i++) thumb(photos[i], i),
          if (photos.length < maxPhotos)
            InkWell(
              onTap: saving ? null : () => pickPhotos(setLocal),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: kAdminAccent,
                      size: 26,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Fotoğraf ${photos.length}/$maxPhotos',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: adminDialogDecoration(),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isEdit ? Icons.edit_note_rounded : Icons.post_add,
                        color: kAdminAccent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isEdit ? 'Haberi Düzenle' : 'Haber Ekle',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 16),
                  AdminFieldGroup(
                    children: [
                      AdminSelectRow(
                        icon: Icons.emoji_events_outlined,
                        label: 'Turnuva',
                        value: _tournamentName(formTournamentId),
                        placeholder: 'Turnuva seçin',
                        locked: isEdit,
                        onTap: saving ? null : () => pickTournament(setLocal),
                      ),
                      if (_regionsFor(formTournamentId).isNotEmpty)
                        AdminSelectRow(
                          icon: Icons.map_outlined,
                          label: regionRequired(formTournamentId)
                              ? 'Bölge'
                              : 'Bölge (isteğe bağlı)',
                          value: formRegionId == null
                              ? null
                              : _regions[formRegionId]?.name,
                          placeholder: 'Tüm turnuva',
                          onTap: saving ? null : () => pickRegion(setLocal),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text.rich(
                    TextSpan(
                      text: 'Fotoğraf ',
                      style: TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        TextSpan(
                          text: '(isteğe bağlı)',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  photoField(setLocal),
                  const SizedBox(height: 6),
                  const Text(
                    'Tek fotoğraf · yüklenirken otomatik küçültülür',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    enabled: !saving,
                    minLines: 4,
                    maxLines: 8,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Haber Metni',
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.3),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: kAdminAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AdminFieldGroup(
                    children: [
                      AdminSelectRow(
                        icon: Icons.event_available_outlined,
                        label: 'Yayın bitiş tarihi (isteğe bağlı)',
                        value: publishUntil == null
                            ? null
                            : '${_tarihYaz(publishUntil)} gün sonuna kadar',
                        placeholder: 'Süresiz yayında kalır',
                        onTap: saving ? null : () => pickUntil(setLocal),
                        onClear: () => setLocal(() => publishUntil = null),
                      ),
                    ],
                  ),
                  if (!isEdit) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: publishNow,
                      activeThumbColor: Colors.white,
                      activeTrackColor: kAdminAccent,
                      onChanged: saving
                          ? null
                          : (v) => setLocal(() => publishNow = v),
                      title: const Text(
                        'Hemen yayınla',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text(
                        'Kapalıysa taslak olarak kaydedilir',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAdminAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: saving ? null : () => save(ctx, setLocal),
                      child: saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              isEdit ? 'GÜNCELLE' : 'KAYDET',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      child: const Text(
                        'VAZGEÇ',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // Dialog kapanış animasyonu bitene kadar alan controller'ı kullanır.
    Future<void>.delayed(const Duration(milliseconds: 600), controller.dispose);
  }

  Future<void> _deleteNews(
    String newsId, {
    List<String> imageUrls = const [],
  }) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Haberi Sil',
      message: 'Bu haber silinecek. Devam edilsin mi?',
    );
    if (!ok) return;

    setState(() => _busyIds.add(newsId));
    try {
      await _leagueService.deleteNews(newsId: newsId);
      for (final url in imageUrls) {
        await SupabaseImageUploadService().deleteImageByUrl(url);
      }
      if (mounted) _snack('Haber silindi.');
    } catch (e) {
      if (mounted) _snack('Hata: $e');
    } finally {
      if (mounted) setState(() => _busyIds.remove(newsId));
    }
  }

  Widget _newsCard(NewsItem doc, {bool showTournament = false}) {
    final isPublished = doc.isPublished;
    final expired = isPublished && doc.isExpired;
    final createdAtText = [
      _tarihYaz(doc.createdAt),
      if (doc.publishUntil != null && !expired)
        '${_tarihYaz(doc.publishUntil)}\'e kadar',
    ].join(' → ');
    final busy = _busyIds.contains(doc.id);
    final image = (doc.imageUrl ?? '').trim();
    final likes = doc.likeCount > 0 ? ' · ${doc.likeCount} beğeni' : '';
    const published = kAdminAccent;
    const draft = Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: adminCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTournament || doc.regionId != null) ...[
            Row(
              children: [
                const Icon(
                  Icons.emoji_events_outlined,
                  size: 14,
                  color: kAdminAccent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [
                      if (showTournament) _tournamentName(doc.tournamentId),
                      if (doc.regionId != null)
                        _regions[doc.regionId]?.name ?? '',
                    ].where((t) => t.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kAdminAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (image.isNotEmpty) ...[
                WebSafeImage(
                  url: image,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(10),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  doc.content,
                  maxLines: image.isEmpty ? 4 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (doc.isLive ? published : draft).withValues(
                    alpha: 0.15,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  expired
                      ? 'Süresi doldu'
                      : (isPublished ? 'Yayında' : 'Taslak'),
                  style: TextStyle(
                    color: doc.isLive ? published : draft,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$createdAtText$likes',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kAdminAccent,
                    ),
                  ),
                )
              else ...[
                AdminSmallAction(
                  icon: isPublished
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  tooltip: isPublished ? 'Yayından Kaldır' : 'Yayınla',
                  color: isPublished ? draft : published,
                  onTap: () => _toggle(doc.id, !isPublished),
                ),
                const SizedBox(width: 6),
                AdminSmallAction(
                  icon: Icons.edit_outlined,
                  tooltip: 'Düzenle',
                  color: Colors.white70,
                  onTap: () => _openNewsForm(item: doc),
                ),
                const SizedBox(width: 6),
                AdminSmallAction(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Sil',
                  color: kAdminDanger,
                  onTap: () => _deleteNews(doc.id, imageUrls: doc.imageUrls),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSession.of(context).value;
    if (!session.hasManagementPanel) {
      return const AdminPageScaffold(
        title: 'Haber Yönetimi',
        body: Center(
          child: Text(
            'Bu sayfaya erişim yetkiniz yok.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    return AdminPageScaffold(
      title: 'Haber Yönetimi',
      actions: [
        AdminBarAction(
          icon: Icons.post_add_rounded,
          tooltip: 'Haber Ekle',
          onPressed: () => _openNewsForm(),
        ),
      ],
      body: StreamBuilder<List<League>>(
        stream: _leaguesStream,
        builder: (context, tSnap) {
          if (!tSnap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: kAdminAccent),
            );
          }
          // Admin her turnuvayı; kurucu ve bölge sorumlusu kendininkileri.
          final allowed = session.panelLeagueIds;
          _tournaments = (tSnap.data ?? const <League>[])
              .where((l) => allowed == null || allowed.contains(l.id))
              .toList();
          final myRegions = {for (final r in session.ownedRegions) r.id};
          if (_tournaments.isEmpty) {
            return const Center(
              child: Text(
                'Turnuva bulunamadı.',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }
          if (_selectedTournamentId != _allTournaments &&
              _tournaments.every((l) => l.id != _selectedTournamentId)) {
            _selectedTournamentId = _allTournaments;
          }
          final tId = (_selectedTournamentId ?? '').trim();
          final showAll = tId == _allTournaments;

          return Column(
            children: [
              AdminFilterBar(
                summary:
                    '${showAll ? 'Tüm turnuvalar' : _tournamentName(tId)} • '
                    '${_statusLabel(_status)}',
                onTap: _openFilters,
              ),
              Expanded(
                child: StreamBuilder<List<NewsItem>>(
                  stream: showAll
                      ? _leagueService.watchNewsForLeagues(
                          _tournaments.map((l) => l.id).toSet(),
                        )
                      : _leagueService.watchNews(
                          tournamentId: tId,
                          includeUnpublished: true,
                        ),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: kAdminAccent),
                      );
                    }
                    // Sunucu created_at'e göre azalan sırada döner (en yeni üstte).
                    final docs = (snapshot.data ?? const <NewsItem>[])
                        .where(
                          (n) => switch (_status) {
                            _NewsStatus.all => true,
                            _NewsStatus.live => n.isLive,
                            _NewsStatus.passive => !n.isLive,
                          },
                        )
                        // Bölge sorumlusu yalnızca kendi bölgesinin haberleri.
                        .where(
                          (n) =>
                              session.canManageLeague(n.tournamentId) ||
                              myRegions.contains(n.regionId),
                        )
                        .toList();
                    if (docs.isEmpty) {
                      return Center(
                        child: Text(
                          _status == _NewsStatus.all
                              ? 'Kayıtlı haber bulunamadı.\n'
                                    'Sağ üstteki butondan haber ekleyebilirsiniz.'
                              : '${_statusLabel(_status)} haber yok.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54),
                        ),
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        for (final d in docs)
                          _newsCard(d, showTournament: showAll),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Liste filtresi: yayında = yayınlanmış ve süresi dolmamış; pasif = taslak
/// ya da süresi dolmuş.
enum _NewsStatus { all, live, passive }

/// Fotoğraf önizlemesinin üzerindeki küçük koyu buton (Değiştir / Kaldır).
/// Fotoğraf küçük resminin köşesindeki küçük simge düğmesi.
class _PhotoButton extends StatelessWidget {
  const _PhotoButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color = Colors.white,
  });

  final IconData icon;
  final String? tooltip;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: const Color(0xFF0F172A).withValues(alpha: 0.85),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
    final tip = tooltip;
    return tip == null ? child : Tooltip(message: tip, child: child);
  }
}
