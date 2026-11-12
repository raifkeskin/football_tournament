-- Oyuncu kartındaki kalem: kimliği hiç onaylanmamış (çip/ibraz yok)
-- futbolcu kendi ad/soyad/doğum tarihini de düzenleyebilir.
create or replace function public.can_edit_player_basic(p_player uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select auth.uid() is not null
     and not exists (select 1 from public.player_verifications v where v.player_id = p_player)
     and (
       public.is_admin()
       or exists (select 1 from public.players pl
                   where pl.id = p_player and pl.auth_uid = auth.uid())
       or exists (
         select 1 from public.season_team_players stp
           join public.seasons s on s.id = stp.season_id
          where stp.player_id = p_player
            and (public.owns_league(s.league_id)
                 or exists (select 1 from public.region_owners ro
                              join public.season_regions sr on sr.id = ro.region_id
                             where sr.season_id = s.id and ro.user_id = auth.uid())))
     )
$function$;
