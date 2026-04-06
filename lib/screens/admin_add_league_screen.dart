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
  final _picker = ImagePicker();
  final _storageService = StorageService();

  XFile? _leagueLogo;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void dispose() {
    _leagueNameController.dispose();
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

  Future<void> _tarihSec({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart
          ? (_startDate ?? now)
          : (_endDate ?? _startDate ?? now),
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
      }
    });
  }

  String _tarihYaz(DateTime? date) {
    if (date == null) return 'Tarih seç';
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  Future<void> _turnuvaEkle() async {
    if (_leagueNameController.text.trim().isEmpty ||
        _startDate == null ||
        _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Lütfen turnuva adı, başlangıç ve bitiş tarihini girin.',
          ),
        ),
      );
      return;
    }

    try {
      if (_leagueLogo != null) {
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
      appBar: AppBar(title: const Text('Turnuva Ekle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _leagueNameController,
            decoration: const InputDecoration(labelText: 'Turnuva Adı'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _tarihSec(isStart: true),
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Başlangıç: ${_tarihYaz(_startDate)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _tarihSec(isStart: false),
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text('Bitiş: ${_tarihYaz(_endDate)}'),
                ),
              ),
            ],
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
