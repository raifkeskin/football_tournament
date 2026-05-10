import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:football_tournament/core/config/app_config.dart';
import 'package:football_tournament/features/team/services/supabase/supabase_team_service.dart';

void main() {
  group('Roster Fetch Test', () {
    late SupabaseClient client;
    late SupabaseTeamService teamService;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
      client = Supabase.instance.client;
      teamService = SupabaseTeamService();
    });

    test('getEligiblePlayers fetches data correctly', () async {
      // Bilinen test ID'leri. DB'nizde gerçekten 18 oyuncu varsa bu test geçecektir.
      // Eğer bu test ID'leri boş geliyorsa, veritabanından dinamik bir ID bulmalıyız.
      final teamsRes = await client.from('season_team_players').select('team_id, season_id').limit(1);
      
      if ((teamsRes as List).isEmpty) {
        // DB boşsa test anlamsız olur, atla.
        return;
      }
      
      final row = teamsRes.first;
      final testTeamId = row['team_id'];
      final testSeasonId = row['season_id'];
      
      final players = await teamService.getEligiblePlayers(testTeamId, testSeasonId);
      // Veritabanındaki "Her takımda 18 oyuncu var" varsayımına göre test:
      expect(players.length, 18, reason: 'Supabase inner join sorgusu tam olarak 18 oyuncu döndürmeli.');
    });
  });
}