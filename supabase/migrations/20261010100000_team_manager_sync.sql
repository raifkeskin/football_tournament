-- Takım sorumlusu tek kaynaktan: Takım Yönetimi'nde seçilen sorumlu
-- (teams.manager_id = players.id) yetki tablosuna (team_managers: giriş
-- hesabı × takımın sezonları) otomatik yansır. Önceden popup yalnız
-- teams.manager_id yazıyor, yetkiler team_managers'tan okunuyordu; hiçbir
-- sorumlu esame giremiyordu.

-- Bir takımın yetki satırlarını sorumlusuna göre yeniden kurar.
create or replace function public.sync_team_managers(p_team_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid;
begin
  select p.auth_uid into v_uid
  from public.teams t
  join public.players p on p.id = t.manager_id
  where t.id = p_team_id;

  -- Sorumlu değiştiyse / kaldırıldıysa eski hesapların yetkisi düşer.
  delete from public.team_managers tm
  where tm.team_id = p_team_id
    and (v_uid is null or tm.user_id <> v_uid);

  if v_uid is not null then
    insert into public.team_managers (season_id, team_id, user_id)
    select st.season_id, p_team_id, v_uid
    from public.season_teams st
    where st.team_id = p_team_id
    on conflict do nothing;
  end if;
end;
$$;

-- Sorumlu seçilince / değişince.
create or replace function public.trg_teams_manager_sync()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform public.sync_team_managers(new.id);
  return new;
end;
$$;

drop trigger if exists teams_manager_sync on public.teams;
create trigger teams_manager_sync
  after insert or update of manager_id on public.teams
  for each row execute function public.trg_teams_manager_sync();

-- Takım bir sezona eklenince / sezondan çıkınca.
create or replace function public.trg_season_teams_manager_sync()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if tg_op = 'DELETE' then
    delete from public.team_managers
    where team_id = old.team_id and season_id = old.season_id;
    return old;
  end if;
  perform public.sync_team_managers(new.team_id);
  return new;
end;
$$;

drop trigger if exists season_teams_manager_sync on public.season_teams;
create trigger season_teams_manager_sync
  after insert or delete on public.season_teams
  for each row execute function public.trg_season_teams_manager_sync();

-- Sorumlu olan futbolcu sonradan hesap açınca / hesabı eşleşince.
create or replace function public.trg_players_manager_sync()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  r record;
begin
  for r in select id from public.teams where manager_id = new.id loop
    perform public.sync_team_managers(r.id);
  end loop;
  return new;
end;
$$;

drop trigger if exists players_manager_sync on public.players;
create trigger players_manager_sync
  after update of auth_uid on public.players
  for each row
  when (old.auth_uid is distinct from new.auth_uid)
  execute function public.trg_players_manager_sync();

-- Kadro yetkisi: teams.manager_id bir futbolcu kimliği; giriş hesabıyla
-- futbolcunun auth_uid'si üzerinden karşılaştırılır (önceden doğrudan
-- auth.uid() ile karşılaştırılıyordu ve hiç eşleşmiyordu).
create or replace function public.can_edit_match_roster(
  p_match_id uuid,
  p_team_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.can_manage_match(p_match_id) or exists (
    select 1 from public.matches m
    where m.id = p_match_id
      and p_team_id in (m.home_team_id, m.away_team_id)
      and m.status <> 'finished'
      and (public.manages_team(m.season_id, p_team_id)
           or exists (select 1 from public.teams t
                      join public.players p on p.id = t.manager_id
                      where t.id = p_team_id and p.auth_uid = auth.uid()))
      and now() >= public.match_roster_open_at(m.id)
  )
$$;

-- Mevcut sorumluların yetkileri bir kez kurulur.
do $$
declare
  r record;
begin
  for r in select id from public.teams where manager_id is not null loop
    perform public.sync_team_managers(r.id);
  end loop;
end;
$$;
