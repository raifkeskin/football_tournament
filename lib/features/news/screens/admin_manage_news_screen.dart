import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../tournament/models/league.dart';
import '../../tournament/models/league_extras.dart';
import '../../../core/services/app_session.dart';
import '../../tournament/services/interfaces/i_league_service.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/custom_popup_selector.dart';
import '../../../core/widgets/web_safe_image.dart';

class AdminManageNewsScreen extends StatefulWidget {
  const AdminManageNewsScreen({super.key});

  @override
  State<AdminManageNewsScreen> createState() => _AdminManageNewsScreenState();
}

class _AdminManageNewsScreenState extends State<AdminManageNewsScreen> {
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final Set<String> _busyIds = {};
  String? _selectedTournamentId;

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
    final existingUrl = (item?.imageUrl ?? '').trim();
    XFile? picked;
    var removeImage = false;
    var publishNow = true;
    var saving = false;

    Future<void> pickPhoto(StateSetter setLocal) async {
      // Yüklemeden önce küçültülür: depolama ve mobil veri dostu.
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
      );
      if (file == null) return;
      setLocal(() {
        picked = file;
        removeImage = false;
      });
    }

    Future<void> save(BuildContext ctx, StateSetter setLocal) async {
      final text = controller.text.trim();
      if (text.isEmpty) {
        _snack('Lütfen bir haber metni girin.');
        return;
      }
      final tId = (_selectedTournamentId ?? '').trim();
      if (!isEdit && tId.isEmpty) {
        _snack('Lütfen önce turnuva seçin.');
        return;
      }
      setLocal(() => saving = true);
      if (isEdit) setState(() => _busyIds.add(item.id));
      try {
        String? imageUrl = removeImage || existingUrl.isEmpty
            ? null
            : existingUrl;
        final file = picked;
        if (file != null) {
          imageUrl = await ImgBBUploadService().uploadImage(File(file.path));
          if (imageUrl == null) {
            throw Exception('Fotoğraf yüklenemedi, tekrar deneyin.');
          }
        }
        if (isEdit) {
          await _leagueService.updateNews(
            newsId: item.id,
            content: text,
            imageUrl: imageUrl,
          );
        } else {
          await _leagueService.addNews(
            tournamentId: tId,
            content: text,
            imageUrl: imageUrl,
            isPublished: publishNow,
          );
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
      final file = picked;
      final showExisting = file == null && !removeImage && existingUrl.isNotEmpty;
      final hasPhoto = file != null || showExisting;

      if (!hasPhoto) {
        return InkWell(
          onTap: saving ? null : () => pickPhoto(setLocal),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_photo_alternate_outlined,
                    color: kAdminAccent, size: 32),
                SizedBox(height: 8),
                Text(
                  'Fotoğraf ekle',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      final preview = file != null
          ? (kIsWeb
                ? Image.network(file.path, fit: BoxFit.cover)
                : Image.file(File(file.path), fit: BoxFit.cover))
          : WebSafeImage(url: existingUrl, fit: BoxFit.cover);

      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: Stack(
            fit: StackFit.expand,
            children: [
              preview,
              Positioned(
                right: 8,
                bottom: 8,
                child: Row(
                  children: [
                    _PhotoButton(
                      icon: Icons.image_outlined,
                      label: 'Değiştir',
                      onTap: saving ? null : () => pickPhoto(setLocal),
                    ),
                    const SizedBox(width: 8),
                    _PhotoButton(
                      icon: Icons.delete_outline_rounded,
                      color: kAdminDanger,
                      tooltip: 'Fotoğrafı kaldır',
                      onTap: saving
                          ? null
                          : () => setLocal(() {
                              picked = null;
                              removeImage = true;
                            }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
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

  Future<void> _deleteNews(String newsId) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Haberi Sil',
      message: 'Bu haber silinecek. Devam edilsin mi?',
    );
    if (!ok) return;

    setState(() => _busyIds.add(newsId));
    try {
      await _leagueService.deleteNews(newsId: newsId);
      if (mounted) _snack('Haber silindi.');
    } catch (e) {
      if (mounted) _snack('Hata: $e');
    } finally {
      if (mounted) setState(() => _busyIds.remove(newsId));
    }
  }

  Widget _newsCard(NewsItem doc) {
    final isPublished = doc.isPublished;
    final createdAtText = _tarihYaz(doc.createdAt);
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
                  color: (isPublished ? published : draft).withValues(
                    alpha: 0.15,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isPublished ? 'Yayında' : 'Kapalı',
                  style: TextStyle(
                    color: isPublished ? published : draft,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (createdAtText.isNotEmpty || likes.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '$createdAtText$likes',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ],
              const Spacer(),
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
                  onTap: () =>
                      _openNewsForm(item: doc),
                ),
                const SizedBox(width: 6),
                AdminSmallAction(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Sil',
                  color: kAdminDanger,
                  onTap: () => _deleteNews(doc.id),
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
    if (!session.isAdmin && !session.isLeagueOwner) {
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
        stream: _leagueService.watchLeagues(),
        builder: (context, tSnap) {
          if (!tSnap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: kAdminAccent),
            );
          }
          // Admin her turnuvayı, turnuva sahibi sadece kendisininkileri görür.
          final tournaments = (tSnap.data ?? const <League>[])
              .where((l) => session.canManageLeague(l.id))
              .toList();
          if (tournaments.isEmpty) {
            return const Center(
              child: Text(
                'Turnuva bulunamadı.',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }
          if (tournaments.every((l) => l.id != _selectedTournamentId)) {
            _selectedTournamentId = tournaments.first.id;
          }
          final tId = (_selectedTournamentId ?? '').trim();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: CustomPopupSelector<String>(
                  label: 'Turnuva',
                  selectedValue: tId.isEmpty ? tournaments.first.id : tId,
                  items: tournaments.map((l) => l.id).toList(),
                  labelBuilder: (id) => tournaments
                      .firstWhere(
                        (l) => l.id == id,
                        orElse: () => tournaments.first,
                      )
                      .name,
                  onChanged: (v) => setState(() => _selectedTournamentId = v),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<List<NewsItem>>(
                  stream: tId.isEmpty
                      ? const Stream.empty()
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
                    final docs = snapshot.data ?? const <NewsItem>[];
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text(
                          'Kayıtlı haber bulunamadı.\n'
                          'Sağ üstteki butondan haber ekleyebilirsiniz.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54),
                        ),
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: docs.map(_newsCard).toList(),
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

/// Fotoğraf önizlemesinin üzerindeki küçük koyu buton (Değiştir / Kaldır).
class _PhotoButton extends StatelessWidget {
  const _PhotoButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.tooltip,
    this.color = Colors.white,
  });

  final IconData icon;
  final String? label;
  final String? tooltip;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: const Color(0xFF0F172A).withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 40,
          constraints: const BoxConstraints(minWidth: 40),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 12),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label!,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    final tip = tooltip;
    return tip == null ? child : Tooltip(message: tip, child: child);
  }
}
