import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/league.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/image_upload_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/widgets/web_safe_image.dart';
import 'season_management_screen.dart';

class AdminManageLeaguesScreen extends StatefulWidget {
  const AdminManageLeaguesScreen({super.key});

  @override
  State<AdminManageLeaguesScreen> createState() =>
      _AdminManageLeaguesScreenState();
}

class _AdminManageLeaguesScreenState extends State<AdminManageLeaguesScreen> {
  final _picker = ImagePicker();

  SupabaseClient get _sb => Supabase.instance.client;

  Future<String> _uploadLeagueLogo({
    required XFile file,
  }) async {
    final uploaded = await ImgBBUploadService().uploadImage(File(file.path));
    final url = (uploaded ?? '').trim();
    if (url.isEmpty) {
      throw Exception('Logo yüklenemedi, lütfen tekrar deneyin.');
    }
    return url;
  }

  Stream<List<League>> _watchActiveLeagues() {
    return _sb
        .from('leagues')
        .stream(primaryKey: ['id'])
        .eq('is_active', true)
        .order('name', ascending: true)
        .map((rows) {
          final list = rows
              .cast<Map<String, dynamic>>()
              .map((r) => League.fromJson(r))
              .toList();
          list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          return list;
        });
  }

  Future<void> _createLeagueDialog() async {
    final nameController = TextEditingController();
    final accessCodeController = TextEditingController();
    var isPrivate = false;
    var saving = false;
    XFile? selectedLogo;

    String newAccessCode() {
      final n = 100000 + Random().nextInt(900000);
      return n.toString();
    }

    Future<void> submit(void Function(void Function()) setSheetState) async {
      final name = nameController.text.trim();
      final access = accessCodeController.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turnuva adı zorunludur.')),
        );
        return;
      }
      if (isPrivate && access.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gizli turnuva için erişim kodu zorunludur.')),
        );
        return;
      }

      setSheetState(() => saving = true);
      try {
        final payload = <String, dynamic>{
          'name': name,
          'is_private': isPrivate,
          'access_code': isPrivate ? access : null,
          'is_active': true,
        };
        final inserted = await _sb
            .from('leagues')
            .insert(payload)
            .select('id')
            .single();
        final leagueId = (inserted['id'] as String?) ?? '';

        if (selectedLogo != null && leagueId.trim().isNotEmpty) {
          final url = await _uploadLeagueLogo(
            file: selectedLogo!,
          );
          await _sb.from('leagues').update({'logo_url': url}).eq('id', leagueId);
        }
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turnuva oluşturuldu.')),
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
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final h = MediaQuery.of(context).size.height * 0.8;
        final viewInsets = MediaQuery.of(context).viewInsets;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SizedBox(
              height: h,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  16 + viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Yeni Turnuva Oluştur',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: SizedBox(
                          width: 148,
                          height: 148,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ClipOval(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                    ),
                                    child: selectedLogo != null
                                        ? Image.file(
                                            File(selectedLogo!.path),
                                            fit: BoxFit.cover,
                                          )
                                        : Icon(
                                            Icons.add_photo_alternate_outlined,
                                            size: 44,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 6,
                                bottom: 6,
                                child: Row(
                                  children: [
                                    IconButton.filledTonal(
                                      onPressed: saving
                                          ? null
                                          : () async {
                                              final picked =
                                                  await _picker.pickImage(
                                                source: ImageSource.gallery,
                                                imageQuality: 85,
                                              );
                                              if (picked == null) return;
                                              setSheetState(() {
                                                selectedLogo = picked;
                                              });
                                            },
                                      icon: const Icon(
                                        Icons.photo_library_outlined,
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
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Turnuva Adı',
                          border: OutlineInputBorder(),
                        ),
                        enabled: !saving,
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Gizli Turnuva'),
                        value: isPrivate,
                        onChanged: saving
                            ? null
                            : (v) {
                                setSheetState(() {
                                  isPrivate = v;
                                  if (isPrivate &&
                                      accessCodeController.text
                                          .trim()
                                          .isEmpty) {
                                    accessCodeController.text = newAccessCode();
                                  }
                                  if (!isPrivate) accessCodeController.clear();
                                });
                              },
                      ),
                      if (isPrivate) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: accessCodeController,
                          decoration: const InputDecoration(
                            labelText: 'Erişim Kodu',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !saving,
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: saving ? null : () => submit(setSheetState),
                          child: saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'KAYDET',
                                  style: TextStyle(fontWeight: FontWeight.w900),
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
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    accessCodeController.dispose();
  }

  Future<void> _editLeagueDialog(League league) async {
    final nameController = TextEditingController(text: league.name);
    final accessCodeController =
        TextEditingController(text: (league.accessCode ?? '').trim());
    final existingUrlInitial = league.logoUrl.trim();
    XFile? selectedLogo;
    var removedLogo = false;
    var saving = false;
    var isPrivate = league.isPrivate;

    String newAccessCode() {
      final n = 100000 + Random().nextInt(900000);
      return n.toString();
    }

    Future<void> submit(void Function(void Function()) setSheetState) async {
      final name = nameController.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turnuva adı zorunludur.')),
        );
        return;
      }
      final access = accessCodeController.text.trim();
      if (isPrivate && access.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gizli turnuva için erişim kodu zorunludur.')),
        );
        return;
      }

      setSheetState(() => saving = true);
      try {
        final update = <String, dynamic>{'name': name};
        if (removedLogo) update['logo_url'] = null;
        update['is_private'] = isPrivate;
        update['access_code'] = isPrivate ? access : null;

        await _sb.from('leagues').update(update).eq('id', league.id);

        if (!removedLogo && selectedLogo != null) {
          final url = await _uploadLeagueLogo(
            file: selectedLogo!,
          );
          await _sb.from('leagues').update({'logo_url': url}).eq('id', league.id);
        }
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Güncellendi.')),
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
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final h = MediaQuery.of(context).size.height * 0.8;
        final viewInsets = MediaQuery.of(context).viewInsets;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final showUrl = removedLogo
                ? ''
                : (selectedLogo == null ? existingUrlInitial : '');
            return SizedBox(
              height: h,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  16 + viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Turnuvayı Düzenle',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: SizedBox(
                          width: 148,
                          height: 148,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ClipOval(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                    ),
                                    child: selectedLogo != null
                                        ? Image.file(
                                            File(selectedLogo!.path),
                                            fit: BoxFit.cover,
                                          )
                                        : (showUrl.isNotEmpty
                                            ? WebSafeImage(
                                                url: showUrl,
                                                width: 148,
                                                height: 148,
                                                fit: BoxFit.cover,
                                              )
                                            : Icon(
                                                Icons.business,
                                                size: 44,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              )),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 6,
                                bottom: 6,
                                child: Row(
                                  children: [
                                    IconButton.filledTonal(
                                      onPressed: saving
                                          ? null
                                          : () async {
                                              final picked =
                                                  await _picker.pickImage(
                                                source: ImageSource.gallery,
                                                imageQuality: 85,
                                              );
                                              if (picked == null) return;
                                              setSheetState(() {
                                                selectedLogo = picked;
                                                removedLogo = false;
                                              });
                                            },
                                      icon: const Icon(
                                        Icons.photo_library_outlined,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton.filledTonal(
                                      onPressed: saving
                                          ? null
                                          : () {
                                              setSheetState(() {
                                                selectedLogo = null;
                                                removedLogo = true;
                                              });
                                            },
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Turnuva Adı',
                          border: OutlineInputBorder(),
                        ),
                        enabled: !saving,
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Gizli Turnuva'),
                        value: isPrivate,
                        onChanged: saving
                            ? null
                            : (v) {
                                setSheetState(() {
                                  isPrivate = v;
                                  if (isPrivate &&
                                      accessCodeController.text
                                          .trim()
                                          .isEmpty) {
                                    accessCodeController.text = newAccessCode();
                                  }
                                  if (!isPrivate) accessCodeController.clear();
                                });
                              },
                      ),
                      if (isPrivate) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: accessCodeController,
                          decoration: const InputDecoration(
                            labelText: 'Erişim Kodu',
                            border: OutlineInputBorder(),
                          ),
                          enabled: !saving,
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed:
                              saving ? null : () => submit(setSheetState),
                          child: saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'KAYDET',
                                  style: TextStyle(fontWeight: FontWeight.w900),
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
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    accessCodeController.dispose();
  }

  Future<bool> _softDeleteLeague(League league) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turnuvayı Kaldır'),
        content: const Text('Turnuva pasife alınacak. Devam edilsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Evet'),
          ),
        ],
      ),
    );
    if (ok != true) return false;

    try {
      await _sb
          .from('leagues')
          .update({'is_active': false})
          .eq('id', league.id);
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turnuva pasife alındı.')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
      return false;
    }
  }

  static const List<String> _turkiyeIlleri = <String>[
    'Adana',
    'Adıyaman',
    'Afyonkarahisar',
    'Ağrı',
    'Amasya',
    'Ankara',
    'Antalya',
    'Artvin',
    'Aydın',
    'Balıkesir',
    'Bilecik',
    'Bingöl',
    'Bitlis',
    'Bolu',
    'Burdur',
    'Bursa',
    'Çanakkale',
    'Çankırı',
    'Çorum',
    'Denizli',
    'Diyarbakır',
    'Edirne',
    'Elazığ',
    'Erzincan',
    'Erzurum',
    'Eskişehir',
    'Gaziantep',
    'Giresun',
    'Gümüşhane',
    'Hakkâri',
    'Hatay',
    'Isparta',
    'Mersin',
    'İstanbul',
    'İzmir',
    'Kars',
    'Kastamonu',
    'Kayseri',
    'Kırklareli',
    'Kırşehir',
    'Kocaeli',
    'Konya',
    'Kütahya',
    'Malatya',
    'Manisa',
    'Kahramanmaraş',
    'Mardin',
    'Muğla',
    'Muş',
    'Nevşehir',
    'Niğde',
    'Ordu',
    'Rize',
    'Sakarya',
    'Samsun',
    'Siirt',
    'Sinop',
    'Sivas',
    'Tekirdağ',
    'Tokat',
    'Trabzon',
    'Tunceli',
    'Şanlıurfa',
    'Uşak',
    'Van',
    'Yozgat',
    'Zonguldak',
    'Aksaray',
    'Bayburt',
    'Karaman',
    'Kırıkkale',
    'Batman',
    'Şırnak',
    'Bartın',
    'Ardahan',
    'Iğdır',
    'Yalova',
    'Karabük',
    'Kilis',
    'Osmaniye',
    'Düzce',
  ];

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    final cs = Theme.of(context).colorScheme;
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Turnuva Yönetimi')),
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
        title: const Text('Turnuva Yönetimi'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _createLeagueDialog,
            icon: const Icon(Icons.add),
            color: const Color(0xFF10B981),
            tooltip: 'Yeni Turnuva Oluştur',
          ),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const SizedBox(height: 12),
          StreamBuilder<List<League>>(
            stream: _watchActiveLeagues(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final leagues = snapshot.data ?? const <League>[];

              if (leagues.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Turnuva bulunamadı.')),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: leagues.length,
                itemBuilder: (context, index) {
                  final league = leagues[index];
                  return Dismissible(
                    key: ValueKey(league.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) => _softDeleteLeague(league),
                    background: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.centerRight,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                      ),
                    ),
                    child: Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        leading: league.logoUrl.isNotEmpty
                            ? SizedBox(
                                width: 36,
                                height: 36,
                                child: WebSafeImage(
                                  url: league.logoUrl,
                                  width: 36,
                                  height: 36,
                                  borderRadius: BorderRadius.circular(8),
                                  fallbackIconSize: 18,
                                ),
                              )
                            : Icon(
                                Icons.emoji_events,
                                color: cs.onSurfaceVariant,
                              ),
                        title: Text(
                          league.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          softWrap: true,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => _editLeagueDialog(league),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SeasonManagementScreen(
                                leagueId: league.id,
                                leagueName: league.name,
                                leagueLogoUrl: league.logoUrl,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class EditLeagueScreen extends StatefulWidget {
  final League league;
  const EditLeagueScreen({super.key, required this.league});

  @override
  State<EditLeagueScreen> createState() => _EditLeagueScreenState();
}

class _EditLeagueScreenState extends State<EditLeagueScreen> {
  late TextEditingController _nameController;
  late TextEditingController _subtitleController;
  late TextEditingController _managerFullNameController;
  late TextEditingController _managerPhoneController;
  late TextEditingController _matchPeriodDurationController;
  late TextEditingController _groupCountController;
  late TextEditingController _teamsPerGroupController;
  late TextEditingController _ytController;
  late TextEditingController _igController;
  late TextEditingController _startDateController;
  late TextEditingController _endDateController;
  late TextEditingController _accessCodeController;
  DateTime? _startDate;
  DateTime? _endDate;
  XFile? _newLogo;
  bool _isLoading = false;
  bool _isPrivate = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.league.name);
    _managerFullNameController =
        TextEditingController(text: widget.league.managerFullName ?? '');
    _managerPhoneController =
        TextEditingController(text: widget.league.managerPhoneRaw10 ?? '');
    _matchPeriodDurationController = TextEditingController(
      text: widget.league.matchPeriodDuration.toString(),
    );
    _groupCountController =
        TextEditingController(text: widget.league.groupCount.toString());
    _teamsPerGroupController =
        TextEditingController(text: widget.league.teamsPerGroup.toString());
    _ytController = TextEditingController(text: widget.league.youtubeUrl);
    _igController = TextEditingController(text: widget.league.instagramUrl);
    _startDate = widget.league.startDate;
    _endDate = widget.league.endDate;
    _isPrivate = widget.league.isPrivate;
    _accessCodeController =
        TextEditingController(text: widget.league.accessCode ?? '');
    if (_isPrivate && _accessCodeController.text.trim().isEmpty) {
      _accessCodeController.text = _generateAccessCode();
    }
    _startDateController = TextEditingController(
      text: _startDate == null ? '' : _formatDate(_startDate!),
    );
    _endDateController = TextEditingController(
      text: _endDate == null ? '' : _formatDate(_endDate!),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _subtitleController.dispose();
    _managerFullNameController.dispose();
    _managerPhoneController.dispose();
    _matchPeriodDurationController.dispose();
    _groupCountController.dispose();
    _teamsPerGroupController.dispose();
    _ytController.dispose();
    _igController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _accessCodeController.dispose();
    super.dispose();
  }

  static String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  static String _generateAccessCode() {
    final n = 100000 + Random().nextInt(900000);
    return n.toString();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_startDate ?? now)
        : (_endDate ?? _startDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
        if (_startDate != null && _endDate!.isBefore(_startDate!)) {
          _startDate = picked;
        }
      }
      _startDateController.text = _startDate == null ? '' : _formatDate(_startDate!);
      _endDateController.text = _endDate == null ? '' : _formatDate(_endDate!);
    });
  }

  Future<void> _update() async {
    final name = _nameController.text.trim();
    final groupCount = int.tryParse(_groupCountController.text.trim()) ?? 0;
    final teamsPerGroup =
        int.tryParse(_teamsPerGroupController.text.trim()) ?? 0;
    final managerFullName = _managerFullNameController.text.trim();
    final managerPhone = _managerPhoneController.text.trim();
    final matchPeriodDuration =
        int.tryParse(_matchPeriodDurationController.text.trim()) ?? 25;
    if (_isPrivate && _accessCodeController.text.trim().isEmpty) {
      _accessCodeController.text = _generateAccessCode();
    }
    if (name.isEmpty || _startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen turnuva adı, başlangıç ve bitiş tarihini girin.'),
        ),
      );
      return;
    }
    if (groupCount <= 0 || teamsPerGroup <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Grup sayısı ve grup başı takım 0 olamaz.')),
      );
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isLoading = true);
    try {
      String normalizePhoneToRaw10(String input) {
        final digits = input.replaceAll(RegExp(r'\D'), '');
        if (digits.isEmpty) return '';
        var d = digits;
        if (d.startsWith('90') && d.length >= 12) d = d.substring(2);
        if (d.startsWith('0')) d = d.substring(1);
        if (d.length > 10) d = d.substring(d.length - 10);
        return d;
      }

      String logoUrl = widget.league.logoUrl;
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

      final updatedLeague = League(
        id: widget.league.id,
        name: name,
        logoUrl: logoUrl,
        country: widget.league.country,
        managerFullName: managerFullName.isEmpty ? null : managerFullName,
        managerPhoneRaw10:
            managerPhone.trim().isEmpty ? null : normalizePhoneToRaw10(managerPhone),
        matchPeriodDuration: matchPeriodDuration <= 0 ? 25 : matchPeriodDuration,
        startDate: _startDate,
        endDate: _endDate,
        season: widget.league.season,
        isActive: widget.league.isActive,
        isDefault: widget.league.isDefault,
        isPrivate: _isPrivate,
        accessCode: _isPrivate && _accessCodeController.text.trim().isNotEmpty
            ? _accessCodeController.text.trim()
            : null,
        youtubeUrl: _ytController.text.trim(),
        instagramUrl: _igController.text.trim(),
        numberOfGroups: groupCount,
        groups: List.generate(
          groupCount,
          (i) => String.fromCharCode(65 + i), // A, B, C...
        ),
        groupCount: groupCount,
        teamsPerGroup: teamsPerGroup,
      );

      await ServiceLocator.leagueService.updateLeague(updatedLeague);
      if (!mounted) return;
      Navigator.pop(context, true);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Turnuvayı Düzenle')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Logo Düzenleme
                Center(
                  child: Stack(
                    children: [
                      if (_newLogo != null)
                        CircleAvatar(
                          radius: 60,
                          backgroundImage: FileImage(File(_newLogo!.path)),
                        )
                      else if (widget.league.logoUrl.isNotEmpty)
                        SizedBox(
                          width: 120,
                          height: 120,
                          child: WebSafeImage(
                            url: widget.league.logoUrl,
                            width: 120,
                            height: 120,
                            isCircle: true,
                            fallbackIconSize: 40,
                          ),
                        )
                      else
                        const CircleAvatar(
                          radius: 60,
                          child: Icon(Icons.emoji_events, size: 40),
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
                const SizedBox(height: 24),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Turnuva Adı',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _subtitleController,
                  decoration: const InputDecoration(
                    labelText: 'Alt Bilgi (Örn: Yaz Ligi 2024)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gizlensin'),
                  value: _isPrivate,
                  onChanged: _isLoading
                      ? null
                      : (v) {
                          setState(() {
                            _isPrivate = v;
                            if (_isPrivate &&
                                _accessCodeController.text.trim().isEmpty) {
                              _accessCodeController.text = _generateAccessCode();
                            }
                            if (!_isPrivate) {
                              _accessCodeController.clear();
                            }
                          });
                        },
                ),
                if (_isPrivate) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _accessCodeController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Erişim Kodu (6 haneli)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else
                  const SizedBox(height: 16),
                TextField(
                  controller: _managerFullNameController,
                  decoration: const InputDecoration(
                    labelText: 'Turnuva Sorumlusu (Ad Soyad)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _managerPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Turnuva Sorumlusu Telefon',
                    hintText: '0 (5XX) XXX XX XX',
                    border: OutlineInputBorder(),
                  ),
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _matchPeriodDurationController,
                  decoration: const InputDecoration(
                    labelText: 'Maç Süresi (Dakika)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _startDateController,
                        readOnly: true,
                        onTap: _isLoading ? null : () => _pickDate(isStart: true),
                        decoration: const InputDecoration(
                          hintText: 'Başlangıç Tarihi',
                          prefixIcon: Icon(Icons.calendar_month_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _endDateController,
                        readOnly: true,
                        onTap: _isLoading ? null : () => _pickDate(isStart: false),
                        decoration: const InputDecoration(
                          hintText: 'Bitiş Tarihi',
                          prefixIcon: Icon(Icons.calendar_month_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _groupCountController,
                        decoration: const InputDecoration(
                          labelText: 'Grup Sayısı',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        enabled: !_isLoading,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _teamsPerGroupController,
                        decoration: const InputDecoration(
                          labelText: 'Toplam Takım Sayısı',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        enabled: !_isLoading,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _ytController,
                  decoration: const InputDecoration(
                    labelText: 'YouTube Linki',
                    prefixIcon: Icon(Icons.play_circle_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _igController,
                  decoration: const InputDecoration(
                    labelText: 'Instagram Linki',
                    prefixIcon: Icon(Icons.camera_alt_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _isLoading ? null : _update,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('GÜNCELLE'),
                ),
              ],
            ),
          if (_isLoading)
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: cs.surface.withValues(alpha: 0.55),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
