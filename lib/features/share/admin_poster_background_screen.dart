import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/active_tournament.dart';
import '../../core/services/app_session.dart';
import '../../core/services/image_upload_service.dart';
import '../../core/widgets/admin_form.dart';
import '../../core/widgets/admin_page.dart';
import '../../core/widgets/picked_image.dart';
import '../team/utils/standings.dart';
import 'fixture_poster.dart';
import 'match_poster.dart';
import 'poster_background.dart';
import 'poster_share.dart';
import 'standings_poster.dart';

/// Afiş Arka Planı: turnuvanın ortak afiş görseli ve maç, haftalık fikstür,
/// maç sonuçları, puan durumu afişlerine özel görseller. Özel görseli
/// olmayan afiş ortak görseli kullanır. Önizleme turnuvanın kendi
/// takımlarıyla çizilir. Admin bütün turnuvaları, kurucu başkan kendi
/// turnuvalarını yönetir. Kadro, esame ve diziliş afişleri takım rengiyle
/// çizilir, burada yer almaz.
class AdminPosterBackgroundScreen extends StatefulWidget {
  const AdminPosterBackgroundScreen({super.key});

  @override
  State<AdminPosterBackgroundScreen> createState() =>
      _AdminPosterBackgroundScreenState();
}

/// Önizlemedeki takım.
typedef _Team = ({String name, String logo});

