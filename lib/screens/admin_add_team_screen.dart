import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/league.dart';
import '../repositories/teams_repository.dart';
import '../services/app_session.dart';
import '../services/image_upload_service.dart';
import '../services/interfaces/i_league_service.dart';
import '../services/service_locator.dart';

/// Admin için takım ekleme formu.
class AdminAddTeamScreen extends StatefulWidget {
  const AdminAddTeamScreen({super.key});

  @override
  State<AdminAddTeamScreen> createState() => _AdminAddTeamScreenState();
}

class _AdminAddTeamScreenState extends State<AdminAddTeamScreen> {
  final _teamNameController = TextEditingController();
  final _picker = ImagePicker();
  final _imageUploadService = ImgBBUploadService();
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final _teamsRepo = TeamsRepository();

  XFile? _teamLogo;
  String? _selectedLeagueId;
  bool _isLoading = false;

  @override
  void dispose() {
    _teamNameController.dispose();
    super.dispose();
  }

  Future<void> _logoSec() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _teamLogo = picked);
  }

  Future<void> _takimEkle() async {
    final teamName = _teamNameController.text.trim();

    if (teamName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen takım adını girin.')),
      );
      return;
    }

    if (_selectedLeagueId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lütfen bir lig seçin.')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      String logoUrl = '';
      if (_teamLogo != null) {
        final uploadedUrl = await _imageUploadService.uploadImage(
          File(_teamLogo!.path),
        );
        if (uploadedUrl != null) {
          logoUrl = uploadedUrl;
        } else {
          throw Exception('Logo yüklenemedi, lütfen tekrar deneyin.');
        }
      }

      await _teamsRepo.addTeamAndUpsertCache(
        leagueId: _selectedLeagueId!,
        teamName: teamName,
        logoUrl: logoUrl,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Takım başarıyla kaydedildi.'),
          backgroundColor: Colors.green,
        ),
      );

      // Formu temizle
      setState(() {
        _teamNameController.clear();
        _teamLogo = null;
        _selectedLeagueId = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata oluştu: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Takım Ekle')),
        body: const Center(
          child: Text(
            'Bu sayfaya erişim yetkiniz yok.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Takım Ekle')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                StreamBuilder<List<League>>(
                  stream: _leagueService.watchLeagues(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Text('Hata: ${snapshot.error}');
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final leagues = snapshot.data ?? const <League>[];
                    if (leagues.isEmpty) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'Henüz bir turnuva eklenmemiş. Önce bir turnuva eklemelisiniz.',
                            style: TextStyle(color: Colors.orange),
                          ),
                        ),
                      );
                    }
                    return DropdownButtonFormField<String>(
                      initialValue: _selectedLeagueId,
                      decoration: const InputDecoration(labelText: 'Turnuva Seçin'),
                      items: leagues.map((doc) {
                        return DropdownMenuItem<String>(
                          value: doc.id,
                          child: Text(doc.name),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setState(() => _selectedLeagueId = val),
                    );
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _teamNameController,
                  decoration: const InputDecoration(labelText: 'Takım Adı'),
                ),
                const SizedBox(height: 16),
                if (_teamLogo != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(_teamLogo!.path),
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _logoSec,
                  style: OutlinedButton.styleFrom(
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    side: BorderSide(color: cs.outlineVariant),
                  ),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    _teamLogo == null
                        ? 'Takım Logosu Seç (Galeri)'
                        : 'Seçildi: ${_teamLogo!.name}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: _takimEkle,
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Takımı Kaydet'),
                ),
              ],
            ),
    );
  }
}
