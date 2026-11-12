-- Telefon zaten kayıtlıysa sahibinin kimliğini (telefon dışında) gösterir.
create or replace function public.player_phone_owner(p_phone text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when auth.uid() is null then null else (
    select jsonb_build_object(
      'name', trim(p.name || ' ' || coalesce(p.surname, '')),
      'birth_date', p.birth_date,
      'teams', coalesce((select jsonb_agg(distinct t.name)
         from public.season_team_players s join public.teams t on t.id = s.team_id
         where s.player_id = p.id), '[]'::jsonb))
    from public.players p
    where p.phone = regexp_replace(coalesce(p_phone, ''), '\D', '', 'g')
    limit 1) end
$$;
revoke all on function public.player_phone_owner(text) from public, anon;
grant execute on function public.player_phone_owner(text) to authenticated;
