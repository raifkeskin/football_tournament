import 'package:flutter/material.dart';

import '../models/league.dart';
import '../models/league_extras.dart';
import '../services/app_session.dart';
import '../services/database_service.dart';
import '../services/interfaces/i_league_service.dart';
import '../services/service_locator.dart';

class AdminManageNewsScreen extends StatefulWidget {
  const AdminManageNewsScreen({super.key});

  @override
  State<AdminManageNewsScreen> createState() => _AdminManageNewsScreenState();
}

class _AdminManageNewsScreenState extends State<AdminManageNewsScreen> {
  final _dbService = DatabaseService();
  final ILeagueService _leagueService = ServiceLocator.leagueService;
  final Set<String> _busyIds = {};
  String? _selectedTournamentId;

  String _tarihYaz(DateTime? createdAt) {
    final d = createdAt;
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  Future<void> _toggle(String newsId, bool next) async {
    setState(() => _busyIds.add(newsId));
    try {
      await _dbService.setNewsPublished(newsId: newsId, isPublished: next);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _busyIds.remove(newsId));
    }
  }

  Future<void> _editNews(String newsId, String initialText) async {
    final controller = TextEditingController(text: initialText);
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> save() async {
            final text = controller.text.trim();
            if (text.isEmpty) return;
            setDialogState(() => saving = true);
            setState(() => _busyIds.add(newsId));
            try {
              await _dbService.updateNewsContent(newsId: newsId, content: text);
              if (!context.mounted) return;
              Navigator.pop(context);
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Hata: $e')));
            } finally {
              if (context.mounted) setDialogState(() => saving = false);
              if (mounted) setState(() => _busyIds.remove(newsId));
            }
          }

          return AlertDialog(
            title: const Text('Haberi Düzenle'),
            content: TextField(
              controller: controller,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Haber Metni'),
              enabled: !saving,
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              FilledButton(
                onPressed: saving ? null : save,
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

    controller.dispose();
  }

  Future<void> _deleteNews(String newsId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Haberi Sil'),
        content: const Text('Bu haber silinecek. Devam edilsin mi?'),
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

    setState(() => _busyIds.add(newsId));
    try {
      await _dbService.deleteNews(newsId: newsId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _busyIds.remove(newsId));
    }
  }

  Future<void> _openAddNewsDialog() async {
    final controller = TextEditingController();
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> save() async {
            final tId = (_selectedTournamentId ?? '').trim();
            if (tId.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Lütfen önce turnuva seçin.')),
              );
              return;
            }
            final text = controller.text.trim();
            if (text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Lütfen bir haber metni girin.')),
              );
              return;
            }
            setDialogState(() => saving = true);
            try {
              await _dbService.addNews(tournamentId: tId, content: text);
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(
                this.context,
              ).showSnackBar(const SnackBar(content: Text('Haber eklendi.')));
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Hata: $e')));
            } finally {
              if (context.mounted) setDialogState(() => saving = false);
            }
          }

          return AlertDialog(
            title: const Text('Haber Ekle'),
            content: TextField(
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Haber Metni'),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('İptal'),
              ),
              FilledButton(
                onPressed: saving ? null : save,
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

    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.of(context).value.isAdmin;
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Haber Yönetimi')),
        body: const Center(
          child: Text(
            'Bu sayfaya erişim yetkiniz yok.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Haber Yönetimi')),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: _openAddNewsDialog,
              child: const Icon(Icons.add),
            )
          : null,
      body: StreamBuilder<List<League>>(
        stream: _leagueService.watchLeagues(),
        builder: (context, tSnap) {
          if (!tSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final tournaments = tSnap.data ?? const <League>[];
          if (tournaments.isEmpty) {
            return const Center(child: Text('Turnuva bulunamadı.'));
          }
          _selectedTournamentId ??= tournaments.first.id;
          final tId = (_selectedTournamentId ?? '').trim();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: DropdownButtonFormField<String>(
                  initialValue: tId.isEmpty ? tournaments.first.id : tId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Turnuva',
                    border: OutlineInputBorder(),
                  ),
                  items: tournaments
                      .map(
                        (l) => DropdownMenuItem<String>(
                          value: l.id,
                          child: Text(
                            l.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedTournamentId = v),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: StreamBuilder<List<NewsItem>>(
                  stream: tId.isEmpty
                      ? const Stream.empty()
                      : _leagueService.watchNews(
                          tournamentId: tId,
                          includeUnpublished: true,
                        ),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data ?? const <NewsItem>[];
                    if (docs.isEmpty) {
                      return const Center(child: Text('Kayıtlı haber bulunamadı.'));
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: docs.length,
                      separatorBuilder: (context, index) =>
                          Divider(color: Colors.grey.shade300, height: 1),
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final content = doc.content;
                        final isPublished = doc.isPublished;
                        final createdAtText = _tarihYaz(doc.createdAt);
                        final busy = _busyIds.contains(doc.id);

                        return Card(
                          child: ListTile(
                            enabled: isAdmin && !busy,
                            title: Text(
                              content,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: createdAtText.isEmpty
                                ? Text(isPublished ? 'Yayında' : 'Kapalı')
                                : Text(
                                    '$createdAtText • ${isPublished ? 'Yayında' : 'Kapalı'}',
                                  ),
                            trailing: busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.chevron_right),
                            onTap: !isAdmin || busy
                                ? null
                                : () async {
                                    await showModalBottomSheet<void>(
                                      context: context,
                                      showDragHandle: true,
                                      builder: (context) => SafeArea(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ListTile(
                                              leading: Icon(
                                                isPublished
                                                    ? Icons.visibility_off_outlined
                                                    : Icons.visibility_outlined,
                                              ),
                                              title: Text(
                                                isPublished ? 'Yayından Kaldır' : 'Yayınla',
                                              ),
                                              onTap: () {
                                                Navigator.pop(context);
                                                _toggle(doc.id, !isPublished);
                                              },
                                            ),
                                            ListTile(
                                              leading: const Icon(Icons.edit_outlined),
                                              title: const Text('Düzenle'),
                                              onTap: () {
                                                Navigator.pop(context);
                                                _editNews(doc.id, content);
                                              },
                                            ),
                                            ListTile(
                                              leading: const Icon(Icons.delete_outline),
                                              title: const Text('Sil'),
                                              onTap: () {
                                                Navigator.pop(context);
                                                _deleteNews(doc.id);
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
              ),
            ],
          );
        },
      ),
    );
  }
}
