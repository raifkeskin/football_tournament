import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/image_upload_service.dart';
import '../services/interfaces/i_team_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/admin_form.dart';
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/web_safe_image.dart';

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
  final _picker = ImagePicker();
  final _imageUploadService = SupabaseImageUploadService();
  Future<List<Map<String, dynamic>>>? _teamsFuture;

  @override
  void initState() {
    super.initState();
    _teamsFuture = _fetchTeamsOnce();
  }

  /// Takımlar + sorumlu adları + kaç sezonda yer aldıkları (liste kartları
  /// için; toplam 3 sorgu).
  Future<List<Map<String, dynamic>>> _fetchTeamsOnce() async {
    final client = Supabase.instance.client;
    final res = await client.from('teams').select();
    final teams = res.map((e) => Map<String, dynamic>.from((e as Map))).toList()
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

  /// Takım sorumlusu seçimi (Takım Sorumlusu / Her İkisi rolündekiler).
  Future<Map<String, String>?> _pickManager() async {
    // Controller ve sorgu builder dışında bir kez oluşturulur; klavye
    // açılıp popup yeniden build edildiğinde sıfırlanmaz / tekrar çekilmez.
    final searchController = TextEditingController();
    final future = Supabase.instance.client
        .from('players')
        .select('id, name, surname, role, photo_url')
        .inFilter('role', const ['Takım Sorumlusu', 'Her İkisi'])
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
                              final role = (r['role'] ?? '').toString().trim();
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
                                              if (role.isNotEmpty)
                                                Text(
                                                  role,
                                                  style: const TextStyle(
                                                    color: kAdminMuted,
                                                    fontSize: 12,
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
    XFile? selectedLogo;
    var removeLogo = false;
    var saving = false;

    Future<void> pickLogo(void Function(void Function()) setSheetState) async {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null) return;
      setSheetState(() {
        selectedLogo = picked;
        removeLogo = false;
      });
    }

    Future<void> submit(
      BuildContext sheetContext,
      void Function(void Function()) setSheetState,
    ) async {
      final teamName = nameController.text.trim();
      if (teamName.isEmpty) {
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
            File(selectedLogo!.path),
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
          'logo_url': logoUrl.trim(),
          'manager_id': selectedManagerId.isEmpty ? null : selectedManagerId,
          'founded_year': ?foundedYear,
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

        if (isEdit && existingLogoUrl.isNotEmpty && logoUrl != existingLogoUrl) {
          await _imageUploadService.deleteImageByUrl(existingLogoUrl);
        }

        // Başarılı kayıtta popup kapanır; kapanmış popup'a setState yapılmaz.
        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        if (!mounted) return;
        setState(() {
          _teamsFuture = _fetchTeamsOnce();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEdit ? 'Güncellendi.' : 'Takım eklendi.')),
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
              logo = Image.file(File(selectedLogo!.path), fit: BoxFit.cover);
            } else if (showLogoUrl.isNotEmpty) {
              logo = WebSafeImage(
                url: showLogoUrl,
                width: 112,
                height: 112,
                fit: BoxFit.cover,
                fallbackIconSize: 44,
              );
            } else {
              logo = const Icon(
                Icons.shield_outlined,
                size: 48,
                color: Color(0xFF6EE7B7),
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdminDialogHeader(
                    icon: isEdit ? Icons.edit_outlined : Icons.group_add_rounded,
                    title: isEdit ? 'Takımı Düzenle' : 'Takım Ekle',
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: GestureDetector(
                      onTap: saving ? null : () => pickLogo(setSheetState),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 112,
                            height: 112,
                            clipBehavior: Clip.antiAlias,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF064E3B),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black38,
                                  blurRadius: 14,
                                  offset: Offset(0, 6),
                                ),
                              ],
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
                        child: Text(hasLogo ? 'Logoyu değiştir' : 'Logo seç'),
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
                  TextField(
                    controller: nameController,
                    enabled: !saving,
                    maxLength: 30,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    cursorColor: kAdminAccent,
                    decoration: adminInputDecoration(
                      label: 'Takım Adı',
                      icon: Icons.shield_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: foundedController,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    style: const TextStyle(color: Colors.white),
                    cursorColor: kAdminAccent,
                    decoration: adminInputDecoration(
                      label: 'Kuruluş Yılı',
                      hint: 'Örn. 1966',
                      icon: Icons.event_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AdminFieldGroup(
                    children: [
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
                    ],
                  ),
                  const SizedBox(height: 24),
                  AdminPrimaryButton(
                    label: isEdit ? 'GÜNCELLE' : 'KAYDET',
                    busy: saving,
                    onPressed: () => submit(sheetContext, setSheetState),
                  ),
                  const SizedBox(height: 10),
                  AdminSecondaryButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    _disposeControllersLater([nameController, foundedController]);
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

  Future<void> _takimSil(String teamId, {String? logoUrl}) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Takımı Sil',
      message:
          'Takım ve ilişkili veriler silinecektir. Devam etmek istiyor musunuz?',
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
            _TeamLogo(name: teamName, logoUrl: logoUrl),
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
            PopupMenuButton<String>(
              tooltip: 'İşlemler',
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white54),
              onSelected: (v) {
                if (v == 'edit') openEdit();
                if (v == 'delete') _takimSil(teamId, logoUrl: logoUrl);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
                      SizedBox(width: 10),
                      Text('Düzenle', style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        color: kAdminDanger,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Text('Sil', style: TextStyle(color: kAdminDanger)),
                    ],
                  ),
                ),
              ],
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
                      fontWeight: FontWeight.w900,
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    if (!isAdmin) {
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
                all.isEmpty ? 'Henüz takım yok.' : 'Aramayla eşleşen takım yok.',
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
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  for (final e in sections.entries)
                    _letterSection(e.key, e.value),
                ],
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: kAdminAccent,
                  decoration: adminInputDecoration(
                    hint: 'Takım veya sorumlu ara',
                    icon: Icons.search_rounded,
                  ).copyWith(
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(
                              Icons.clear_rounded,
                              color: Colors.white54,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
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
class _TeamLogo extends StatelessWidget {
  const _TeamLogo({required this.name, required this.logoUrl});

  final String name;
  final String logoUrl;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.characters.first)
        .join()
        .toUpperCase();
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF064E3B),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: logoUrl.isNotEmpty
          ? WebSafeImage(url: logoUrl, width: 44, height: 44)
          : Text(
              initials,
              style: const TextStyle(
                color: Color(0xFF6EE7B7),
                fontSize: 15,
                fontWeight: FontWeight.w800,
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
          File(_newLogo!.path),
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
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) setState(() => _newLogo = picked);
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
                                  backgroundImage: FileImage(
                                    File(_newLogo!.path),
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
                                    isCircle: true,
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
