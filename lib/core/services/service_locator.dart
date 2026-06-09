import '../../features/auth/services/interfaces/i_auth_service.dart';
import '../../features/tournament/services/interfaces/i_league_service.dart';
import '../../features/match/services/interfaces/i_match_service.dart';
import '../../features/team/services/interfaces/i_team_service.dart';
import '../../features/auth/services/supabase/supabase_auth_service.dart';
import '../../features/tournament/services/supabase/supabase_league_service.dart';
import '../../features/match/services/supabase/supabase_match_service.dart';
import '../../features/team/services/supabase/supabase_team_service.dart';

class ServiceLocator {
  static final IAuthService _supabaseAuthService = SupabaseAuthService();
  static final ILeagueService _supabaseLeagueService = SupabaseLeagueService();
  static final IMatchService _supabaseMatchService = SupabaseMatchService();
  static final ITeamService _supabaseTeamService = SupabaseTeamService();

  static IAuthService get authService => _supabaseAuthService;
  static ILeagueService get leagueService => _supabaseLeagueService;
  static IMatchService get matchService => _supabaseMatchService;
  static ITeamService get teamService => _supabaseTeamService;
}
