import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../match/models/match.dart';

class PlayerService {
  PlayerService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Stream<List<PlayerModel>> watchAllFootballers({String? caller}) {
    if (AppConfig.activeDatabase != DatabaseType.supabase) {
      return const Stream<List<PlayerModel>>.empty();
    }
    try {
      return _client
          .from('players')
          .stream(primaryKey: ['id'])
          .inFilter('role', const ['Futbolcu', 'Her İkisi'])
          .order('name', ascending: true)
          .map((rows) {
            final list = <PlayerModel>[];
            for (final r in rows) {
              final row = Map<String, dynamic>.from(r);
              final id = (row['id'] ?? row['phone'] ?? '').toString().trim();
              if (id.isEmpty) continue;
              list.add(PlayerModel.fromMap(row, id));
            }
            list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
            return list;
          });
    } catch (_) {
      return const Stream<List<PlayerModel>>.empty();
    }
  }

  Future<void> createFootballer({
    required String fullName,
    required String phoneRaw10,
  }) async {
    if (AppConfig.activeDatabase != DatabaseType.supabase) {
      throw Exception('Bu işlem bu veritabanı modunda desteklenmiyor.');
    }
    final name = fullName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) throw Exception('İsim boş olamaz.');
    final phone = phoneRaw10.replaceAll(RegExp(r'\D'), '');
    if (phone.isEmpty) throw Exception('Telefon boş olamaz.');

    final nowIso = DateTime.now().toIso8601String();
    final payload = <String, dynamic>{
      'name': name,
      'role': 'Futbolcu',
      'phone': phone,
      'phone_raw10': phone,
      'team_id': 'free_agent_pool',
      'created_at': nowIso,
      'updated_at': nowIso,
    };

    Future<void> doInsert(Map<String, dynamic> p) async {
      await _client.from('players').insert(p);
    }

    try {
      await doInsert(payload);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST204') {
        final p = Map<String, dynamic>.from(payload);
        p.remove('phone_raw10');
        await doInsert(p);
      } else {
        rethrow;
      }
    }
  }
}
