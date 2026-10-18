import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/panel_scope.dart';
import '../../../core/services/image_upload_service.dart';
import '../services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/team_crest.dart';
import '../../../core/widgets/web_safe_image.dart';
import 'package:football_tournament/core/widgets/picked_image.dart';
import 'team_squad_screen.dart';
import '../../../core/utils/reveal_search.dart';

class AdminManageTeamsScreen extends StatefulWidget {
  const AdminManageTeamsScreen({
    super.key,
    this.initialLeagueId,
    this.lockLeagueSelection = false,
  });

  final String? initialLeagueId;
  final bool lockLeagueSelection;

  @override
  State<AdminManageTeamsScreen> createState() => _AdminManageTeamsScreenState();
}

class _AdminManageTeamsScreenState extends State<AdminManageTeamsScreen> {
  final ITeamService _teamService = ServiceLocator.teamService;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  /// Arama kutusu: sağ alttaki arama düğmesiyle açılır.
  bool _searchOpen = false;
  final _picker = ImagePicker();
  final _imageUploadService = SupabaseImageUploadService();
  Future<List<Map<String, dynamic>>>? _teamsFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Oturum (yetki kapsamı) bağlamdan okunduğu için initState yerine burada.
    _teamsFuture ??= _fetchTeamsOnce();
  }

  /// Takımlar + sorumlu adları + kaç sezonda yer aldıkları (liste kartları
  /// için; toplam 3 sorgu).
  Future<List<Map<String, dynamic>>> _fetchTeamsOnce() async {
    final client = Supabase.instance.client;
    // Kurucu / bölge sorumlusu yalnızca kendi takımlarını görür.
    final allowed = await PanelScope.teamIds(AppSession.of(context).value);
    final res = await client.from('teams').select();
    final teams =
        res
            .map((e) => Map<String, dynamic>.from((e as Map)))
            .where(
              (t) => allowed == null || allowed.contains(t['id'].toString()),
            )
            .toList()
          ..sort(
            (a, b) => _trCompare(
              (a['name'] ?? '').toString(),
              (b['name'] ?? '').toString(),
            ),
          );

    final managerIds = <String>{
      for (final t in teams)
        if ((t['manager_id'] ?? '').toString().trim().isNotEmpty)
          t['manager_id'].toString().trim(),
    };
    final managerNames = <String, String>{};
    final seasonCounts = <String, int>{};
    await Future.wait([
      if (managerIds.isNotEmpty)
        client
            .from('players')
            .select('id, name, surname')
            .inFilter('id', managerIds.toList())
            .then((rows) {
              for (final r in rows) {
                managerNames[(r['id'] ?? '').toString()] = _fullName(r);
              }
            }),
      client.from('season_teams').select('team_id').then((rows) {
        for (final r in rows) {
          final tid = (r['team_id'] ?? '').toString();
          seasonCounts[tid] = (seasonCounts[tid] ?? 0) + 1;
        }
      }),
    ]);

    for (final t in teams) {
      final id = (t['id'] ?? '').toString();
      t['manager_name'] =
          managerNames[(t['manager_id'] ?? '').toString().trim()] ?? '';
      t['season_count'] = seasonCounts[id] ?? 0;
    }
    return teams;
  }

  static String _fullName(Map<String, dynamic> row) => [
    (row['name'] ?? '').toString().trim(),
    (row['surname'] ?? '').toString().trim(),
  ].where((e) => e.isNotEmpty).join(' ');

  /// Arama için küçük harf; i / ı / İ / I eşdeğer sayılır.
  String _toTurkishLow(String input) {
    return input.replaceAll('İ', 'i').toLowerCase().replaceAll('ı', 'i');
  }

  static String _trUpper(String s) =>
      s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

  static const _trAlphabet = 'abcçdefgğhıijklmnoöprsştuüvyz';

  /// Türk alfabesine göre sıralama (Ç, Ğ, İ, Ö, Ş, Ü doğru yerde).
  static int _trCompare(String a, String b) {
    String low(String s) =>
        s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase().trim();
    final x = low(a);
    final y = low(b);
    final n = x.length < y.length ? x.length : y.length;
    for (var i = 0; i < n; i++) {
      if (x[i] == y[i]) continue;
      final ix = _trAlphabet.indexOf(x[i]);
      final iy = _trAlphabet.indexOf(y[i]);
      if (ix >= 0 && iy >= 0) return ix.compareTo(iy);
      if (ix >= 0) return 1; // rakam / sembol önce
      if (iy >= 0) return -1;
      return x[i].compareTo(y[i]);
    }
    return x.length.compareTo(y.length);
  }

  bool _matchesTeamSearch(Map<String, dynamic> data) {
    final q = _searchQuery.trim();
    if (q.isEmpty) return true;
    String read(dynamic v) => (v ?? '').toString();
    return _toTurkishLow(read(data['name'])).contains(q) ||
        _toTurkishLow(read(data['manager_name'])).contains(q);
  }

  String _friendlyLoadError(Object? error) {
    final s = (error ?? '').toString();
    final lower = s.toLowerCase();
    if (lower.contains('permission-denied')) {
      return 'Yetki hatası. Giriş yapıldı mı ve kullanıcı yetkisi doğru mu kontrol edin.\n\n$s';
    }
    if (lower.contains('unavailable') || lower.contains('network')) {
      return 'Bağlantı hatası. İnternet bağlantısını kontrol edin.\n\n$s';
    }
    return s;
  }

  /// Takımın kadro ekranı. Kadro sezona bağlıdır: takım tek sezondaysa
  /// doğrudan açılır; birden fazla sezondaysa üstte sezon yılı, altta o yılın
  /// turnuvaları seçilir (aynı yıl iki turnuvada oynayan takımlar için).
  Future<void> _openSquad(
    BuildContext ctx, {
    required String teamId,
    required String teamName,
    required String logoUrl,
  }) async {
    final sb = Supabase.instance.client;
    List<_SquadSeason> seasons;
    try {
      final links = await sb
          .from('season_teams')
          .select('season_id')
          .eq('team_id', teamId);
      final ids = {for (final r in links) (r['season_id'] ?? '').toString()}
        ..remove('');
      final rows = ids.isEmpty
          ? const <Map<String, dynamic>>[]
          : await sb
                .from('seasons')
                .select('id, name, season_year, start_date, league_id')
                .inFilter('id', ids.toList())
                .order('start_date', ascending: false);
      final leagueIds = {
        for (final r in rows) (r['league_id'] ?? '').toString(),
      }..remove('');
      final leagueNames = <String, String>{};
      if (leagueIds.isNotEmpty) {
        final ls = await sb
            .from('leagues')
            .select('id, name')
            .inFilter('id', leagueIds.toList());
        for (final l in ls) {
          leagueNames[(l['id'] ?? '').toString()] = (l['name'] ?? '')
              .toString()
              .trim();
        }
      }
      seasons = [
        for (final r in rows)
          _SquadSeason(
            id: (r['id'] ?? '').toString(),
            name: (r['name'] ?? '').toString().trim(),
            year:
                (r['season_year'] as num?)?.toInt() ??
                DateTime.tryParse((r['start_date'] ?? '').toString())?.year ??
                0,
            league: leagueNames[(r['league_id'] ?? '').toString()] ?? '',
          ),
      ];
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(SnackBar(content: Text('Sezonlar okunamadı: $e')));
      }
      return;
    }
    if (!ctx.mounted) return;
    if (seasons.isEmpty) {
      await showAdminInfoDialog(
        context: ctx,
        title: 'Kadro',
        message:
            'Takım henüz bir sezona eklenmemiş. Kadro, takım bir sezona '
            'eklendikten sonra düzenlenebilir.',
        icon: Icons.info_outline_rounded,
        iconColor: kAdminAccent,
      );
      return;
    }
    final season = seasons.length == 1
        ? seasons.first
        : await _pickSquadSeason(ctx, teamName: teamName, seasons: seasons);
    if (season == null || !ctx.mounted) return;
    await Navigator.of(ctx).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'TeamSquadScreen'),
        builder: (_) => TeamSquadScreen(
          teamId: teamId,
          tournamentId: season.id,
          teamName: teamName,
          teamLogoUrl: logoUrl,
        ),
      ),
    );
  }

  /// Kadro için sezon seçimi: üstte yıllar (tek seçim), altta seçili yılın
  /// turnuvaları. Turnuvaya dokununca o sezon döner.
  Future<_SquadSeason?> _pickSquadSeason(
    BuildContext ctx, {
    required String teamName,
    required List<_SquadSeason> seasons,
  }) {
    final years = {for (final s in seasons) s.year}.toList()
      ..sort((a, b) => b.compareTo(a));
    var year = years.first;
    return showDialog<_SquadSeason>(
      context: ctx,
      builder: (dctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: AdminDialogCloseOverlay(
          onClose: () => Navigator.pop(dctx),
          child: StatefulBuilder(
            builder: (dctx, setDState) {
              final list = seasons.where((s) => s.year == year).toList()
                ..sort((a, b) => _trCompare(a.league, b.league));
              return Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(dctx).size.height * 0.8,
                ),
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
                decoration: adminDialogDecoration(),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AdminDialogHeader(
                        icon: Icons.groups_outlined,
                        title: 'Kadro',
                        subtitle: teamName,
                      ),
                      AdminFormSection(
                        title: 'Sezonlar',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final y in years)
                              _YearChip(
                                label: y == 0 ? 'Diğer' : '$y',
                                selected: y == year,
                                onTap: () => setDState(() => year = y),
                              ),
                          ],
                        ),
                      ),
                      AdminFormSection(
                        title: 'Turnuvalar',
                        child: AdminFieldGroup(
                          children: [
                            for (final s in list)
                              AdminFieldRow(
                                icon: Icons.emoji_events_outlined,
                                label: s.name,
                                onTap: () => Navigator.pop(dctx, s),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.white54,
                                ),
                                child: Text(
                                  s.league.isEmpty ? s.name : s.league,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Takım sorumlusu seçimi: tüm futbolcular arasından (aramayla).
  Future<Map<String, String>?> _pickManager() async {
    // Controller ve sorgu builder dışında bir kez oluşturulur; klavye
    // açılıp popup yeniden build edildiğinde sıfırlanmaz / tekrar çekilmez.
    final searchController = TextEditingController();
    final future = Supabase.instance.client
        .from('players')
        .select('id, name, surname, photo_url')
        .order('name', ascending: true);
    final picked = await showAdminPopup<Map<String, String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setPickerState) {
            final h = MediaQuery.of(context).size.height * 0.75;
            final q = _toTurkishLow(searchController.text.trim());
            return SizedBox(
              height: h,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AdminDialogHeader(
                      icon: Icons.badge_outlined,
                      title: 'Takım Sorumlusu Seç',
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: searchController,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: kAdminAccent,
                      decoration: adminInputDecoration(
                        hint: 'İsimle ara',
                        icon: Icons.search_rounded,
                      ),
                      onChanged: (_) => setPickerState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: FutureBuilder(
                        future: future,
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: kAdminAccent,
                              ),
                            );
                          }
                          if (snap.hasError) {
                            return Center(
                              child: Text(
                                'Hata: ${snap.error}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            );
                          }
                          final rows =
                              (snap.data as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              const <Map<String, dynamic>>[];
                          final filtered = q.isEmpty
                              ? rows
                              : rows
                                    .where(
                                      (r) => _toTurkishLow(
                                        _fullName(r),
                                      ).contains(q),
                                    )
                                    .toList();
                          if (filtered.isEmpty) {
                            return const Center(
                              child: Text(
                                'Takım sorumlusu bulunamadı.',
                                style: TextStyle(color: Colors.white54),
                              ),
                            );
                          }
                          return ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final r = filtered[index];
                              final id = (r['id'] ?? '').toString().trim();
                              final n = _fullName(r);
                              final photo = (r['photo_url'] ?? '')
                                  .toString()
                                  .trim();
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => Navigator.of(
                                    context,
                                  ).pop({'id': id, 'name': n}),
                                  child: Ink(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.25,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.08,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        ClipOval(
                                          child: Container(
                                            width: 40,
                                            height: 40,
                                            color: Colors.white.withValues(
                                              alpha: 0.08,
                                            ),
                                            child: photo.isEmpty
                                                ? const Icon(
                                                    Icons.person_rounded,
                                                    color: Colors.white54,
                                                  )
                                                : WebSafeImage(
                                                    url: photo,
                                                    width: 40,
                                                    height: 40,
                                                    isCircle: true,
                                                    fit: BoxFit.cover,
                                                    fallbackIconSize: 20,
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                n.isEmpty ? id : n,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          color: Colors.white38,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    _disposeControllersLater([searchController]);
    return picked;
  }

  Future<void> _openTeamFormSheet({
    String? teamId,
    Map<String, dynamic>? existing,
  }) async {
    final isEdit = (teamId ?? '').trim().isNotEmpty && existing != null;
    final nameController = TextEditingController(
      text: (existing?['name'] ?? '').toString().trim(),
    );
    final shortNameController = TextEditingController(
      text: (existing?['short_name'] ?? '').toString().trim(),
    );
    final foundedController = TextEditingController(
      text: (existing?['founded_year'] ?? existing?['foundedYear'] ?? '')
          .toString()
          .trim(),
    );
    final existingLogoUrl =
        (existing?['logo_url'] ?? existing?['logoUrl'] ?? '').toString().trim();
    String selectedManagerId =
        (existing?['manager_id'] ?? existing?['managerId'] ?? '')
            .toString()
            .trim();
    String managerName = (existing?['manager_name'] ?? '').toString().trim();
    String? firstColor = (existing?['first_color'] ?? '').toString().trim();
    String? secondColor = (existing?['second_color'] ?? '').toString().trim();
    if (firstColor.isEmpty) firstColor = null;
    if (secondColor.isEmpty) secondColor = null;
    XFile? selectedLogo;
    var removeLogo = false;
    var saving = false;
    // Açık sekme: 0 Genel, 1 Görünüm.
    var tab = 0;

    Future<void> pickLogo(void Function(void Function()) setSheetState) async {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      if (!mounted) return;
      final logo = await preparePickedLogo(context, picked);
      if (logo == null) return;
      setSheetState(() {
        selectedLogo = logo;
        removeLogo = false;
      });
    }

    Future<void> submit(
      BuildContext sheetContext,
      void Function(void Function()) setSheetState,
    ) async {
      final teamName = nameController.text.trim();
      if (teamName.isEmpty) {
        setSheetState(() => tab = 0);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen takım adını girin.')),
        );
        return;
      }

      setSheetState(() => saving = true);
      try {
        var logoUrl = removeLogo ? '' : existingLogoUrl;
        if (selectedLogo != null) {
          final uploaded = await _imageUploadService.uploadImage(
            selectedLogo!,
            folder: MediaFolder.teams,
          );
          if ((uploaded ?? '').trim().isEmpty) {
            throw Exception('Logo yüklenemedi.');
          }
          logoUrl = uploaded!.trim();
        }

        final foundedRaw = foundedController.text.replaceAll(RegExp(r'\D'), '');
        final foundedYear = foundedRaw.isEmpty ? null : foundedRaw;

        final payload = <String, dynamic>{
          'name': teamName,
          'short_name': shortNameController.text.trim().isEmpty
              ? null
              : shortNameController.text.trim(),
          'logo_url': logoUrl.trim(),
          'manager_id': selectedManagerId.isEmpty ? null : selectedManagerId,
          'founded_year': ?foundedYear,
          'first_color': firstColor,
          'second_color': secondColor,
        };

        Future<void> doUpdateInsert({required bool includeFounded}) async {
          final p = Map<String, dynamic>.from(payload);
          if (!includeFounded) {
            p.remove('founded_year');
          }
          if (isEdit) {
            await Supabase.instance.client
                .from('teams')
                .update(p)
                .eq('id', teamId!);
          } else {
            p['created_at'] = DateTime.now().toIso8601String();
            await Supabase.instance.client.from('teams').insert(p);
          }
        }

        try {
          await doUpdateInsert(includeFounded: true);
        } on PostgrestException catch (e) {
          if (e.code == 'PGRST204') {
            await doUpdateInsert(includeFounded: false);
          } else {
            rethrow;
          }
        }

        if (isEdit &&
            existingLogoUrl.isNotEmpty &&
            logoUrl != existingLogoUrl) {
          await _imageUploadService.deleteImageByUrl(existingLogoUrl);
        }

        // Başarılı kayıtta popup kapanır; kapanmış popup'a setState yapılmaz.
        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        if (!mounted) return;
        setState(() {
          _teamsFuture = _fetchTeamsOnce();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEdit
                  ? 'Güncellendi.'
                  : AppSession.of(context).value.isAdmin
                  ? 'Takım eklendi.'
                  : 'Takım eklendi. Turnuva Yönetimi\'nde bir gruba '
                        'atadığınızda bu listede görünür.',
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
        if (sheetContext.mounted) setSheetState(() => saving = false);
      }
    }

    await showAdminPopup<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final showLogoUrl = selectedLogo == null && !removeLogo
                ? existingLogoUrl
                : '';
            final hasLogo = selectedLogo != null || showLogoUrl.isNotEmpty;

            Future<void> openManagerPicker() async {
              final picked = await _pickManager();
              if (picked == null) return;
              setSheetState(() {
                selectedManagerId = (picked['id'] ?? '').trim();
                managerName = (picked['name'] ?? '').trim();
              });
            }

            final Widget logo;
            if (selectedLogo != null) {
              logo = Image(
                image: pickedImageProvider(selectedLogo!),
                fit: BoxFit.contain,
              );
            } else if (showLogoUrl.isNotEmpty) {
              logo = WebSafeImage(
                url: showLogoUrl,
                width: 112,
                height: 112,
                fit: BoxFit.contain,
                fallbackIconSize: 44,
              );
            } else {
              logo = const Icon(
                Icons.shield_outlined,
                size: 48,
                color: Color(0xFF6EE7B7),
              );
            }

            // Kaydet butonu içerik kaysa da hep görünür; kapatma sağ üstte.
            // Alanlar sekmelere bölünür; form aşağı doğru uzamaz.
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 4, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: AdminFormTabs(
                          labels: const ['Genel', 'Görünüm'],
                          selected: tab,
                          onChanged: saving
                              ? null
                              : (i) => setSheetState(() => tab = i),
                        ),
                      ),
                      AdminDialogCloseButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (tab == 1) ...[
                          Center(
                            child: GestureDetector(
                              onTap: saving
                                  ? null
                                  : () => pickLogo(setSheetState),
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 112,
                                    height: 112,
                                    // Zemin (decoration) yokken kırpma
                                    // yapılamaz; Flutter hata verir.
                                    clipBehavior: hasLogo
                                        ? Clip.none
                                        : Clip.antiAlias,
                                    alignment: Alignment.center,
                                    // Logo varsa zemin yok; logo kendi
                                    // şekliyle görünür.
                                    decoration: hasLogo
                                        ? null
                                        : BoxDecoration(
                                            color: const Color(0xFF064E3B),
                                            borderRadius: BorderRadius.circular(
                                              28,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.12,
                                              ),
                                            ),
                                          ),
                                    child: SizedBox.expand(child: logo),
                                  ),
                                  Positioned(
                                    right: -6,
                                    bottom: -6,
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: kAdminAccent,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFF1E293B),
                                          width: 3,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.photo_camera_outlined,
                                        size: 17,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed: saving
                                    ? null
                                    : () => pickLogo(setSheetState),
                                style: TextButton.styleFrom(
                                  foregroundColor: kAdminAccent,
                                ),
                                child: Text(
                                  hasLogo ? 'Logoyu değiştir' : 'Logo seç',
                                ),
                              ),
                              if (hasLogo)
                                TextButton(
                                  onPressed: saving
                                      ? null
                                      : () => setSheetState(() {
                                          selectedLogo = null;
                                          removeLogo = true;
                                        }),
                                  style: TextButton.styleFrom(
                                    foregroundColor: kAdminDanger,
                                  ),
                                  child: const Text('Kaldır'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (tab == 0)
                          AdminFormSection(
                            title: 'Takım',
                            child: AdminFieldGroup(
                              children: [
                                AdminFieldRow(
                                  icon: Icons.shield_outlined,
                                  label: 'Takım Adı',
                                  child: TextField(
                                    controller: nameController,
                                    enabled: !saving,
                                    maxLength: 30,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    cursorColor: kAdminAccent,
                                    decoration: adminInlineInputDecoration(
                                      hint: 'Örn. Yeşil FK',
                                    ).copyWith(counterText: ''),
                                  ),
                                ),
                                AdminFieldRow(
                                  icon: Icons.short_text_rounded,
                                  label: 'Kısa Ad (opsiyonel)',
                                  child: TextField(
                                    controller: shortNameController,
                                    enabled: !saving,
                                    maxLength: 16,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    cursorColor: kAdminAccent,
                                    decoration: adminInlineInputDecoration(
                                      hint: 'Dar ekranlar için, örn. GOP Autur',
                                    ).copyWith(counterText: ''),
                                  ),
                                ),
                                AdminFieldRow(
                                  icon: Icons.event_outlined,
                                  label: 'Kuruluş Yılı',
                                  child: TextField(
                                    controller: foundedController,
                                    enabled: !saving,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(4),
                                    ],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    cursorColor: kAdminAccent,
                                    decoration: adminInlineInputDecoration(
                                      hint: 'Örn. 1966',
                                    ),
                                  ),
                                ),
                                AdminSelectRow(
                                  icon: Icons.badge_outlined,
                                  label: 'Takım Sorumlusu',
                                  value: managerName,
                                  placeholder: 'Sorumlu seçin',
                                  onTap: saving ? null : openManagerPicker,
                                  onClear: () => setSheetState(() {
                                    selectedManagerId = '';
                                    managerName = '';
                                  }),
                                ),
                                if (isEdit)
                                  AdminSelectRow(
                                    icon: Icons.groups_outlined,
                                    label: 'Kadro',
                                    value: 'Kadroyu aç',
                                    placeholder: 'Kadroyu aç',
                                    onTap: saving
                                        ? null
                                        : () => _openSquad(
                                            context,
                                            teamId: teamId!,
                                            teamName: nameController.text
                                                .trim(),
                                            logoUrl: existingLogoUrl,
                                          ),
                                  ),
                              ],
                            ),
                          ),
                        if (tab == 1)
                          AdminFormSection(
                            title: 'Renkler',
                            child: Row(
                              children: [
                                Expanded(
                                  child: AdminColorTile(
                                    label: 'Ana Renk',
                                    hex: firstColor,
                                    onTap: saving
                                        ? null
                                        : () async {
                                            final c =
                                                await showAdminColorPicker(
                                                  context: context,
                                                  title: 'Ana Renk',
                                                  initial: firstColor,
                                                );
                                            if (c != null) {
                                              setSheetState(
                                                () => firstColor = c,
                                              );
                                            }
                                          },
                                    onClear: () =>
                                        setSheetState(() => firstColor = null),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: AdminColorTile(
                                    label: 'İkinci Renk',
                                    hex: secondColor,
                                    onTap: saving
                                        ? null
                                        : () async {
                                            final c =
                                                await showAdminColorPicker(
                                                  context: context,
                                                  title: 'İkinci Renk',
                                                  initial: secondColor,
                                                );
                                            if (c != null) {
                                              setSheetState(
                                                () => secondColor = c,
                                              );
                                            }
                                          },
                                    onClear: () =>
                                        setSheetState(() => secondColor = null),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: AdminPrimaryButton(
                    label: isEdit ? 'GÜNCELLE' : 'KAYDET',
                    busy: saving,
                    onPressed: () => submit(sheetContext, setSheetState),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    _disposeControllersLater([
      nameController,
      shortNameController,
      foundedController,
    ]);
  }

  /// Popup kapanış animasyonu sürerken TextField'lar controller'ı kullanmaya
  /// devam eder; hemen dispose etmek "_dependents.isEmpty" /
  /// "used after being disposed" hatalarına yol açar.
  void _disposeControllersLater(List<TextEditingController> controllers) {
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      for (final c in controllers) {
        c.dispose();
      }
    });
  }

  /// Satırdaki ⋮ menüsü: ortada açılan, form diliyle aynı işlem listesi.
  Future<void> _openTeamActions(Map<String, dynamic> data) async {
    final teamId = (data['id'] ?? '').toString();
    final teamName = (data['name'] ?? '').toString().trim();
    final logoUrl = (data['logo_url'] ?? '').toString().trim();
    final isAdmin = AppSession.of(context).value.isAdmin;
    final action = await showDialog<String>(
      context: context,
      builder: (dctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: AdminDialogCloseOverlay(
          onClose: () => Navigator.pop(dctx),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
            decoration: adminDialogDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Column(
                    children: [
                      TeamCrest(name: teamName, logoUrl: logoUrl, size: 56),
                      const SizedBox(height: 10),
                      Text(
                        teamName,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AdminFormSection(
                  title: 'İşlemler',
                  child: AdminFieldGroup(
                    children: [
                      _actionRow(
                        dctx,
                        value: 'squad',
                        icon: Icons.groups_outlined,
                        label: 'Kadroyu aç',
                      ),
                      _actionRow(
                        dctx,
                        value: 'edit',
                        icon: Icons.edit_outlined,
                        label: 'Düzenle',
                      ),
                      // Takım silme yalnızca admin.
                      if (isAdmin)
                        _actionRow(
                          dctx,
                          value: 'delete',
                          icon: Icons.delete_outline_rounded,
                          label: 'Takımı sil',
                          danger: true,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'squad':
        await _openSquad(
          context,
          teamId: teamId,
          teamName: teamName,
          logoUrl: logoUrl,
        );
      case 'edit':
        await _openTeamFormSheet(teamId: teamId, existing: data);
      case 'delete':
        await _takimSil(teamId, logoUrl: logoUrl);
    }
  }

  Widget _actionRow(
    BuildContext dctx, {
    required String value,
    required IconData icon,
    required String label,
    bool danger = false,
  }) {
    final color = danger ? kAdminDanger : kAdminAccent;
    return InkWell(
      onTap: () => Navigator.pop(dctx, value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: danger ? kAdminDanger : Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  /// Takım silme yalnızca hiç sezona katılmamış ve maçı olmayan takımlar
  /// için (ör. yanlış açılmış kayıt). Geçmişi olan takım silinirse maçları,
  /// rakiplerin sonuçları ve puan tabloları da giderdi.
  Future<void> _takimSil(String teamId, {String? logoUrl}) async {
    final sb = Supabase.instance.client;
    int seasonCount;
    int matchCount;
    try {
      final r = await Future.wait([
        sb.from('season_teams').select('season_id').eq('team_id', teamId),
        sb
            .from('matches')
            .select('id')
            .or('home_team_id.eq.$teamId,away_team_id.eq.$teamId')
            .limit(1000),
      ]);
      seasonCount = r[0].length;
      matchCount = r[1].length;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kontrol edilemedi: $e')));
      return;
    }
    if (!mounted) return;
    if (seasonCount > 0 || matchCount > 0) {
      final parts = [
        if (seasonCount > 0) '$seasonCount sezonda yer aldı',
        if (matchCount > 0) '$matchCount maçı var',
      ].join(' ve ');
      await showAdminInfoDialog(
        context: context,
        title: 'Takım Silinemez',
        message:
            'Bu takım $parts. Maç geçmişi, rakiplerin sonuçları ve puan '
            'tabloları bozulmasın diye geçmişi olan takımlar silinemez.',
        icon: Icons.block_rounded,
        iconColor: kAdminDanger,
      );
      return;
    }

    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Takımı Sil',
      message:
          'Takımın hiç sezonu ve maçı yok; kalıcı olarak silinecek. '
          'Devam etmek istiyor musunuz?',
    );
    if (!ok) return;

    try {
      await _teamService.deleteTeamCascade(
        teamId,
        caller: 'AdminManageTeamsScreen',
      );
      await _imageUploadService.deleteImageByUrl(logoUrl);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Takım silindi.')));
      setState(() {
        _teamsFuture = _fetchTeamsOnce();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Widget _teamRow(Map<String, dynamic> data, {required bool first}) {
    final teamId = (data['id'] ?? '').toString();
    final teamName = (data['name'] ?? '').toString().trim();
    final logoUrl = (data['logo_url'] ?? '').toString().trim();
    final manager = (data['manager_name'] ?? '').toString().trim();
    final founded = (data['founded_year'] ?? '').toString().trim();
    final seasonCount = (data['season_count'] as int?) ?? 0;
    final sub = [
      manager.isEmpty ? 'Sorumlu atanmadı' : manager,
      if (founded.isNotEmpty) 'Kuruluş $founded',
    ].join(' · ');

    Future<void> openEdit() =>
        _openTeamFormSheet(teamId: teamId, existing: data);

    return InkWell(
      onTap: openEdit,
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        decoration: BoxDecoration(
          border: first
              ? null
              : Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                ),
        ),
        child: Row(
          children: [
            TeamCrest(name: teamName, logoUrl: logoUrl, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    teamName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        manager.isEmpty
                            ? Icons.person_off_outlined
                            : Icons.badge_outlined,
                        size: 13,
                        color: manager.isEmpty ? kAdminAmber : kAdminMuted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: kAdminMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Pill(
              seasonCount == 0 ? 'Sezon yok' : '$seasonCount sezon',
              seasonCount == 0 ? kAdminAmber : kAdminAccent,
            ),
            IconButton(
              tooltip: 'Kadro',
              visualDensity: VisualDensity.compact,
              onPressed: () => _openSquad(
                context,
                teamId: teamId,
                teamName: teamName,
                logoUrl: logoUrl,
              ),
              icon: const Icon(Icons.groups_outlined, color: kAdminAccent),
            ),
            IconButton(
              tooltip: 'İşlemler',
              visualDensity: VisualDensity.compact,
              onPressed: () => _openTeamActions(data),
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _letterSection(String letter, List<Map<String, dynamic>> teams) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    letter,
                    style: const TextStyle(
                      color: kAdminAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Text(
                  '${teams.length} takım',
                  style: const TextStyle(color: kAdminMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  for (var i = 0; i < teams.length; i++)
                    _teamRow(teams[i], first: i == 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppSession.of(context).value.hasManagementPanel) {
      return const AdminPageScaffold(
        title: 'Takım Yönetimi',
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
      title: 'Takım Yönetimi',
      actions: [
        if (!_searchOpen)
          AdminBarAction(
            icon: Icons.search_rounded,
            tooltip: 'Takım ara',
            onPressed: () {
              setState(() => _searchOpen = true);
              revealSearchField(_searchFocus);
            },
          ),
        AdminBarAction(
          icon: Icons.group_add_rounded,
          tooltip: 'Takım Ekle',
          onPressed: () => _openTeamFormSheet(),
        ),
      ],
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _teamsFuture,
        builder: (context, snapshot) {
          Future<void> refresh() async {
            setState(() {
              _teamsFuture = _fetchTeamsOnce();
            });
            await _teamsFuture;
          }

          Widget buildMessage(String text) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 120),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54),
                ),
              ],
            );
          }

          final all = (snapshot.data ?? const <Map<String, dynamic>>[])
              .where((d) => (d['id'] ?? '').toString() != 'free_agent_pool')
              .toList();
          final teams = all.where(_matchesTeamSearch).toList();
          final noManager = all
              .where((d) => (d['manager_name'] ?? '').toString().isEmpty)
              .length;

          final Widget content;
          if (snapshot.connectionState == ConnectionState.waiting) {
            content = const Center(
              child: CircularProgressIndicator(color: kAdminAccent),
            );
          } else if (snapshot.hasError) {
            content = RefreshIndicator(
              onRefresh: refresh,
              child: buildMessage(
                'Takımlar yüklenemedi.\n\n${_friendlyLoadError(snapshot.error)}',
              ),
            );
          } else if (teams.isEmpty) {
            content = RefreshIndicator(
              onRefresh: refresh,
              child: buildMessage(
                all.isEmpty
                    ? 'Henüz takım yok.'
                    : 'Aramayla eşleşen takım yok.',
              ),
            );
          } else {
            // Baş harfe göre bölümler.
            final sections = <String, List<Map<String, dynamic>>>{};
            for (final t in teams) {
              final name = (t['name'] ?? '').toString().trim();
              final letter = name.isEmpty
                  ? '#'
                  : _trUpper(name.characters.first);
              sections.putIfAbsent(letter, () => []).add(t);
            }
            content = RefreshIndicator(
              onRefresh: refresh,
              color: kAdminAccent,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  kAdminFabClearance + kAdminFabStep,
                ),
                children: [
                  for (final e in sections.entries)
                    _letterSection(e.key, e.value),
                ],
              ),
            );
          }

          return Column(
            children: [
              if (_searchOpen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: kAdminAccent,
                    decoration:
                        adminInputDecoration(
                          hint: 'Takım veya sorumlu ara',
                          icon: Icons.search_rounded,
                        ).copyWith(
                          // Kapatınca arama da temizlenir.
                          suffixIcon: IconButton(
                            tooltip: 'Aramayı kapat',
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white54,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              _searchFocus.unfocus();
                              setState(() {
                                _searchQuery = '';
                                _searchOpen = false;
                              });
                            },
                          ),
                        ),
                    onChanged: (val) =>
                        setState(() => _searchQuery = _toTurkishLow(val)),
                  ),
                ),
              if (snapshot.hasData)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SummaryBox(
                          value: '${all.length}',
                          label: 'Toplam takım',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SummaryBox(
                          value: '${all.length - noManager}',
                          label: 'Sorumlusu olan',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SummaryBox(
                          value: '$noManager',
                          label: 'Sorumlu yok',
                          color: noManager == 0 ? null : kAdminAmber,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }
}

/// Takım logosu; yoksa baş harfler (Sezon / Grup listeleriyle aynı).
/// Kadro seçiminde bir sezon: yılı ve bağlı olduğu turnuvanın adı.
class _SquadSeason {
  const _SquadSeason({
    required this.id,
    required this.name,
    required this.year,
    required this.league,
  });

  final String id;
  final String name;
  final int year;
  final String league;
}

/// Tek seçimli yıl kapsülü.
class _YearChip extends StatelessWidget {
  const _YearChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? kAdminAccent.withValues(alpha: 0.18)
          : const Color(0xFF1E293B).withValues(alpha: 0.94),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: selected ? kAdminAccent : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? kAdminAccent : Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Liste üstündeki küçük sayı kutusu.
class _SummaryBox extends StatelessWidget {
  const _SummaryBox({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color ?? Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: kAdminMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class ArchiveDecoder {
  ArchiveDecoder(this.bytes);
  final List<int> bytes;

  Future<String?> findFirstCsv() async {
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) return null;
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? best;
    int bestScore = -1;
    for (final f in archive) {
      if (!f.isFile) continue;
      final name = f.name.toLowerCase();
      if (!name.endsWith('.csv')) continue;
      var score = 0;
      if (name.contains('preview')) score += 3;
      if (name.contains('export')) score += 2;
      if (name.contains('sheet')) score += 1;
      if (score > bestScore) {
        best = f;
        bestScore = score;
      } else if (score == bestScore && best != null) {
        if (f.size > 0 && f.size < best.size) best = f;
      }
    }
    if (best == null) return null;
    final content = best.content;
    if (content is! List<int>) return null;
    var decoded = utf8.decode(content, allowMalformed: true);
    if (decoded.isNotEmpty && decoded.codeUnitAt(0) == 0xFEFF) {
      decoded = decoded.substring(1);
    }
    return decoded;
  }
}

class EditTeamScreen extends StatefulWidget {
  final String teamId;
  final Map<String, dynamic> data;
  const EditTeamScreen({super.key, required this.teamId, required this.data});

  @override
  State<EditTeamScreen> createState() => _EditTeamScreenState();
}

class _EditTeamScreenState extends State<EditTeamScreen> {
  late TextEditingController _nameController;
  late TextEditingController _foundedController;
  late TextEditingController _managerController;
  XFile? _newLogo;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.data['name']);
    _foundedController = TextEditingController(
      text: (widget.data['foundedYear'] ?? widget.data['founded'] ?? '')
          .toString()
          .trim(),
    );
    _managerController = TextEditingController(
      text: (widget.data['managerName'] ?? widget.data['manager'] ?? '')
          .toString()
          .trim(),
    );
  }

  Future<void> _update() async {
    setState(() => _isLoading = true);
    try {
      String logoUrl =
          (widget.data['logoUrl'] ??
                  widget.data['logo_url'] ??
                  widget.data['logo'] ??
                  '')
              .toString();
      if (_newLogo != null) {
        final uploaded = await SupabaseImageUploadService().uploadImage(
          _newLogo!,
          folder: MediaFolder.teams,
        );
        if (uploaded != null) {
          logoUrl = uploaded;
        } else {
          throw Exception('Logo yüklenemedi.');
        }
      }

      await ServiceLocator.teamService.updateTeam(widget.teamId, {
        'name': _nameController.text.trim(),
        'logoUrl': logoUrl,
        'foundedYear': _foundedController.text.trim(),
        'managerName': _managerController.text.trim(),
      }, caller: 'EditTeamScreen');
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    if (!mounted) return;
    final logo = await preparePickedLogo(context, picked);
    if (logo == null) return;
    if (mounted) setState(() => _newLogo = logo);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentLogoUrl =
        (widget.data['logoUrl'] ??
                widget.data['logo_url'] ??
                widget.data['logo'] ??
                '')
            .toString();

    return Scaffold(
      appBar: AppBar(title: const Text('Takımı Düzenle')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      children: [
                        Center(
                          child: Stack(
                            children: [
                              if (_newLogo != null)
                                CircleAvatar(
                                  radius: 64,
                                  backgroundColor: cs.primary.withValues(
                                    alpha: 0.10,
                                  ),
                                  backgroundImage: pickedImageProvider(
                                    _newLogo!,
                                  ),
                                )
                              else if (currentLogoUrl.isNotEmpty)
                                SizedBox(
                                  width: 128,
                                  height: 128,
                                  child: WebSafeImage(
                                    url: currentLogoUrl,
                                    width: 128,
                                    height: 128,
                                    fit: BoxFit.contain,
                                    fallbackIconSize: 46,
                                  ),
                                )
                              else
                                CircleAvatar(
                                  radius: 64,
                                  backgroundColor: cs.primary.withValues(
                                    alpha: 0.10,
                                  ),
                                  child: Icon(
                                    Icons.shield,
                                    size: 46,
                                    color: Colors.grey,
                                  ),
                                ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: CircleAvatar(
                                  backgroundColor: cs.primary,
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                    ),
                                    onPressed: _pickLogo,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Takım Adı',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _foundedController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Kuruluş Tarihi',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _managerController,
                          decoration: const InputDecoration(
                            labelText: 'Takım Sorumlusu',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _update,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('GÜNCELLE'),
                ),
              ],
            ),
    );
  }
}
