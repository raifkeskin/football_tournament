import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/approval_service.dart';

class AdminPendingActionsScreen extends StatefulWidget {
  const AdminPendingActionsScreen({super.key});

  @override
  State<AdminPendingActionsScreen> createState() =>
      _AdminPendingActionsScreenState();
}

class _AdminPendingActionsScreenState extends State<AdminPendingActionsScreen> {
  final _approval = ApprovalService();
  bool _busy = false;
  List<PendingAction> _actions = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _busy = true);
    try {
      final list = await _approval.fetchPendingActions();
      if (!mounted) return;
      setState(() => _actions = list);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _teamName(String? teamId) async {
    if (teamId == null || teamId.isEmpty) return '-';
    final snap = await FirebaseFirestore.instance
        .collection('teams')
        .doc(teamId)
        .get();
    final data = snap.data();
    return (data?['name'] as String?) ?? teamId;
  }

  Future<void> _approve(PendingAction action) async {
    setState(() => _busy = true);
    try {
      await _approval.approveAction(
        actionId: action.actionId,
        adminUserId: 'admin',
      );
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Onaylandı.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(PendingAction action) async {
    setState(() => _busy = true);
    try {
      await _approval.rejectAction(
        actionId: action.actionId,
        adminUserId: 'admin',
      );
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reddedildi.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bekleyen Onaylar'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _busy
          ? const LinearProgressIndicator()
          : _actions.isEmpty
          ? const Center(child: Text('Bekleyen işlem yok.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _actions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final a = _actions[index];
                final count = (a.payload['players'] is List)
                    ? (a.payload['players'] as List).length
                    : null;
                return Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          a.actionType,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        FutureBuilder<String>(
                          future: _teamName(a.teamId),
                          builder: (context, snap) =>
                              Text('Takım: ${snap.data ?? '-'}'),
                        ),
                        if (count != null) Text('Kayıt: $count'),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: _busy ? null : () => _approve(a),
                                child: const Text('Onayla'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.tonal(
                                onPressed: _busy ? null : () => _reject(a),
                                child: const Text('Reddet'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
