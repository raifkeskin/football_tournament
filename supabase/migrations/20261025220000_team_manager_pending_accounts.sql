-- Takım listesi: sorumlusu henüz hesap açmamış takımlar ("Hesap bekliyor").
-- auth.users istemciden okunamadığı için RPC; yalnız yönetilebilen takımlar.
create or replace function public.team_manager_pending_accounts()
returns setof uuid
language sql
stable
security definer
set search_path to ''
as $$
  select c.team_id
  from public.team_manager_contacts c
  join public.teams t on t.id = c.team_id
  left join public.players p on p.id = t.manager_id
  where public.owns_team(c.team_id)
    and p.auth_uid is null
    and public.account_uid_for_phone(c.phone_raw10) is null;
$$;
revoke all on function public.team_manager_pending_accounts() from public, anon;
grant execute on function public.team_manager_pending_accounts() to authenticated;
