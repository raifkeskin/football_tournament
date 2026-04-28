import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/league.dart';
import '../models/season.dart';
import '../../../core/services/app_session.dart';
import '../../../core/services/image_upload_service.dart';
import '../services/interfaces/i_league_service.dart';
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
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final _imageUploadService = ImgBBUploadService();
  final _picker = ImagePicker();

  SupabaseClient get _sb => Supabase.instance.client;

  static String _contentTypeForPath(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  Future<String> _uploadLeagueLogo({
    required String leagueId,
    required XFile file,
  }) async {
    final bytes = await File(file.path).readAsBytes();
    final ext = file.name.contains('.') ? file.name.split('.').last : 'jpg';
    final filePath =
        'league_$leagueId/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _sb.storage.from('leagues_logos').uploadBinary(
          filePath,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: _contentTypeForPath(file.path),
          ),
        );

    return _sb.storage.from('leagues_logos').getPublicUrl(filePath);
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

    Future<void> submit(void Function(void Function()) setDialogState) async {
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

      setDialogState(() => saving = true);
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
            leagueId: leagueId,
            file: selectedLogo!,
          );
          await _sb.from('leagues').update({'logo_url': url}).eq('id', leagueId);
        }
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Turnuva oluşturuldu.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      } finally {
        if (mounted) setDialogState(() => saving = false);
      }
    }

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text('Yeni Turnuva/Marka Oluştur'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        ClipPath(
                          clipper: ShapeBorderClipper(
                            shape: const OvalBorder(),
                          ),
                          child: Container(
                            width: double.infinity,
                            height: 160,
                            decoration: ShapeDecoration(
                              shape: const OvalBorder(),
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              shadows: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.10),
                                  blurRadius: 18,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: selectedLogo != null
                                ? Image.file(
                                    File(selectedLogo!.path),
                                    fit: BoxFit.cover,
                                  )
                                : Center(
                                    child: Icon(
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
                          right: 10,
                          bottom: 10,
                          child: Row(
                            children: [
                              IconButton.filledTonal(
                                onPressed: saving
                                    ? null
                                    : () async {
                                        final picked = await _picker.pickImage(
                                          source: ImageSource.gallery,
                                          imageQuality: 85,
                                        );
                                        if (picked == null) return;
                                        setDialogState(
                                          () => selectedLogo = picked,
                                        );
                                      },
                                icon: const Icon(
                                  Icons.photo_library_outlined,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                onPressed: saving
                                    ? null
                                    : () => setDialogState(
                                          () => selectedLogo = null,
                                        ),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
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
                            setDialogState(() {
                              isPrivate = v;
                              if (isPrivate &&
                                  accessCodeController.text.trim().isEmpty) {
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
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: saving ? null : () => submit(setDialogState),
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
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

    Future<void> submit(void Function(void Function()) setDialogState) async {
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

      setDialogState(() => saving = true);
      try {
        final update = <String, dynamic>{'name': name};
        if (removedLogo) update['logo_url'] = null;
        update['is_private'] = isPrivate;
        update['access_code'] = isPrivate ? access : null;

        await _sb.from('leagues').update(update).eq('id', league.id);

        if (!removedLogo && selectedLogo != null) {
          final url = await _uploadLeagueLogo(
            leagueId: league.id,
            file: selectedLogo!,
          );
          await _sb.from('leagues').update({'logo_url': url}).eq('id', league.id);
        }
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Güncellendi.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      } finally {
        if (mounted) setDialogState(() => saving = false);
      }
    }

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final showUrl = removedLogo
              ? ''
              : (selectedLogo == null ? existingUrlInitial : '');
          String newAccessCode() {
            final n = 100000 + Random().nextInt(900000);
            return n.toString();
          }
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text('Turnuvayı Düzenle'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        ClipPath(
                          clipper: ShapeBorderClipper(
                            shape: const OvalBorder(),
                          ),
                          child: Container(
                            width: double.infinity,
                            height: 160,
                            decoration: ShapeDecoration(
                              shape: const OvalBorder(),
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              shadows: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.10),
                                  blurRadius: 18,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: selectedLogo != null
                                ? Image.file(
                                    File(selectedLogo!.path),
                                    fit: BoxFit.cover,
                                  )
                                : (showUrl.isNotEmpty
                                    ? WebSafeImage(
                                        url: showUrl,
                                        width: double.infinity,
                                        height: 160,
                                        fit: BoxFit.cover,
                                      )
                                    : Center(
                                        child: Icon(
                                          Icons.business,
                                          size: 44,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      )),
                          ),
                        ),
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Row(
                            children: [
                              IconButton.filledTonal(
                                onPressed: saving
                                    ? null
                                    : () async {
                                        final picked = await _picker.pickImage(
                                          source: ImageSource.gallery,
                                          imageQuality: 85,
                                        );
                                        if (picked == null) return;
                                        setDialogState(() {
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
                                        setDialogState(() {
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
                  const SizedBox(height: 12),
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
                            setDialogState(() {
                              isPrivate = v;
                              if (isPrivate &&
                                  accessCodeController.text.trim().isEmpty) {
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
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: saving ? null : () => submit(setDialogState),
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
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

  Future<void> _createSeasonSheet(League league) async {
    final nameController = TextEditingController();
    final subtitleController = TextEditingController();
    final startDateController = TextEditingController();
    final endDateController = TextEditingController();
    final startingPlayerCountController = TextEditingController(text: '11');
    final subPlayerCountController = TextEditingController(text: '7');
    final cityController = TextEditingController();
    final countryController = TextEditingController(text: 'Türkiye');
    final transferStartController = TextEditingController();
    final transferEndController = TextEditingController();
    final teamsPerGroupController = TextEditingController(text: '4');
    final numberOfGroupsController = TextEditingController(text: '1');
    final instagramController = TextEditingController();
    final youtubeController = TextEditingController();
    final matchPeriodDurationController = TextEditingController(text: '25');
    final groupCountController = TextEditingController(text: '1');

    DateTime? startDate;
    DateTime? endDate;
    DateTime? transferStartDate;
    DateTime? transferEndDate;
    var isActive = true;
    var isDefault = false;
    var saving = false;

    String tarihYaz(DateTime date) {
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    }

    String dateOnly(DateTime date) {
      final y = date.year.toString().padLeft(4, '0');
      final m = date.month.toString().padLeft(2, '0');
      final d = date.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    Future<void> pickDate({
      required void Function(void Function()) setSheetState,
      required bool isStart,
    }) async {
      final now = DateTime.now();
      final initial = isStart
          ? (startDate ?? now)
          : (endDate ?? startDate ?? now);
      final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(now.year - 2),
        lastDate: DateTime(now.year + 5),
      );
      if (picked == null) return;
      setSheetState(() {
        if (isStart) {
          startDate = picked;
          startDateController.text = tarihYaz(picked);
        } else {
          endDate = picked;
          endDateController.text = tarihYaz(picked);
        }
      });
    }

    Future<void> pickTransferDate({
      required void Function(void Function()) setSheetState,
      required bool isStart,
    }) async {
      final now = DateTime.now();
      final initial = isStart
          ? (transferStartDate ?? now)
          : (transferEndDate ?? transferStartDate ?? now);
      final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(now.year - 2),
        lastDate: DateTime(now.year + 5),
      );
      if (picked == null) return;
      setSheetState(() {
        if (isStart) {
          transferStartDate = picked;
          transferStartController.text = tarihYaz(picked);
        } else {
          transferEndDate = picked;
          transferEndController.text = tarihYaz(picked);
        }
      });
    }

    Future<void> submit(void Function(void Function()) setSheetState) async {
      final name = nameController.text.trim();
      final subtitle = subtitleController.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sezon adı zorunludur.')),
        );
        return;
      }
      if (startDate == null || endDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Başlangıç ve bitiş tarihi zorunludur.')),
        );
        return;
      }

      final season = Season(
        id: '',
        leagueId: league.id,
        name: name,
        subtitle: subtitle.isEmpty ? null : subtitle,
        startDate: startDate,
        endDate: endDate,
        startingPlayerCount:
            int.tryParse(startingPlayerCountController.text.trim()) ?? 11,
        subPlayerCount: int.tryParse(subPlayerCountController.text.trim()) ?? 7,
        city: cityController.text.trim().isEmpty ? null : cityController.text.trim(),
        country: countryController.text.trim().isEmpty
            ? 'Türkiye'
            : countryController.text.trim(),
        isActive: isActive,
        isDefault: isDefault,
        transferStartDate: transferStartDate,
        transferEndDate: transferEndDate,
        teamsPerGroup: int.tryParse(teamsPerGroupController.text.trim()) ?? 4,
        numberOfGroups: int.tryParse(numberOfGroupsController.text.trim()) ?? 1,
        instagramUrl: instagramController.text.trim().isEmpty
            ? null
            : instagramController.text.trim(),
        youtubeUrl:
            youtubeController.text.trim().isEmpty ? null : youtubeController.text.trim(),
        matchPeriodDuration:
            int.tryParse(matchPeriodDurationController.text.trim()) ?? 25,
        groupCount: int.tryParse(groupCountController.text.trim()) ?? 1,
      );

      setSheetState(() => saving = true);
      try {
        final payload = Map<String, dynamic>.from(season.toJson());
        payload.remove('id');
        payload['start_date'] = dateOnly(startDate!);
        payload['end_date'] = dateOnly(endDate!);
        await _sb.from('seasons').insert(payload);
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sezon oluşturuldu.')),
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
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Yeni Sezon Oluştur',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Sezon Adı',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !saving,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: startDateController,
                            readOnly: true,
                            onTap: saving
                                ? null
                                : () => pickDate(
                                      setSheetState: setSheetState,
                                      isStart: true,
                                    ),
                            decoration: const InputDecoration(
                              labelText: 'Başlangıç',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.calendar_month_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: endDateController,
                            readOnly: true,
                            onTap: saving
                                ? null
                                : () => pickDate(
                                      setSheetState: setSheetState,
                                      isStart: false,
                                    ),
                            decoration: const InputDecoration(
                              labelText: 'Bitiş',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.calendar_month_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: startingPlayerCountController,
                            decoration: const InputDecoration(
                              labelText: 'Başlangıç Oyuncu',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            enabled: !saving,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: subPlayerCountController,
                            decoration: const InputDecoration(
                              labelText: 'Yedek Oyuncu',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            enabled: !saving,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: cityController,
                            decoration: const InputDecoration(
                              labelText: 'Şehir',
                              border: OutlineInputBorder(),
                            ),
                            enabled: !saving,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: countryController,
                            decoration: const InputDecoration(
                              labelText: 'Ülke',
                              border: OutlineInputBorder(),
                            ),
                            enabled: !saving,
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Varsayılan'),
                      value: isDefault,
                      onChanged:
                          saving ? null : (v) => setSheetState(() => isDefault = v),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: teamsPerGroupController,
                            decoration: const InputDecoration(
                              labelText: 'Grup Başı Takım',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            enabled: !saving,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: numberOfGroupsController,
                            decoration: const InputDecoration(
                              labelText: 'Grup Sayısı',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            enabled: !saving,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: matchPeriodDurationController,
                            decoration: const InputDecoration(
                              labelText: 'Maç Süresi',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            enabled: !saving,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: transferStartController,
                            readOnly: true,
                            onTap: saving
                                ? null
                                : () => pickTransferDate(
                                      setSheetState: setSheetState,
                                      isStart: true,
                                    ),
                            decoration: const InputDecoration(
                              labelText: 'Transfer Başlangıç',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.calendar_month_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: transferEndController,
                            readOnly: true,
                            onTap: saving
                                ? null
                                : () => pickTransferDate(
                                      setSheetState: setSheetState,
                                      isStart: false,
                                    ),
                            decoration: const InputDecoration(
                              labelText: 'Transfer Bitiş',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.calendar_month_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: instagramController,
                      decoration: const InputDecoration(
                        labelText: 'Instagram URL',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !saving,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: youtubeController,
                      decoration: const InputDecoration(
                        labelText: 'YouTube URL',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !saving,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: saving ? null : () => Navigator.pop(context),
                            child: const Text('Vazgeç'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: saving ? null : () => submit(setSheetState),
                            child: saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Kaydet'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    nameController.dispose();
    subtitleController.dispose();
    startDateController.dispose();
    endDateController.dispose();
    startingPlayerCountController.dispose();
    subPlayerCountController.dispose();
    cityController.dispose();
    countryController.dispose();
    transferStartController.dispose();
    transferEndController.dispose();
    teamsPerGroupController.dispose();
    numberOfGroupsController.dispose();
    instagramController.dispose();
    youtubeController.dispose();
    matchPeriodDurationController.dispose();
    groupCountController.dispose();
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

  Future<String?> _sehirSec({
    required BuildContext context,
    String? initialValue,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? _turkiyeIlleri
                : _turkiyeIlleri
                    .where((c) => c.toLowerCase().contains(q))
                    .toList();
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Şehir Ara',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) => setModalState(() => query = v),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final city = filtered[index];
                          final selected =
                              (initialValue ?? '').trim().toLowerCase() ==
                                  city.toLowerCase();
                          return ListTile(
                            title: Text(city),
                            trailing: selected
                                ? const Icon(Icons.check_rounded)
                                : null,
                            onTap: () => Navigator.pop(context, city),
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
  }

  Future<void> _turnuvaSil(String leagueId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turnuva Sil'),
        content: const Text(
          'Turnuva ve ilişkili veriler silinecektir. Devam etmek istiyor musunuz?',
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
      await _leagueService.deleteLeagueCascade(leagueId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Turnuva silindi.')));
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _openAddLeagueSheet() async {
    final leagueNameController = TextEditingController();
    final subtitleController = TextEditingController();
    final managerFullNameController = TextEditingController();
    final managerPhoneController = TextEditingController();
    final cityController = TextEditingController();
    final matchPeriodDurationController = TextEditingController(text: '25');
    final startingPlayerCountController = TextEditingController(text: '11');
    final subPlayerCountController = TextEditingController(text: '7');
    final groupCountController = TextEditingController(text: '1');
    final teamsPerGroupController = TextEditingController(text: '4');
    final youtubeController = TextEditingController();
    final instagramController = TextEditingController();
    final startDateController = TextEditingController();
    final endDateController = TextEditingController();
    final accessCodeController = TextEditingController();

    DateTime? startDate;
    DateTime? endDate;
    XFile? leagueLogo;
    var isPrivate = false;
    var saving = false;

    String tarihYaz(DateTime date) {
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    }

    void syncDateText() {
      startDateController.text = startDate == null ? '' : tarihYaz(startDate!);
      endDateController.text = endDate == null ? '' : tarihYaz(endDate!);
    }

    Future<void> tarihSec({
      required bool isStart,
      required void Function(void Function()) setSheetState,
    }) async {
      final now = DateTime.now();
      final initial = isStart
          ? (startDate ?? now)
          : (endDate ?? startDate ?? now);
      final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(now.year - 2),
        lastDate: DateTime(now.year + 5),
      );
      if (picked == null) return;
      setSheetState(() {
        if (isStart) {
          startDate = picked;
          if (endDate != null && endDate!.isBefore(picked)) {
            endDate = picked;
          }
        } else {
          endDate = picked;
          if (startDate != null && endDate!.isBefore(startDate!)) {
            startDate = endDate;
          }
        }
        syncDateText();
      });
    }

    Future<void> logoSec(void Function(void Function()) setSheetState) async {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null) return;
      setSheetState(() => leagueLogo = picked);
    }

    String generateAccessCode() {
      final n = 100000 + Random().nextInt(900000);
      return n.toString();
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> save() async {
              FocusManager.instance.primaryFocus?.unfocus();
              final name = leagueNameController.text.trim();
              final subtitle = subtitleController.text.trim();
              final managerFullName = managerFullNameController.text.trim();
              final managerPhone = managerPhoneController.text.trim();
              final city = cityController.text.trim();
              final matchPeriodDuration =
                  int.tryParse(matchPeriodDurationController.text.trim()) ?? 25;
              final startingPlayerCount =
                  int.tryParse(startingPlayerCountController.text.trim()) ?? 11;
              final subPlayerCount =
                  int.tryParse(subPlayerCountController.text.trim()) ?? 7;
              if (isPrivate && accessCodeController.text.trim().isEmpty) {
                accessCodeController.text = generateAccessCode();
              }
              if (name.isEmpty || startDate == null || endDate == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Lütfen turnuva adı, başlangıç ve bitiş tarihini girin.',
                    ),
                  ),
                );
                return;
              }
              setSheetState(() => saving = true);
              var didClose = false;
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

                var logoUrl = '';
                if (leagueLogo != null) {
                  final uploadedUrl = await _imageUploadService.uploadImage(
                    File(leagueLogo!.path),
                  );
                  if (uploadedUrl == null) {
                    throw Exception('Logo yüklenemedi.');
                  }
                  logoUrl = uploadedUrl;
                }

                final league = League(
                  id: '',
                  name: name,
                  logoUrl: logoUrl,
                  country: 'Türkiye',
                  city: city.isEmpty ? null : city,
                  managerFullName:
                      managerFullName.isEmpty ? null : managerFullName,
                  managerPhoneRaw10: managerPhone.isEmpty
                      ? null
                      : normalizePhoneToRaw10(managerPhone),
                  matchPeriodDuration:
                      matchPeriodDuration <= 0 ? 25 : matchPeriodDuration,
                  startingPlayerCount:
                      startingPlayerCount <= 0 ? 11 : startingPlayerCount,
                  subPlayerCount: subPlayerCount < 0 ? 7 : subPlayerCount,
                  startDate: startDate,
                  endDate: endDate,
                  isPrivate: isPrivate,
                  accessCode: isPrivate && accessCodeController.text.trim().isNotEmpty
                      ? accessCodeController.text.trim()
                      : null,
                  youtubeUrl: youtubeController.text.trim(),
                  instagramUrl: instagramController.text.trim(),
                  numberOfGroups: int.tryParse(groupCountController.text) ?? 1,
                  groups: List.generate(
                    int.tryParse(groupCountController.text) ?? 1,
                    (i) => String.fromCharCode(65 + i), // A, B, C...
                  ),
                  groupCount: int.tryParse(groupCountController.text) ?? 1,
                  teamsPerGroup:
                      int.tryParse(teamsPerGroupController.text) ?? 4,
                );

                await _leagueService.addLeague(league);
                if (!context.mounted) return;
                didClose = true;
                Navigator.pop(context, true);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Hata: $e')));
              } finally {
                if (!didClose && context.mounted) {
                  setSheetState(() => saving = false);
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 4,
                bottom: viewInsets.bottom + 16,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    'Yeni Turnuva',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: leagueNameController,
                    decoration: const InputDecoration(labelText: 'Turnuva Adı'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subtitleController,
                    decoration: const InputDecoration(
                      labelText: 'Alt Bilgi (Örn: Yaz Ligi 2024)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Gizlensin'),
                    value: isPrivate,
                    onChanged: saving
                        ? null
                        : (v) {
                            setSheetState(() {
                              isPrivate = v;
                              if (isPrivate &&
                                  accessCodeController.text.trim().isEmpty) {
                                accessCodeController.text =
                                    generateAccessCode();
                              }
                              if (!isPrivate) {
                                accessCodeController.clear();
                              }
                            });
                          },
                  ),
                  if (isPrivate) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: accessCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Erişim Kodu (6 haneli)',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: managerFullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Turnuva Sorumlusu (Ad Soyad)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: managerPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Turnuva Sorumlusu Telefon',
                      hintText: '0 (5XX) XXX XX XX',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cityController,
                    decoration: const InputDecoration(
                      labelText: 'Şehir',
                    ),
                    readOnly: true,
                    onTap: saving
                        ? null
                        : () async {
                            final picked = await _sehirSec(
                              context: context,
                              initialValue: cityController.text,
                            );
                            if (picked == null) return;
                            setSheetState(() => cityController.text = picked);
                          },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: matchPeriodDurationController,
                    decoration: const InputDecoration(
                      labelText: 'Maç Süresi (Tek Devre)',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startingPlayerCountController,
                          decoration: const InputDecoration(
                            labelText: 'Sahadaki Oyuncu',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: subPlayerCountController,
                          decoration: const InputDecoration(
                            labelText: 'Yedek Oyuncu',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startDateController,
                          readOnly: true,
                          onTap: saving
                              ? null
                              : () => tarihSec(
                                    isStart: true,
                                    setSheetState: setSheetState,
                                  ),
                          decoration: const InputDecoration(
                            hintText: 'Başlangıç Tarihi',
                            prefixIcon: Icon(Icons.calendar_month_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: endDateController,
                          readOnly: true,
                          onTap: saving
                              ? null
                              : () => tarihSec(
                                    isStart: false,
                                    setSheetState: setSheetState,
                                  ),
                          decoration: const InputDecoration(
                            hintText: 'Bitiş Tarihi',
                            prefixIcon: Icon(Icons.calendar_month_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: groupCountController,
                          decoration: const InputDecoration(
                            labelText: 'Grup Sayısı',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: teamsPerGroupController,
                          decoration: const InputDecoration(
                            labelText: 'Grup Başı Takım',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: youtubeController,
                    decoration: const InputDecoration(
                      labelText: 'YouTube Linki',
                      prefixIcon: Icon(Icons.play_circle_outline),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: instagramController,
                    decoration: const InputDecoration(
                      labelText: 'Instagram Linki',
                      prefixIcon: Icon(Icons.camera_alt_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: saving ? null : () => logoSec(setSheetState),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(
                      leagueLogo == null
                          ? 'LOGO EKLE'
                          : 'Seçildi: ${leagueLogo!.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 48,
                    child: saving
                        ? const Center(child: CircularProgressIndicator())
                        : FilledButton.icon(
                            onPressed: save,
                            label: const Text('KAYDET'),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    leagueNameController.dispose();
    subtitleController.dispose();
    groupCountController.dispose();
    teamsPerGroupController.dispose();
    youtubeController.dispose();
    instagramController.dispose();
    startDateController.dispose();
    endDateController.dispose();
    accessCodeController.dispose();
    managerFullNameController.dispose();
    managerPhoneController.dispose();
    cityController.dispose();
    matchPeriodDurationController.dispose();
    startingPlayerCountController.dispose();
    subPlayerCountController.dispose();

    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turnuva eklendi.')),
      );
      setState(() {});
    }
  }

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
        actions: [
          IconButton(
            onPressed: _createLeagueDialog,
            icon: const Icon(Icons.add),
            color: const Color(0xFF10B981),
            tooltip: 'Yeni Turnuva/Marka Oluştur',
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
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'new_season') {
                                  _createSeasonSheet(league);
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem<String>(
                                  value: 'new_season',
                                  child: Text('Yeni Sezon Oluştur'),
                                ),
                              ],
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
                          labelText: 'Grup Başı Takım',
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
