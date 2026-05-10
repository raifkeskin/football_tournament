import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:football_tournament/core/config/app_config.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  });

  test('Direct query test', () async {
    try {
      final res = await Supabase.instance.client
          .from('season_team_players')
          .select('player_id, jersey_number')
          .limit(1);
      print('First query success: $res');
    } catch (e) {
      print('Exception first query: $e');
    }
  });
}