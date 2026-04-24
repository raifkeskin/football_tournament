import '../config/app_config.dart';
import 'auth_service.dart';
import 'interfaces/i_auth_service.dart';
import 'interfaces/i_league_service.dart';
import 'interfaces/i_match_service.dart';
import 'interfaces/i_team_service.dart';
import 'league_service.dart';
import 'match_service.dart';
import 'supabase/supabase_auth_service.dart';
import 'supabase/supabase_league_service.dart';
import 'supabase/supabase_match_service.dart';
import 'supabase/supabase_team_service.dart';
import 'team_service.dart';

class ServiceLocator {
  static final IAuthService _firebaseAuthService = FirebaseAuthService();
  static final IAuthService _supabaseAuthService = SupabaseAuthService();

  static final ILeagueService _firebaseLeagueService = FirebaseLeagueService();
  static final ILeagueService _supabaseLeagueService = SupabaseLeagueService();

  static final IMatchService _firebaseMatchService = FirebaseMatchService();
  static final IMatchService _supabaseMatchService = SupabaseMatchService();

  static final ITeamService _firebaseTeamService = FirebaseTeamService();
  static final ITeamService _supabaseTeamService = SupabaseTeamService();

  static bool get _useSupabase => AppConfig.activeDatabase == DatabaseType.supabase;

  static IAuthService get authService => _useSupabase ? _supabaseAuthService : _firebaseAuthService;

  static ILeagueService get leagueService =>
      _useSupabase ? _supabaseLeagueService : _firebaseLeagueService;

  static IMatchService get matchService =>
      _useSupabase ? _supabaseMatchService : _firebaseMatchService;

  static ITeamService get teamService => _useSupabase ? _supabaseTeamService : _firebaseTeamService;
}
