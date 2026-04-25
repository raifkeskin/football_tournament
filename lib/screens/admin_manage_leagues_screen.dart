import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/league.dart';
import '../services/app_session.dart';
import '../services/image_upload_service.dart';
import '../services/interfaces/i_league_service.dart';
import '../services/service_locator.dart';
import '../widgets/web_safe_image.dart';
import 'admin_awards_screen.dart';
import 'admin_fixture_entry_screen.dart';
import 'admin_group_management_screen.dart';
import 'admin_manage_teams_screen.dart';
import 'admin_penalty_management_screen.dart';

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
  bool _dialOpen = false;

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
                  subtitle: subtitle.isEmpty ? null : subtitle,
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
        appBar: AppBar(title: const Text('Turnuva Ayarları / Yönetimi')),
        body: const Center(
          child: Text(
            'Bu sayfaya erişim yetkiniz yok.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Turnuva Ayarları / Yönetimi')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: isAdmin
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_dialOpen) ...[
                  _DialItem(
                    label: 'Turnuva Ekle',
                    icon: Icons.add_rounded,
                    onPressed: () {
                      setState(() => _dialOpen = false);
                      _openAddLeagueSheet();
                    },
                  ),
                  const SizedBox(height: 10),
                  _DialItem(
                    label: 'Grup Atama',
                    icon: Icons.grid_view_outlined,
                    onPressed: () {
                      setState(() => _dialOpen = false);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AdminGroupManagementScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _DialItem(
                    label: 'Fikstür Planlama',
                    icon: Icons.calendar_month_outlined,
                    onPressed: () {
                      setState(() => _dialOpen = false);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AdminFixtureEntryScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _DialItem(
                    label: 'Ceza Yönetimi',
                    icon: Icons.gavel_outlined,
                    onPressed: () {
                      setState(() => _dialOpen = false);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AdminPenaltyManagementScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _DialItem(
                    label: 'Ödül/Kupa',
                    icon: Icons.military_tech_outlined,
                    onPressed: () {
                      setState(() => _dialOpen = false);
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AdminAwardsScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                FloatingActionButton(
                  onPressed: () => setState(() => _dialOpen = !_dialOpen),
                  child: Icon(_dialOpen ? Icons.close_rounded : Icons.add),
                ),
              ],
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          const SizedBox(height: 12),
          StreamBuilder<List<League>>(
            stream: _leagueService.watchLeagues(),
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
                  final subtitle = (league.subtitle ?? '').trim();
                  Future<void> toggleDefault() async {
                    try {
                      await _leagueService.setLeagueDefaultFlag(
                        leagueId: league.id,
                        isDefault: !league.isDefault,
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Hata: $e')),
                      );
                    }
                  }

                  Future<void> openEditDialog() async {
                    final updated = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => Dialog.fullscreen(
                        child: EditLeagueScreen(league: league),
                      ),
                    );
                    if (!context.mounted) return;
                    if (updated == true) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Güncellendi')),
                      );
                      setState(() {});
                    }
                  }

                  Future<void> openTeams() async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AdminManageTeamsScreen(
                          initialLeagueId: league.id,
                          lockLeagueSelection: true,
                        ),
                      ),
                    );
                  }

                  return Card(
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
                          : const Icon(Icons.emoji_events),
                      title: Text(
                        league.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                      ),
                      subtitle: subtitle.isEmpty
                          ? null
                          : Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: toggleDefault,
                            icon: Icon(
                              league.isDefault
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              color: league.isDefault
                                  ? const Color(0xFF10B981)
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                          IconButton(
                            onPressed: openEditDialog,
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ),
                      onTap: openTeams,
                      onLongPress: () async {
                        await showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          builder: (context) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.delete_outline),
                                  title: const Text('Sil'),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _turnuvaSil(league.id);
                                  },
                                ),
                                const SizedBox(height: 10),
                              ],
                            ),
                          ),
                        );
                      },
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

class _DialItem extends StatelessWidget {
  const _DialItem({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 10),
        FloatingActionButton.small(
          heroTag: label,
          onPressed: onPressed,
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          child: Icon(icon),
        ),
      ],
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
    _subtitleController =
        TextEditingController(text: widget.league.subtitle ?? '');
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
        subtitle: _subtitleController.text.trim().isEmpty
            ? null
            : _subtitleController.text.trim(),
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
