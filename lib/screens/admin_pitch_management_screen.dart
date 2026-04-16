import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/app_session.dart';
import '../utils/string_utils.dart';

class AdminPitchManagementScreen extends StatefulWidget {
  const AdminPitchManagementScreen({super.key});

  @override
  State<AdminPitchManagementScreen> createState() =>
      _AdminPitchManagementScreenState();
}

class _AdminPitchManagementScreenState extends State<AdminPitchManagementScreen> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _snack(String text, {Color? bg}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: bg),
    );
  }

  Future<void> _addPitch() async {
    final name = _nameController.text.trim();
    final location = _locationController.text.trim();
    if (name.isEmpty) {
      _snack('Saha adı boş olamaz.');
      return;
    }

    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance.collection('pitches').add({
        'name': name,
        'nameKey': StringUtils.normalizeTrKey(name),
        'location': location.isEmpty ? null : location,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      _nameController.clear();
      _locationController.clear();
      _snack(
        'Saha eklendi.',
        bg: Theme.of(context).colorScheme.primary,
      );
    } catch (e) {
      if (!mounted) return;
      _snack('Hata: $e', bg: Theme.of(context).colorScheme.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePitch(String pitchId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Saha Sil'),
        content: Text(
          "'$name' sahasını silmek istediğinize emin misiniz? Bu işlem geri alınamaz.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance.collection('pitches').doc(pitchId).delete();
      if (!mounted) return;
      _snack(
        'Saha silindi.',
        bg: Theme.of(context).colorScheme.primary,
      );
    } catch (e) {
      if (!mounted) return;
      _snack('Hata: $e', bg: Theme.of(context).colorScheme.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Saha Yönetimi')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: !isAdmin
          ? const Center(child: Text('Bu sayfa sadece adminler içindir.'))
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            TextField(
                              controller: _nameController,
                              enabled: !_busy,
                              decoration:
                                  const InputDecoration(labelText: 'Saha Adı'),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _locationController,
                              enabled: !_busy,
                              decoration:
                                  const InputDecoration(labelText: 'Konum'),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: _busy ? null : _addPitch,
                              icon: const Icon(Icons.add),
                              label: const Text('Ekle'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 48),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('pitches')
                          .orderBy('nameKey')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final docs = snapshot.data!.docs;
                        if (docs.isEmpty) {
                          return const Center(child: Text('Saha bulunamadı.'));
                        }
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: docs.length,
                            separatorBuilder: (context, index) =>
                                Divider(height: 1, color: cs.outlineVariant),
                            itemBuilder: (context, index) {
                              final d = docs[index];
                              final data = d.data() as Map<String, dynamic>;
                              final name =
                                  (data['name'] ?? '').toString().trim();
                              final location =
                                  (data['location'] ?? '').toString().trim();
                              return ListTile(
                                leading: const Icon(Icons.location_on_outlined),
                                title: Text(name.isEmpty ? d.id : name),
                                subtitle:
                                    location.isEmpty ? null : Text(location),
                                trailing: IconButton(
                                  onPressed:
                                      _busy ? null : () => _deletePitch(d.id, name),
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: cs.error,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
                if (_busy)
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

