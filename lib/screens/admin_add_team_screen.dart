import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/storage_service.dart';

/// Admin için takım ekleme formu.
class AdminAddTeamScreen extends StatefulWidget {
  const AdminAddTeamScreen({super.key});

  @override
  State<AdminAddTeamScreen> createState() => _AdminAddTeamScreenState();
}

class _AdminAddTeamScreenState extends State<AdminAddTeamScreen> {
  final _teamNameController = TextEditingController();
  final _picker = ImagePicker();
  final _storageService = StorageService();

  XFile? _teamLogo;

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
    if (_teamNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen takım adını girin.')),
      );
      return;
    }
    try {
      if (_teamLogo != null) {
        await _storageService.uploadTeamLogo(
          teamId: _teamNameController.text.trim().toLowerCase().replaceAll(
            ' ',
            '_',
          ),
          file: File(_teamLogo!.path),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Takım taslağı oluşturuldu (iskelet).')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Logo yükleme sırasında hata oluştu. Firebase bağlantısı kontrol edilmeli.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(title: const Text('Takım Ekle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _teamNameController,
            decoration: const InputDecoration(labelText: 'Takım Adı'),
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
              _teamLogo == null
                  ? 'Takım Logosu Seç (Galeri)'
                  : 'Seçildi: ${_teamLogo!.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _takimEkle,
            style: FilledButton.styleFrom(elevation: 0),
            child: const Text('Takım Ekle'),
          ),
        ],
      ),
    );
  }
}
