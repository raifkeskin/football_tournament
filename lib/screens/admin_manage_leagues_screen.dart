import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/league.dart';
import '../services/app_session.dart';
import '../services/database_service.dart';
import '../services/image_upload_service.dart';

class AdminManageLeaguesScreen extends StatefulWidget {
  const AdminManageLeaguesScreen({super.key});

  @override
  State<AdminManageLeaguesScreen> createState() =>
      _AdminManageLeaguesScreenState();
}

class _AdminManageLeaguesScreenState extends State<AdminManageLeaguesScreen> {
  final _dbService = DatabaseService();
  final _imageUploadService = ImgBBUploadService();
  final _picker = ImagePicker();

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
      await _dbService.deleteLeagueCascade(leagueId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Turnuva silindi.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _openAddLeagueSheet() async {
    final leagueNameController = TextEditingController();
    final groupCountController = TextEditingController(text: '1');
    final teamsPerGroupController = TextEditingController(text: '4');
    final youtubeController = TextEditingController();
    final twitterController = TextEditingController();
    final instagramController = TextEditingController();

    DateTime? startDate;
    DateTime? endDate;
    XFile? leagueLogo;
    var saving = false;

    String tarihYaz(DateTime? date) {
      if (date == null) return 'Tarih seç';
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
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
        }
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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final viewInsets = MediaQuery.of(context).viewInsets;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> save() async {
              final name = leagueNameController.text.trim();
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
              try {
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
                  startDate: startDate,
                  endDate: endDate,
                  youtubeUrl: youtubeController.text.trim(),
                  twitterUrl: twitterController.text.trim(),
                  instagramUrl: instagramController.text.trim(),
                  groupCount: int.tryParse(groupCountController.text) ?? 1,
                  teamsPerGroup:
                      int.tryParse(teamsPerGroupController.text) ?? 4,
                );

                await _dbService.addLeague(league);
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Turnuva eklendi.')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Hata: $e')));
              } finally {
                if (context.mounted) setSheetState(() => saving = false);
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: saving
                              ? null
                              : () => tarihSec(
                                  isStart: true,
                                  setSheetState: setSheetState,
                                ),
                          icon: const Icon(Icons.event_outlined),
                          label: Text('Başlangıç: ${tarihYaz(startDate)}'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: saving
                              ? null
                              : () => tarihSec(
                                  isStart: false,
                                  setSheetState: setSheetState,
                                ),
                          icon: const Icon(Icons.event_available_outlined),
                          label: Text('Bitiş: ${tarihYaz(endDate)}'),
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
                    controller: twitterController,
                    decoration: const InputDecoration(
                      labelText: 'Twitter (X) Linki',
                      prefixIcon: Icon(Icons.alternate_email),
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
                          ? 'Logo Seç (Galeri)'
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
                            icon: const Icon(Icons.add),
                            label: const Text('Ekle'),
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
    groupCountController.dispose();
    teamsPerGroupController.dispose();
    youtubeController.dispose();
    twitterController.dispose();
    instagramController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Turnuva Yönetimi')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: _openAddLeagueSheet,
              child: const Icon(Icons.add),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 4),
          Text(
            'Turnuvalar',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: _dbService.getLeagues(),
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final leagues = snapshot.data!.docs
                  .map(
                    (doc) => League.fromMap({
                      ...doc.data() as Map<String, dynamic>,
                      'id': doc.id,
                    }),
                  )
                  .toList();

              if (leagues.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Turnuva bulunamadı.')),
                );
              }

              return Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: leagues.length,
                  separatorBuilder: (context, index) =>
                      Divider(color: Colors.grey.shade300, height: 1),
                  itemBuilder: (context, index) {
                    final league = leagues[index];
                    return ListTile(
                      leading: league.logoUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                league.logoUrl,
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Icon(Icons.emoji_events),
                      title: Text(league.name, maxLines: 3, softWrap: true),
                      subtitle: Text(league.country),
                      trailing: SizedBox(
                        width: 88,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Switch.adaptive(
                              value: league.isDefault,
                              onChanged: !isAdmin || league.isDefault
                                  ? null
                                  : (_) async {
                                      try {
                                        await _dbService.setDefaultLeague(
                                          leagueId: league.id,
                                        );
                                      } catch (e) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Hata: $e')),
                                        );
                                      }
                                    },
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              league.isDefault
                                  ? Icons.star_rounded
                                  : Icons.chevron_right,
                              color: league.isDefault ? cs.primary : null,
                            ),
                          ],
                        ),
                      ),
                      onTap: () async {
                        if (!isAdmin) return;
                        await showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          builder: (context) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.edit_outlined),
                                  title: const Text('Düzenle'),
                                  onTap: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            EditLeagueScreen(league: league),
                                      ),
                                    );
                                  },
                                ),
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
                    );
                  },
                ),
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
  late TextEditingController _ytController;
  late TextEditingController _xController;
  late TextEditingController _igController;
  XFile? _newLogo;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.league.name);
    _subtitleController =
        TextEditingController(text: widget.league.subtitle ?? '');
    _ytController = TextEditingController(text: widget.league.youtubeUrl);
    _xController = TextEditingController(text: widget.league.twitterUrl);
    _igController = TextEditingController(text: widget.league.instagramUrl);
  }

  Future<void> _update() async {
    setState(() => _isLoading = true);
    try {
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
        name: _nameController.text.trim(),
        subtitle: _subtitleController.text.trim().isEmpty
            ? null
            : _subtitleController.text.trim(),
        logoUrl: logoUrl,
        country: widget.league.country,
        startDate: widget.league.startDate,
        endDate: widget.league.endDate,
        isDefault: widget.league.isDefault,
        youtubeUrl: _ytController.text.trim(),
        twitterUrl: _xController.text.trim(),
        instagramUrl: _igController.text.trim(),
      );

      await DatabaseService().updateLeague(updatedLeague);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Güncellendi')));
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Logo Düzenleme
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundImage: _newLogo != null
                            ? FileImage(File(_newLogo!.path)) as ImageProvider
                            : (widget.league.logoUrl.isNotEmpty
                                  ? NetworkImage(widget.league.logoUrl)
                                  : null),
                        child:
                            (_newLogo == null && widget.league.logoUrl.isEmpty)
                            ? const Icon(Icons.emoji_events, size: 40)
                            : null,
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
                TextField(
                  controller: _ytController,
                  decoration: const InputDecoration(
                    labelText: 'YouTube',
                    prefixIcon: Icon(Icons.play_circle_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _xController,
                  decoration: const InputDecoration(
                    labelText: 'Twitter (X)',
                    prefixIcon: Icon(Icons.alternate_email),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _igController,
                  decoration: const InputDecoration(
                    labelText: 'Instagram',
                    prefixIcon: Icon(Icons.camera_alt_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _update,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('Bilgileri Güncelle'),
                ),
              ],
            ),
    );
  }
}
