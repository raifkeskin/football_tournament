import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/active_tournament.dart';
import '../../core/services/app_session.dart';
import '../../core/services/image_upload_service.dart';
import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../../core/widgets/picked_image.dart';
import 'match_poster.dart';
import 'poster_background.dart';
import 'poster_share.dart';

/// Afiş Arka Planı: turnuvanın bütün afişlerinde (maç, fikstür, kadro,
/// diziliş, puan durumu) kullanılan tek zemin görseli. Turnuva başına tek
/// dosya tutulur; yenisi kaydedilince eskisi depodan silinir. Şimdilik
/// yalnızca admin.
class AdminPosterBackgroundScreen extends StatefulWidget {
  const AdminPosterBackgroundScreen({super.key});

  @override
  State<AdminPosterBackgroundScreen> createState() =>
      _AdminPosterBackgroundScreenState();
}

class _AdminPosterBackgroundScreenState
    extends State<AdminPosterBackgroundScreen> {
  SupabaseClient get _sb => Supabase.instance.client;
  final _uploader = SupabaseImageUploadService();

  List<LeagueChoice>? _leagues;
  String? _leagueId;

  /// Kayıtlı görsel ('' = yok, null = okunuyor).
  String? _currentUrl;

  /// Seçilmiş, henüz kaydedilmemiş görsel.
  XFile? _pending;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadLeagues();
  }

  Future<void> _loadLeagues() async {
    try {
      final rows = await _sb
          .from('leagues')
          .select('id, name, logo_url, is_active')
          .order('name');
      final list = [
        for (final r in rows)
          if (r['is_active'] != false)
            LeagueChoice(
              id: r['id'].toString(),
              name: (r['name'] ?? '').toString(),
              logoUrl: (r['logo_url'] ?? '').toString(),
            ),
      ];
      if (!mounted) return;
      final current = ActiveTournament.currentLeagueId.value;
      setState(() {
        _leagues = list;
        _leagueId = list.any((l) => l.id == current)
            ? current
            : (list.isEmpty ? null : list.first.id);
      });
      await _loadCurrent();
    } catch (e) {
      if (mounted) {
        setState(() => _leagues = const []);
        _snack('Turnuvalar yüklenemedi: $e');
      }
    }
  }

  Future<void> _loadCurrent() async {
    final id = _leagueId;
    if (id == null) return;
    try {
      final row = await _sb
          .from('leagues')
          .select('poster_bg_url')
          .eq('id', id)
          .maybeSingle();
      if (!mounted || id != _leagueId) return;
      setState(
        () => _currentUrl = (row?['poster_bg_url'] ?? '').toString().trim(),
      );
    } catch (e) {
      if (mounted) _snack('Afiş arka planı okunamadı: $e');
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pickLeague() async {
    final leagues = _leagues ?? const <LeagueChoice>[];
    final picked = await showAdminOptionPicker<LeagueChoice>(
      context: context,
      title: 'Turnuva',
      items: leagues,
      labelBuilder: (l) => l.name,
      selected: leagues.where((l) => l.id == _leagueId).firstOrNull,
    );
    if (picked == null || picked.id == _leagueId) return;
    setState(() {
      _leagueId = picked.id;
      _currentUrl = null;
      _pending = null;
    });
    await _loadCurrent();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() => _pending = picked);
  }

  /// Yeni görseli yükler, turnuvaya bağlar ve eskisini siler. Kayıt başarısız
  /// olursa yeni yüklenen dosya da silinir; depoda turnuva başına tek dosya
  /// kalır.
  Future<void> _save() async {
    final leagueId = _leagueId;
    final file = _pending;
    if (leagueId == null || file == null) return;
    setState(() => _busy = true);
    String? newUrl;
    try {
      newUrl = await _uploader.uploadImage(
        file,
        folder: MediaFolder.posters,
        subfolder: leagueId,
      );
      if (newUrl == null) throw Exception('Görsel yüklenemedi.');
      await _sb
          .from('leagues')
          .update({'poster_bg_url': newUrl})
          .eq('id', leagueId);
      final old = _currentUrl ?? '';
      if (old.isNotEmpty && old != newUrl) {
        await _uploader.deleteImageByUrl(old);
      }
      PosterBackgrounds.remember(leagueId, newUrl);
      if (!mounted) return;
      setState(() {
        _currentUrl = newUrl;
        _pending = null;
      });
      _snack('Afiş arka planı kaydedildi.');
    } catch (e) {
      if (newUrl != null) await _uploader.deleteImageByUrl(newUrl);
      if (mounted) _snack('Kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final leagueId = _leagueId;
    final old = _currentUrl ?? '';
    if (leagueId == null || old.isEmpty) return;
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Arka Planı Kaldır',
      message:
          'Görsel silinecek; afişler yeniden varsayılan zeminle hazırlanacak.',
      confirmLabel: 'KALDIR',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _sb
          .from('leagues')
          .update({'poster_bg_url': null})
          .eq('id', leagueId);
      await _uploader.deleteImageByUrl(old);
      PosterBackgrounds.remember(leagueId, null);
      if (!mounted) return;
      setState(() => _currentUrl = '');
      _snack('Afiş arka planı kaldırıldı.');
    } catch (e) {
      if (mounted) _snack('Kaldırılamadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _preview(LeagueChoice? league) {
    final pending = _pending;
    final current = _currentUrl ?? '';
    final ImageProvider? image = pending != null
        ? pickedImageProvider(pending)
        : (current.isEmpty ? null : NetworkImage(current));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: AspectRatio(
          aspectRatio: kPosterSize.width / kPosterSize.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: FittedBox(
              child: SizedBox.fromSize(
                size: kPosterSize,
                child: PosterBackground(
                  image: image,
                  child: MatchPoster(
                    leagueName: league?.name ?? '',
                    leagueLogo: league?.logoUrl ?? '',
                    groupName: '',
                    week: 1,
                    homeName: 'Ev Sahibi',
                    homeLogo: '',
                    awayName: 'Deplasman',
                    awayLogo: '',
                    pitchName: 'Saha',
                    dayName: 'Pazar',
                    dateText: '01.11.2026',
                    timeText: '20:00',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const title = 'Afiş Arka Planı';
    if (!AppSession.of(context).value.isAdmin) {
      return const AdminPageScaffold(
        title: title,
        body: Center(
          child: Text(
            'Bu ekrana yalnızca admin erişebilir.',
            style: TextStyle(color: kAdminMuted),
          ),
        ),
      );
    }
    final leagues = _leagues;
    final league = leagues?.where((l) => l.id == _leagueId).firstOrNull;
    final Widget body;
    if (leagues == null || (_leagueId != null && _currentUrl == null)) {
      body = const Center(child: CircularProgressIndicator());
    } else if (leagues.isEmpty) {
      body = const Center(
        child: Text('Turnuva yok.', style: TextStyle(color: kAdminMuted)),
      );
    } else {
      final hasCurrent = (_currentUrl ?? '').isNotEmpty;
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          AdminFieldGroup(
            children: [
              AdminSelectRow(
                icon: Icons.emoji_events_rounded,
                label: 'Turnuva',
                value: league?.name,
                placeholder: 'Turnuva seçin',
                onTap: leagues.length > 1 && !_busy ? _pickLeague : null,
                locked: leagues.length <= 1,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 18),
            child: Text(
              _pending != null
                  ? 'Önizleme: kaydedince maç, fikstür, kadro, diziliş ve puan '
                        'durumu afişlerinde bu görsel kullanılır'
                        '${hasCurrent ? '; mevcut görsel silinir' : ''}.'
                  : hasCurrent
                  ? 'Bu turnuvanın bütün afişleri bu görselle hazırlanıyor. '
                        'Turnuva başına tek görsel tutulur.'
                  : 'Bu turnuvanın afiş arka planı yok; afişler varsayılan '
                        'zeminle hazırlanıyor. Dikey (9:16) bir görsel en iyi '
                        'sonucu verir.',
              style: const TextStyle(
                color: kAdminMuted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
          _preview(league),
          const SizedBox(height: 20),
          if (_pending != null) ...[
            AdminPrimaryButton(
              label: 'KAYDET',
              icon: Icons.check_rounded,
              busy: _busy,
              onPressed: _save,
            ),
            const SizedBox(height: 10),
            AdminSecondaryButton(
              onPressed: _busy ? null : () => setState(() => _pending = null),
            ),
          ] else ...[
            AdminPrimaryButton(
              label: hasCurrent ? 'GÖRSELİ DEĞİŞTİR' : 'GÖRSEL YÜKLE',
              icon: Icons.add_photo_alternate_rounded,
              busy: _busy,
              onPressed: _pickImage,
            ),
            if (hasCurrent) ...[
              const SizedBox(height: 10),
              AdminSecondaryButton(
                label: 'KALDIR',
                onPressed: _busy ? null : _remove,
              ),
            ],
          ],
        ],
      );
    }
    return AdminPageScaffold(title: title, body: body);
  }
}
