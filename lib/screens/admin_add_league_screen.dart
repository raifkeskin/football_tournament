import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/storage_service.dart';

/// Admin için turnuva ekleme formu.
class AdminAddLeagueScreen extends StatefulWidget {
  const AdminAddLeagueScreen({super.key});

  @override
  State<AdminAddLeagueScreen> createState() => _AdminAddLeagueScreenState();
}

class _AdminAddLeagueScreenState extends State<AdminAddLeagueScreen> {
  final _leagueNameController = TextEditingController();
  final _leagueCountryController = TextEditingController();
  final _picker = ImagePicker();
  final _storageService = StorageService();

  XFile? _leagueLogo;

  @override
  void dispose() {
    _leagueNameController.dispose();
    _leagueCountryController.dispose();
    super.dispose();
  }

  Future<void> _logoSec() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _leagueLogo = picked);
  }

  Future<void> _turnuvaEkle() async {
    if (_leagueLogo != null && _leagueNameController.text.trim().isNotEmpty) {
      await _storageService.uploadLeagueLogo(
        leagueId: _leagueNameController.text.trim().toLowerCase().replaceAll(
          ' ',
          '_',
        ),
        file: File(_leagueLogo!.path),
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Turnuva taslağı oluşturuldu (iskelet).')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(title: const Text('Turnuva Ekle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _leagueNameController,
            decoration: const InputDecoration(labelText: 'Turnuva Adı'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _leagueCountryController,
            decoration: const InputDecoration(labelText: 'Ülke'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _logoSec,
            style: OutlinedButton.styleFrom(
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              side: BorderSide(color: cs.outlineVariant),
            ),
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(
              _leagueLogo == null
                  ? 'Turnuva Logosu Seç (Galeri)'
                  : 'Seçildi: ${_leagueLogo!.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _turnuvaEkle,
            style: FilledButton.styleFrom(elevation: 0),
            child: const Text('Turnuva Ekle'),
          ),
        ],
      ),
    );
  }
}
