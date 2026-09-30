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
import '../../../core/widgets/admin_page.dart';
import '../../../core/widgets/app_date_picker.dart';
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
  late final Stream<List<League>> _leaguesStream = _watchActiveLeagues();

  SupabaseClient get _sb => Supabase.instance.client;

  Future<String> _uploadLeagueLogo({required XFile file}) async {
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
          list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
          return list;
        });
  }

  static String _newAccessCode() {
    final n = 100000 + Random().nextInt(900000);
    return n.toString();
  }

  /// Turnuva ekleme ([league] null) ve düzenleme popup'ı.
  Future<void> _openLeagueForm({League? league}) async {
    final isEdit = league != null;
    final nameController = TextEditingController(text: league?.name ?? '');
    final accessCodeController = TextEditingController(
      text: (league?.accessCode ?? '').trim(),
    );
    final existingLogoUrl = (league?.logoUrl ?? '').trim();
    XFile? selectedLogo;
    var removedLogo = false;
    var isPrivate = league?.isPrivate ?? false;
    var saving = false;

    Future<void> submit(
      BuildContext popupContext,
      void Function(void Function()) setPopupState,
    ) async {
      final messenger = ScaffoldMessenger.of(context);
      final name = nameController.text.trim();
      final access = accessCodeController.text.trim();
      if (name.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Turnuva adı zorunludur.')),
        );
        return;
      }
      if (isPrivate && access.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Gizli turnuva için erişim kodu zorunludur.'),
          ),
        );
        return;
      }

      setPopupState(() => saving = true);
      try {
        final payload = <String, dynamic>{
          'name': name,
          'is_private': isPrivate,
          'access_code': isPrivate ? access : null,
        };
        String leagueId;
        if (isEdit) {
          leagueId = league.id;
          if (removedLogo) payload['logo_url'] = null;
          await _sb.from('leagues').update(payload).eq('id', leagueId);
        } else {
          payload['is_active'] = true;
          final inserted = await _sb
              .from('leagues')
              .insert(payload)
              .select('id')
              .single();
          leagueId = (inserted['id'] as String?) ?? '';
        }

        if (selectedLogo != null && leagueId.trim().isNotEmpty) {
          final url = await _uploadLeagueLogo(file: selectedLogo!);
          await _sb
              .from('leagues')
              .update({'logo_url': url})
              .eq('id', leagueId);
        }

        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Turnuva güncellendi.' : 'Turnuva oluşturuldu.'),
          ),
        );
        if (popupContext.mounted) Navigator.of(popupContext).pop();
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
        if (popupContext.mounted) setPopupState(() => saving = false);
      }
    }

    await showAdminPopup<void>(
      context: context,
      builder: (popupContext) {
        return StatefulBuilder(
          builder: (context, setPopupState) {
            final viewInsets = MediaQuery.of(context).viewInsets;
            final showUrl = removedLogo || selectedLogo != null
                ? ''
                : existingLogoUrl;
            final hasLogo = selectedLogo != null || showUrl.isNotEmpty;

            Future<void> pickLogo() async {
              final picked = await _picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 85,
              );
              if (picked == null) return;
              setPopupState(() {
                selectedLogo = picked;
                removedLogo = false;
              });
            }

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isEdit
                            ? Icons.edit_outlined
                            : Icons.emoji_events_outlined,
                        color: kAdminAccent,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          isEdit ? 'Turnuvayı Düzenle' : 'Yeni Turnuva',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 18),
                  Center(
                    child: SizedBox(
                      width: 120,
                      height: 120,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: InkWell(
                              onTap: saving ? null : pickLogo,
                              customBorder: const CircleBorder(),
                              child: Container(
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.3),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.15),
                                  ),
                                ),
                                child: selectedLogo != null
                                    ? Image.file(
                                        File(selectedLogo!.path),
                                        fit: BoxFit.cover,
                                      )
                                    : (showUrl.isNotEmpty
                                          ? WebSafeImage(
                                              url: showUrl,
                                              width: 120,
                                              height: 120,
                                              fit: BoxFit.cover,
                                            )
                                          : const Icon(
                                              Icons.add_photo_alternate_outlined,
                                              size: 40,
                                              color: Colors.white38,
                                            )),
                              ),
                            ),
                          ),
                          Positioned(
                            right: -6,
                            bottom: -2,
                            child: Row(
                              children: [
                                AdminSmallAction(
                                  icon: Icons.photo_library_outlined,
                                  tooltip: 'Logo Seç',
                                  color: kAdminAccent,
                                  onTap: saving ? null : pickLogo,
                                ),
                                if (hasLogo) ...[
                                  const SizedBox(width: 6),
                                  AdminSmallAction(
                                    icon: Icons.delete_outline_rounded,
                                    tooltip: 'Logoyu Kaldır',
                                    color: kAdminDanger,
                                    onTap: saving
                                        ? null
                                        : () => setPopupState(() {
                                            selectedLogo = null;
                                            removedLogo = true;
                                          }),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameController,
                    enabled: !saving,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Turnuva Adı',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: SwitchListTile(
                      dense: true,
                      activeThumbColor: kAdminAccent,
                      secondary: const Icon(
                        Icons.lock_outline_rounded,
                        color: Colors.white54,
                      ),
                      title: const Text(
                        'Gizli Turnuva',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      value: isPrivate,
                      onChanged: saving
                          ? null
                          : (v) => setPopupState(() {
                              isPrivate = v;
                              if (isPrivate &&
                                  accessCodeController.text.trim().isEmpty) {
                                accessCodeController.text = _newAccessCode();
                              }
                              if (!isPrivate) accessCodeController.clear();
                            }),
                    ),
                  ),
                  if (isPrivate) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: accessCodeController,
                      enabled: !saving,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Erişim Kodu',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAdminAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: saving
                          ? null
                          : () => submit(popupContext, setPopupState),
                      child: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
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
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: saving
                          ? null
                          : () => Navigator.of(popupContext).pop(),
                      child: const Text(
                        'VAZGEÇ',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    // Popup kapanış animasyonu sürerken TextField'lar controller'ı kullanmaya
    // devam eder; hemen dispose etmek hataya yol açar.
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      nameController.dispose();
      accessCodeController.dispose();
    });
  }

  Future<void> _softDeleteLeague(League league) async {
    final ok = await showAdminConfirmDialog(
      context: context,
      title: 'Turnuvayı Kaldır',
      message: '"${league.name}" pasife alınacak. Devam edilsin mi?',
      confirmLabel: 'KALDIR',
    );
    if (!ok) return;

    try {
      await _sb
          .from('leagues')
          .update({'is_active': false})
          .eq('id', league.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turnuva pasife alındı.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  void _openSeasons(League league) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SeasonManagementScreen(
          leagueId: league.id,
          leagueName: league.name,
          leagueLogoUrl: league.logoUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    if (!isAdmin) {
      return const AdminPageScaffold(
        title: 'Turnuva Yönetimi',
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
      title: 'Turnuva Yönetimi',
      actions: [
        AdminBarAction(
          icon: Icons.add_rounded,
          tooltip: 'Yeni Turnuva',
          onPressed: () => _openLeagueForm(),
        ),
      ],
      body: StreamBuilder<List<League>>(
        stream: _leaguesStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Turnuvalar yüklenemedi.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: kAdminAccent),
            );
          }
          final leagues = snapshot.data!;
          if (leagues.isEmpty) {
            return const Center(
              child: Text(
                'Turnuva bulunamadı.',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            itemCount: leagues.length,
            itemBuilder: (context, index) {
              final league = leagues[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: adminCardDecoration(),
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(12, 4, 10, 4),
                  leading: SizedBox(
                    width: 40,
                    height: 40,
                    child: league.logoUrl.isNotEmpty
                        ? WebSafeImage(
                            url: league.logoUrl,
                            width: 40,
                            height: 40,
                            borderRadius: BorderRadius.circular(10),
                            fallbackIconSize: 20,
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFF59E0B,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.emoji_events_outlined,
                              color: Color(0xFFF59E0B),
                              size: 22,
                            ),
                          ),
                  ),
                  title: Text(
                    league.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: league.isPrivate
                      ? const Row(
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 12,
                              color: Colors.white38,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Gizli',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        )
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AdminSmallAction(
                        icon: Icons.edit_outlined,
                        tooltip: 'Düzenle',
                        color: Colors.white70,
                        onTap: () => _openLeagueForm(league: league),
                      ),
                      const SizedBox(width: 6),
                      AdminSmallAction(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'Kaldır',
                        color: kAdminDanger,
                        onTap: () => _softDeleteLeague(league),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right, color: Colors.white24),
                    ],
                  ),
                  onTap: () => _openSeasons(league),
                ),
              );
            },
          );
        },
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
    final picked = await showAppDatePicker(
      context: context,
      initialDate: initial,
      firstYear: now.year - 5,
      lastYear: now.year + 10,
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
    
    // Değişiklik: Context'i değişkene alıp Navigator.pop() için kullanacağız.
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    
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
      messenger.showSnackBar(
        const SnackBar(content: Text('Turnuva başarıyla güncellendi.')),
      );
      
      // Sayfa kapatılacağı için setState ile loading durumunu değiştirmeye gerek yok
      nav.pop(true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
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
