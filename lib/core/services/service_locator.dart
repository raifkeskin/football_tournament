import 'package:football_tournament/features/auth/services/auth_service.dart';
import 'package:football_tournament/features/tournament/services/firebase/league_service.dart';

import '../config/app_config.dart';
import '../../features/auth/services/interfaces/i_auth_service.dart';
import '../../features/tournament/services/interfaces/i_league_service.dart';
import '../../features/match/services/interfaces/i_match_service.dart';
import '../../features/team/services/interfaces/i_team_service.dart';
import '../../features/match/services/match_service.dart';
import '../../features/auth/services/supabase/supabase_auth_service.dart';
import '../../features/tournament/services/supabase/supabase_league_service.dart';
import '../../features/match/services/supabase/supabase_match_service.dart';
import '../../features/team/services/supabase/supabase_team_service.dart';
import '../../features/team/services/team_service.dart';

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
