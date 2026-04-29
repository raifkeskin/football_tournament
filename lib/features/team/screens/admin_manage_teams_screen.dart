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
  final _picker = ImagePicker();
  final _imageUploadService = ImgBBUploadService();
  Future<List<Map<String, dynamic>>>? _teamsFuture;

  @override
  void initState() {
    super.initState();
    _teamsFuture = _fetchTeamsOnce();
  }

  Future<List<Map<String, dynamic>>> _fetchTeamsOnce() async {
    final res = await Supabase.instance.client
        .from('teams')
        .select()
        .order('name', ascending: true);
    return res.map((e) => Map<String, dynamic>.from((e as Map))).toList();
  }

  /// Türkçe karakter duyarlı küçük harfe çevirme (Arama için)
  String _toTurkishLow(String input) {
    return input.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  }

  bool _matchesTeamSearch(Map<String, dynamic> data) {
    final q = _searchQuery.trim();
    if (q.isEmpty) return true;
    String read(dynamic v) => (v ?? '').toString();
    final name = read(data['name']);
    return _toTurkishLow(name).contains(q);
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

  Future<void> _openTeamFormSheet({
    String? teamId,
    Map<String, dynamic>? existing,
  }) async {
    final isEdit = (teamId ?? '').trim().isNotEmpty && existing != null;
    final nameController =
        TextEditingController(text: (existing?['name'] ?? '').toString().trim());
    final foundedController = TextEditingController(
      text: (existing?['founded_year'] ?? existing?['foundedYear'] ?? '')
          .toString()
          .trim(),
    );
    final managerController = TextEditingController();
    final existingLogoUrl = (existing?['logo_url'] ?? existing?['logoUrl'] ?? '')
        .toString()
        .trim();
    String? selectedManagerId =
        (existing?['manager_id'] ?? existing?['managerId'] ?? '').toString().trim();
    XFile? selectedLogo;
    var saving = false;

    Future<void> hydrateManagerName() async {
      final mid = (selectedManagerId ?? '').trim();
      if (mid.isEmpty) return;
      try {
        final res = await Supabase.instance.client
            .from('players')
            .select('name')
            .eq('id', mid)
            .limit(1);
        if (res.isNotEmpty) {
          final row = (res.first as Map).cast<String, dynamic>();
          final n = (row['name'] ?? '').toString().trim();
          if (n.isNotEmpty) managerController.text = n;
        }
      } catch (_) {}
    }

    await hydrateManagerName();

    Future<Map<String, dynamic>?> pickManager() async {
      final picked = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        showDragHandle: true,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          final viewInsets = MediaQuery.of(context).viewInsets;
          final h = MediaQuery.of(context).size.height * 0.8;
          final searchController = TextEditingController();
          return StatefulBuilder(
            builder: (context, setPickerState) {
              final q = _toTurkishLow(searchController.text.trim());
              final future = Supabase.instance.client
                  .from('players')
                  .select('id, name, role, photo_url')
                  .inFilter('role', const ['Takım Sorumlusu', 'Her İkisi'])
                  .order('name', ascending: true);
              return SizedBox(
                height: h,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    16 + viewInsets.bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: searchController,
                        decoration: const InputDecoration(
                          labelText: 'Oyuncu Ara',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setPickerState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: FutureBuilder(
                          future: future,
                          builder: (context, snap) {
                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (snap.hasError) {
                              return Center(
                                child: Text('Hata: ${snap.error}'),
                              );
                            }
                            final rows = (snap.data as List?)
                                    ?.cast<Map<String, dynamic>>() ??
                                const <Map<String, dynamic>>[];
                            final filtered = q.isEmpty
                                ? rows
                                : rows.where((r) {
                                    final name =
                                        _toTurkishLow((r['name'] ?? '').toString());
                                    return name.contains(q);
                                  }).toList();
                            if (filtered.isEmpty) {
                              return const Center(
                                child: Text('Oyuncu bulunamadı.'),
                              );
                            }
                            return ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final r = filtered[index];
                                final id = (r['id'] ?? '').toString().trim();
                                final n = (r['name'] ?? '').toString().trim();
                                final role =
                                    (r['role'] ?? '').toString().trim();
                                final photo =
                                    (r['photo_url'] ?? '').toString().trim();
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    leading: SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: ClipOval(
                                        child: photo.isEmpty
                                            ? Container(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                                child: const Icon(
                                                  Icons.person_outline,
                                                  size: 18,
                                                ),
                                              )
                                            : WebSafeImage(
                                                url: photo,
                                                width: 36,
                                                height: 36,
                                                isCircle: true,
                                                fit: BoxFit.cover,
                                                fallbackIconSize: 18,
                                              ),
                                      ),
                                    ),
                                    title: Text(
                                      n.isEmpty ? id : n,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: role.isEmpty ? null : Text(role),
                                    onTap: () => Navigator.of(context).pop({
                                      'id': id,
                                      'name': n,
                                    }),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            'VAZGEÇ',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
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
      return picked;
    }

    Future<void> pickLogo(void Function(void Function()) setSheetState) async {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null) return;
      setSheetState(() => selectedLogo = picked);
    }

    Future<void> submit(void Function(void Function()) setSheetState) async {
      final teamName = nameController.text.trim();
      if (teamName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen takım adını girin.')),
        );
        return;
      }

      setSheetState(() => saving = true);
      try {
        var logoUrl = existingLogoUrl;
        if (selectedLogo != null) {
          final uploaded =
              await _imageUploadService.uploadImage(File(selectedLogo!.path));
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
          'manager_id': (selectedManagerId ?? '').trim().isEmpty
              ? null
              : selectedManagerId!.trim(),
          'updated_at': DateTime.now().toIso8601String(),
          if (foundedYear != null) 'founded_year': foundedYear,
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

        if (!mounted) return;
        setState(() => _teamsFuture = _fetchTeamsOnce());
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEdit ? 'Güncellendi.' : 'Takım eklendi.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      } finally {
        if (mounted) setSheetState(() => saving = false);
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      showDragHandle: true,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets;
        final h = MediaQuery.of(context).size.height * 0.8;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final showLogoUrl = selectedLogo == null ? existingLogoUrl : '';
            return SizedBox(
              height: h,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  16 + viewInsets.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        width: double.infinity,
                        height: 220,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: selectedLogo != null
                                  ? Image.file(
                                      File(selectedLogo!.path),
                                      fit: BoxFit.cover,
                                    )
                                  : (showLogoUrl.isNotEmpty
                                      ? WebSafeImage(
                                          url: showLogoUrl,
                                          width: double.infinity,
                                          height: 220,
                                          isCircle: false,
                                          fit: BoxFit.cover,
                                          fallbackIconSize: 64,
                                        )
                                      : Container(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                          child: Icon(
                                            Icons.shield_outlined,
                                            size: 64,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        )),
                            ),
                            Positioned(
                              right: 10,
                              bottom: 10,
                              child: Row(
                                children: [
                                  IconButton.filledTonal(
                                    onPressed: saving
                                        ? null
                                        : () => pickLogo(setSheetState),
                                    icon: const Icon(
                                      Icons.photo_camera_outlined,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.filledTonal(
                                    onPressed: saving
                                        ? null
                                        : () => setSheetState(() {
                                              selectedLogo = null;
                                            }),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nameController,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Takım Adı',
                        border: OutlineInputBorder(),
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
                      decoration: const InputDecoration(
                        labelText: 'Kuruluş Tarihi',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: managerController,
                            enabled: false,
                            decoration: const InputDecoration(
                              labelText: 'Takım Sorumlusu',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filledTonal(
                          onPressed: saving
                              ? null
                              : () async {
                                  final picked = await pickManager();
                                  if (picked == null) return;
                                  setSheetState(() {
                                    selectedManagerId =
                                        (picked['id'] ?? '').toString().trim();
                                    managerController.text =
                                        (picked['name'] ?? '').toString().trim();
                                  });
                                },
                          icon: const Icon(Icons.search_rounded),
                          tooltip: 'Seç',
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed:
                            saving ? null : () => submit(setSheetState),
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                isEdit ? 'GÜNCELLE' : 'KAYDET',
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed:
                            saving ? null : () => Navigator.of(context).pop(),
                        child: const Text(
                          'VAZGEÇ',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
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

    nameController.dispose();
    foundedController.dispose();
    managerController.dispose();
  }

  Future<void> _takimSil(String teamId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Takım Sil'),
        content: const Text(
          'Takım ve ilişkili veriler silinecektir. Devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hayır'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Evet'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _teamService.deleteTeamCascade(
        teamId,
        caller: 'AdminManageTeamsScreen',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Takım silindi.')));
      setState(() => _teamsFuture = _fetchTeamsOnce());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Takım Yönetimi')),
        body: const Center(
          child: Text(
            'Bu sayfaya erişim yetkiniz yok.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Takımların Listesi'),
        actions: [
          IconButton(
            onPressed: () => _openTeamFormSheet(),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Takım Ekle',
          ),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Takım Ara',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) =>
                  setState(() => _searchQuery = _toTurkishLow(val)),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _teamsFuture,
              builder: (context, snapshot) {
                Future<void> refresh() async {
                  setState(() => _teamsFuture = _fetchTeamsOnce());
                  await _teamsFuture;
                }

                Widget buildMessage(String text) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      const SizedBox(height: 120),
                      Text(text, textAlign: TextAlign.center),
                    ],
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return RefreshIndicator(
                    onRefresh: refresh,
                    child: buildMessage('Takımlar yükleniyor...'),
                  );
                }
                if (snapshot.hasError) {
                  return RefreshIndicator(
                    onRefresh: refresh,
                    child: buildMessage(
                      'Takımlar yüklenemedi.\n\n${_friendlyLoadError(snapshot.error)}',
                    ),
                  );
                }

                final teams = (snapshot.data ?? const <Map<String, dynamic>>[])
                    .where((data) {
                      final id = (data['id'] ?? '').toString().trim();
                      if (id == 'free_agent_pool') return false;
                      return _matchesTeamSearch(data);
                    })
                    .toList();

                if (teams.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: refresh,
                    child: buildMessage('Takım bulunamadı.'),
                  );
                }

                return RefreshIndicator(
                  onRefresh: refresh,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    itemCount: teams.length,
                    itemBuilder: (context, index) {
                      final data = teams[index];
                      final teamId = (data['id'] ?? '').toString();
                      final teamName = (data['name'] ?? '').toString();
                      final logoUrl = (data['logo_url'] ?? '').toString();

                      Future<void> openEditDialog() async {
                        await _openTeamFormSheet(teamId: teamId, existing: data);
                      }

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          leading: SizedBox(
                            width: 36,
                            height: 36,
                            child: WebSafeImage(
                              url: logoUrl,
                              width: 36,
                              height: 36,
                              borderRadius: BorderRadius.circular(8),
                              fallbackIconSize: 18,
                            ),
                          ),
                          title: Text(
                            teamName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                          ),
                          trailing: PopupMenuButton<String>(
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Düzenle'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Sil'),
                              ),
                            ],
                            onSelected: (value) {
                              switch (value) {
                                case 'edit':
                                  openEditDialog();
                                  break;
                                case 'delete':
                                  _takimSil(teamId).then((_) {
                                    if (!mounted) return;
                                    setState(
                                      () => _teamsFuture = _fetchTeamsOnce(),
                                    );
                                  });
                                  break;
                              }
                            },
                          ),
                          onTap: openEditDialog,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
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
        final uploaded = await ImgBBUploadService().uploadImage(
          File(_newLogo!.path),
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
      setState(() => _isLoading = false);
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