class _AdminPosterBackgroundScreenState
    extends State<AdminPosterBackgroundScreen> {
  SupabaseClient get _sb => Supabase.instance.client;
  final _uploader = SupabaseImageUploadService();

  List<LeagueChoice>? _leagues;
  String? _leagueId;

  /// Kayıtlı ortak görsel ('' = yok) ve türe özel görseller; null = okunuyor.
  String? _common;
  Map<String, String> _byKind = const {};

  /// Önizlemede kullanılan turnuva takımları ve grup adı.
  List<_Team> _teams = const [];
  String _groupName = '';

  /// Seçili sekme: null = ortak, aksi halde afiş türü.
  PosterKind? _kind;

  /// Seçilmiş, henüz kaydedilmemiş görsel.
  XFile? _pending;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_leagues == null) _loadLeagues();
  }

  Future<void> _loadLeagues() async {
    final session = AppSession.of(context).value;
    try {
      final rows = await _sb
          .from('leagues')
          .select('id, name, logo_url, status')
          .order('name');
      final list = [
        for (final r in rows)
          if (r['status'] == 'active' &&
              (session.isAdmin ||
                  session.ownedLeagueIds.contains(r['id'].toString())))
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
      await _loadLeague();
    } catch (e) {
      if (mounted) {
        setState(() => _leagues = const []);
        _snack('Turnuvalar yüklenemedi: $e');
      }
    }
  }

  /// Turnuvanın kayıtlı görselleri ve önizleme için güncel sezonun takımları.
  Future<void> _loadLeague() async {
    final id = _leagueId;
    if (id == null) return;
    try {
      final (league, seasons) = await (
        _sb
            .from('leagues')
            .select('poster_bg_url, poster_bgs')
            .eq('id', id)
            .maybeSingle(),
        _sb
            .from('seasons')
            .select('id, is_default, start_date')
            .eq('league_id', id)
            .order('start_date', ascending: false),
      ).wait;
      final season =
          seasons.where((s) => s['is_default'] == true).firstOrNull ??
          seasons.firstOrNull;
      var teams = <_Team>[];
      var groupName = '';
      if (season != null) {
        final rows = await _sb
            .from('season_teams')
            .select('teams(name, logo_url), groups(name)')
            .eq('season_id', season['id'].toString());
        for (final r in rows) {
          final t = r['teams'];
          if (t is! Map) continue;
          teams.add((
            name: (t['name'] ?? '').toString().trim(),
            logo: (t['logo_url'] ?? '').toString().trim(),
          ));
          final g = r['groups'];
          if (groupName.isEmpty && g is Map) {
            groupName = (g['name'] ?? '').toString().trim();
          }
        }
        // Logolu takımlar önce: önizleme gerçeğe yakın görünsün.
        teams.sort((a, b) {
          final la = a.logo.isEmpty ? 1 : 0, lb = b.logo.isEmpty ? 1 : 0;
          return la != lb ? la - lb : a.name.compareTo(b.name);
        });
      }
      if (!mounted || id != _leagueId) return;
      setState(() {
        _common = (league?['poster_bg_url'] ?? '').toString().trim();
        _byKind = PosterBackgrounds.parseKinds(league?['poster_bgs']);
        _teams = teams;
        _groupName = groupName;
      });
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
      _common = null;
      _byKind = const {};
      _teams = const [];
      _pending = null;
    });
    await _loadLeague();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() => _pending = picked);
  }

  /// Seçili sekmenin kendi kayıtlı görseli ('' = yok).
  String get _ownUrl {
    final k = _kind;
    return k == null ? (_common ?? '') : (_byKind[k.key] ?? '');
  }

  /// [url] seçili sekmeye yazılır (null: kaldırılır).
  Future<void> _write(String leagueId, String? url) async {
    final k = _kind;
    if (k == null) {
      await _sb
          .from('leagues')
          .update({'poster_bg_url': url})
          .eq('id', leagueId);
      _common = url ?? '';
    } else {
      final next = {..._byKind};
      if (url == null) {
        next.remove(k.key);
      } else {
        next[k.key] = url;
      }
      await _sb.from('leagues').update({'poster_bgs': next}).eq('id', leagueId);
      _byKind = next;
    }
    PosterBackgrounds.remember(
      leagueId,
      common: _common ?? '',
      byKind: _byKind,
    );
  }

  /// Yeni görseli yükler, sekmeye bağlar ve eskisini siler. Kayıt başarısız
  /// olursa yeni yüklenen dosya da silinir.
  Future<void> _save() async {
    final leagueId = _leagueId;
    final file = _pending;
    if (leagueId == null || file == null) return;
    setState(() => _busy = true);
    String? newUrl;
    final old = _ownUrl;
    try {
      newUrl = await _uploader.uploadImage(
        file,
        folder: MediaFolder.posters,
        subfolder: leagueId,
      );
      if (newUrl == null) throw Exception('Görsel yüklenemedi.');
      await _write(leagueId, newUrl);
      if (old.isNotEmpty && old != newUrl) {
        await _uploader.deleteImageByUrl(old);
      }
      if (!mounted) return;
      setState(() => _pending = null);
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
    final old = _ownUrl;
    if (leagueId == null || old.isEmpty) return;
    final k = _kind;
    final ok = await showAdminConfirmDialog(
      context: context,
      title: k == null ? 'Ortak Arka Planı Kaldır' : 'Ortak Arka Plana Dön',
      message: k == null
          ? 'Görsel silinecek; özel görseli olmayan afişler varsayılan '
                'stadyum zeminiyle hazırlanacak.'
          : '${k.label} afişinin kendi görseli silinecek; afiş ortak arka '
                'planı kullanacak.',
      confirmLabel: k == null ? 'KALDIR' : 'ORTAĞA DÖN',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await _write(leagueId, null);
      await _uploader.deleteImageByUrl(old);
      if (!mounted) return;
      setState(() {});
      _snack(
        k == null ? 'Ortak arka plan kaldırıldı.' : 'Ortak arka plana dönüldü.',
      );
    } catch (e) {
      if (mounted) _snack('Kaldırılamadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Önizleme: turnuvanın kendi takımlarıyla örnek afiş.
  // ---------------------------------------------------------------------------

  _Team _team(int i) {
    if (_teams.isEmpty) {
      return (name: i.isEven ? 'Ev Sahibi' : 'Deplasman', logo: '');
    }
    return _teams[i % _teams.length];
  }

  List<PosterMatch> _sampleMatches({required bool scores}) {
    const times = ['20.00', '21.15', '22.30', '23.45'];
    const sampleScores = ['3 - 1', '2 - 2', '0 - 1', '4 - 2'];
    final n = (_teams.length ~/ 2).clamp(1, 4);
    return [
      for (var i = 0; i < n; i++)
        PosterMatch(
          homeName: _team(i * 2).name,
          awayName: _team(i * 2 + 1).name,
          homeLogo: _team(i * 2).logo,
          awayLogo: _team(i * 2 + 1).logo,
          time: times[i],
          score: scores ? sampleScores[i] : null,
        ),
    ];
  }

  Widget _samplePoster(LeagueChoice? league, PosterKind kind) {
    final name = league?.name ?? '';
    final logo = league?.logoUrl ?? '';
    switch (kind) {
      case PosterKind.match:
        return MatchPoster(
          leagueName: name,
          leagueLogo: logo,
          groupName: _groupName,
          week: 1,
          homeName: _team(0).name,
          homeLogo: _team(0).logo,
          awayName: _team(1).name,
          awayLogo: _team(1).logo,
          pitchName: 'Saha',
          dayName: 'Cumartesi',
          dateText: '17.10.2026',
          timeText: '21:45',
        );
      case PosterKind.fixture:
      case PosterKind.results:
        final results = kind == PosterKind.results;
        final matches = _sampleMatches(scores: results);
        final half = (matches.length / 2).ceil();
        final title = results ? 'Maç Sonuçları' : 'Fikstür';
        return FixturePoster(
          leagueName: name,
          leagueLogo: logo,
          subtitle: _groupName.isEmpty ? title : '$_groupName $title',
          weekText: results ? '1. Hafta Maç Sonuçları' : '1. Hafta',
          days: [
            PosterDay(
              dateText: '17.10.2026 Cumartesi',
              pitchText: 'Saha',
              matches: matches.sublist(0, half),
            ),
            if (matches.length > half)
              PosterDay(
                dateText: '18.10.2026 Pazar',
                pitchText: 'Saha',
                matches: matches.sublist(half),
              ),
          ],
        );
      case PosterKind.standings:
        final count = _teams.isEmpty ? 2 : _teams.length.clamp(2, 12);
        return StandingsPoster(
          leagueName: name,
          leagueLogo: logo,
          subtitle: _groupName,
          rows: [
            for (var i = 0; i < count; i++)
              StandingEntry(
                teamId: '$i',
                name: _team(i).name,
                logo: _team(i).logo,
              ),
          ],
        );
    }
  }

  Widget _preview(LeagueChoice? league) {
    final pending = _pending;
    final k = _kind ?? PosterKind.match;
    final url = _kind == null
        ? ((_common ?? '').isEmpty ? null : _common)
        : PosterBackgrounds.pick(k, common: _common ?? '', byKind: _byKind);
    final ImageProvider? image = pending != null
        ? pickedImageProvider(pending)
        : (url == null ? null : NetworkImage(url));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: AspectRatio(
          aspectRatio: kPosterSize.width / kPosterSize.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: FittedBox(
              child: SizedBox.fromSize(
                size: kPosterSize,
                child: PosterBackground(
                  image: image,
                  child: _samplePoster(league, k),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Sekmenin durumu: hangi görselin kullanıldığı.
  String _status() {
    final k = _kind;
    final hasCommon = (_common ?? '').isNotEmpty;
    if (_pending != null) {
      return k == null
          ? 'Önizleme: kaydedince özel görseli olmayan afişler bu görseli '
                'kullanır.'
          : 'Önizleme: kaydedince ${k.label} afişi bu görseli kullanır.';
    }
    if (k == null) {
      return hasCommon
          ? 'Özel görseli olmayan afişler bu görselle hazırlanıyor.'
          : 'Ortak arka plan yok; özel görseli olmayan afişler stadyum '
                'fotoğrafıyla hazırlanıyor. Dikey (9:16) görsel en iyi sonucu '
                'verir.';
    }
    if (_ownUrl.isNotEmpty) return '${k.label} afişinin kendi görseli var.';
    if (k == PosterKind.results &&
        (_byKind[PosterKind.fixture.key] ?? '').isNotEmpty) {
      return 'Kendi görseli yok; fikstür afişinin görselini kullanıyor.';
    }
    return hasCommon
        ? 'Kendi görseli yok; ortak arka planı kullanıyor.'
        : 'Kendi görseli yok; stadyum fotoğrafıyla hazırlanıyor.';
  }

  @override
  Widget build(BuildContext context) {
    const title = 'Afiş Arka Planı';
    final session = AppSession.of(context).value;
    if (!session.isAdmin && !session.isLeagueOwner) {
      return const AdminPageScaffold(
        title: title,
        body: Center(
          child: Text(
            'Bu ekrana yalnızca admin ve kurucu başkan erişebilir.',
            style: TextStyle(color: kAdminMuted),
          ),
        ),
      );
    }
    final leagues = _leagues;
    final league = leagues?.where((l) => l.id == _leagueId).firstOrNull;
    final Widget body;
    if (leagues == null || (_leagueId != null && _common == null)) {
      body = const Center(child: CircularProgressIndicator());
    } else if (leagues.isEmpty) {
      body = const Center(
        child: Text('Turnuva yok.', style: TextStyle(color: kAdminMuted)),
      );
    } else {
      const tabs = [null, ...PosterKind.values];
      const labels = ['Ortak', 'Maç', 'Fikstür', 'Sonuç', 'Puan'];
      final hasOwn = _ownUrl.isNotEmpty;
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
          const SizedBox(height: 14),
          AdminFormTabs(
            labels: labels,
            selected: tabs.indexOf(_kind),
            onChanged: _busy
                ? null
                : (i) => setState(() {
                    _kind = tabs[i];
                    _pending = null;
                  }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 16),
            child: Text(
              _status(),
              style: const TextStyle(
                color: kAdminMuted,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
          _preview(league),
          const SizedBox(height: 8),
          const Text(
            'Önizlemede turnuvanın kendi takımları örnek maçlarla gösterilir. '
            'Kadro, esame ve diziliş afişleri takım rengiyle hazırlanır.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kAdminMuted, fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 18),
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
              label: hasOwn ? 'GÖRSELİ DEĞİŞTİR' : 'GÖRSEL YÜKLE',
              icon: Icons.add_photo_alternate_rounded,
              busy: _busy,
              onPressed: _pickImage,
            ),
            if (hasOwn) ...[
              const SizedBox(height: 10),
              AdminSecondaryButton(
                label: _kind == null ? 'KALDIR' : 'ORTAK ARKA PLANI KULLAN',
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
