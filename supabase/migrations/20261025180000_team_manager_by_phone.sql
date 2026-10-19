-- Takım sorumlusu telefonla atanır (not 24). Sorumlu futbolcu listesinde
-- olmayan biri de olabilir (ör. teknik sorumlu).
--
-- * teams.manager_phone (10 hane) + teams.manager_name: atanan kişi.
--   Telefon bir futbolcu kaydıyla eşleşirse manager_id o futbolcu olur ve
--   ad soyad futbolcudan gelir; eşleşmezse manager_id boş kalır, ad elle
--   girilir.
-- * Eski derlemeler yalnız manager_id yazar (futbolcu seçici); o durumda
--   telefon ve ad futbolcudan doldurulur.
-- * Yetki (team_managers) futbolcunun hesabından, yoksa telefonun
--   hesabından kurulur; hesap sonradan açılınca kendiliğinden bağlanır.
-- * lookup_person_by_phone: formda telefon yazılınca ad soyadı getirir.

alter table public.teams
  add column if not exists manager_phone text
    check (manager_phone is null or manager_phone ~ '^5[0-9]{9}$'),
  add column if not exists manager_name text;

create index if not exists teams_manager_phone_idx
  on public.teams (manager_phone) where manager_phone is not null;

-- Telefona kayıtlı kişinin adı: futbolcu kaydı, hesap, sahip/sorumlu
-- davetleri sırasıyla. Bulunamazsa null.
create or replace function public.person_name_for_phone(p_raw10 text)
returns table (full_name text, player_id uuid)
language sql
stable
security definer
set search_path to ''
as $$
  select n, pid from (
    select trim(concat_ws(' ', nullif(trim(p.name), ''), nullif(trim(p.surname), ''))) as n,
           p.id as pid, 1 as prio, (p.auth_uid is null)::int as sub
    from public.players p
    where public.phone_raw10(p.phone) = p_raw10
    union all
    select coalesce(nullif(trim(u.display_name), ''), nullif(trim(u.name), '')),
           null::uuid, 2, 0
    from public.app_users u
    where public.phone_raw10(u.phone) = p_raw10
    union all
    select trim(i.full_name), null::uuid, 3, 0
    from public.league_owner_invites i where i.phone_raw10 = p_raw10
    union all
    select trim(i.full_name), null::uuid, 3, 0
    from public.region_owner_invites i where i.phone_raw10 = p_raw10
  ) s
  where coalesce(n, '') <> ''
  order by prio, sub, pid
  limit 1
$$;
revoke all on function public.person_name_for_phone(text) from public, anon, authenticated;

-- Form için: telefon → ad soyad. Yalnız takım ekleyebilenler (admin,
-- kurucu başkan, bölge sorumlusu).
create or replace function public.lookup_person_by_phone(p_phone text)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_raw text := public.phone_raw10(p_phone);
  v_name text;
  v_pid uuid;
begin
  if not (public.is_admin() or public.is_any_league_owner()
          or public.is_any_region_owner()) then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    return null;
  end if;
  select full_name, player_id into v_name, v_pid
  from public.person_name_for_phone(v_raw);
  if v_name is null then
    return null;
  end if;
  return jsonb_build_object('name', v_name, 'is_player', v_pid is not null);
end;
$$;
revoke all on function public.lookup_person_by_phone(text) from public, anon;
grant execute on function public.lookup_person_by_phone(text) to authenticated;

-- Kayıt öncesi: telefon ↔ futbolcu ↔ ad tutarlı tutulur.
create or replace function public.trg_teams_manager_fill()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_found text;
  v_phone_path boolean;
begin
  if tg_op = 'INSERT' then
    v_phone_path := new.manager_phone is not null or new.manager_id is null;
  else
    v_phone_path := new.manager_phone is distinct from old.manager_phone
                    or new.manager_name is distinct from old.manager_name;
    if not v_phone_path and new.manager_id is not distinct from old.manager_id then
      return new;
    end if;
  end if;

  if v_phone_path then
    new.manager_phone := public.phone_raw10(nullif(trim(coalesce(new.manager_phone, '')), ''));
    if new.manager_phone is null then
      new.manager_id := null;
      new.manager_name := null;
      return new;
    end if;
    if new.manager_phone !~ '^5[0-9]{9}$' then
      raise exception 'Geçerli bir cep telefonu girin (5XX XXX XX XX).';
    end if;
    -- Seçili futbolcu bu telefondaysa korunur (aynı telefonda birden çok
    -- kayıt olabilir); değilse telefonla eşleşen futbolcu aranır.
    if new.manager_id is null or not exists (
      select 1 from public.players p
      where p.id = new.manager_id and public.phone_raw10(p.phone) = new.manager_phone
    ) then
      select p.id into new.manager_id from public.players p
      where public.phone_raw10(p.phone) = new.manager_phone
      order by (p.auth_uid is null), p.id limit 1;
    end if;
    select full_name into v_found from public.person_name_for_phone(new.manager_phone);
    new.manager_name := left(coalesce(v_found, nullif(trim(coalesce(new.manager_name, '')), '')), 80);
    if new.manager_name is null then
      raise exception 'Takım sorumlusunun ad soyadını girin.';
    end if;
  else
    -- Eski derleme: yalnız futbolcu seçildi.
    if new.manager_id is null then
      new.manager_phone := null;
      new.manager_name := null;
    else
      select public.phone_raw10(p.phone),
             trim(concat_ws(' ', nullif(trim(p.name), ''), nullif(trim(p.surname), '')))
        into new.manager_phone, new.manager_name
      from public.players p where p.id = new.manager_id;
      if new.manager_phone !~ '^5[0-9]{9}$' then
        new.manager_phone := null;
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists teams_manager_fill on public.teams;
create trigger teams_manager_fill
  before insert or update on public.teams
  for each row execute function public.trg_teams_manager_fill();

-- Yetki: futbolcunun hesabı, yoksa telefonun hesabı.
create or replace function public.sync_team_managers(p_team_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid;
  v_phone text;
begin
  select p.auth_uid, t.manager_phone into v_uid, v_phone
  from public.teams t
  left join public.players p on p.id = t.manager_id
  where t.id = p_team_id;

  if v_uid is null and v_phone is not null then
    v_uid := public.account_uid_for_phone(v_phone);
  end if;

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

drop trigger if exists teams_manager_sync on public.teams;
create trigger teams_manager_sync
  after insert or update of manager_id, manager_phone on public.teams
  for each row execute function public.trg_teams_manager_sync();

-- Futbolcu olmayan sorumlu hesap açınca yetkisi bağlanır; panelde adı
-- görünsün diye app_users kaydı da açılır.
create or replace function public.on_auth_user_created_link_team_manager()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_raw text := split_part(coalesce(new.email, ''), '@', 1);
  v_name text;
  r record;
begin
  if v_raw !~ '^5[0-9]{9}$' then
    return new;
  end if;
  for r in select id, manager_name from public.teams where manager_phone = v_raw loop
    perform public.sync_team_managers(r.id);
    v_name := coalesce(v_name, r.manager_name);
  end loop;
  if v_name is not null then
    insert into public.app_users (phone, name, auth_uid, role)
    values (v_raw, v_name, new.id::text, 'player')
    on conflict (phone) do update
      set auth_uid = excluded.auth_uid,
          name = coalesce(public.app_users.name, excluded.name);
  end if;
  return new;
end;
$$;

drop trigger if exists link_team_manager_on_signup on auth.users;
create trigger link_team_manager_on_signup
  after insert on auth.users
  for each row execute function public.on_auth_user_created_link_team_manager();

-- Kayıt talebi: futbolcu olmayan takım sorumlusu da kayıt olabilir.
create or replace function public.request_account_password(
  p_phone text,
  p_full_name text default null,
  p_reset boolean default false
)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_raw text := public.phone_raw10(p_phone);
  v_name text := nullif(trim(coalesce(p_full_name, '')), '');
  v_has_account boolean;
  v_kind text;
begin
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    return 'invalid_phone';
  end if;

  select exists (
    select 1 from auth.users where email = v_raw || '@masterclass.com'
  ) into v_has_account;

  if p_reset and not v_has_account then
    return 'not_registered';
  end if;

  if not v_has_account
     and not exists (
       select 1 from public.players p where public.phone_raw10(p.phone) = v_raw
     )
     and not exists (
       select 1 from public.league_owner_invites i where i.phone_raw10 = v_raw
     )
     and not exists (
       select 1 from public.region_owner_invites i where i.phone_raw10 = v_raw
     )
     and not exists (
       select 1 from public.teams t where t.manager_phone = v_raw
     ) then
    return 'unknown_phone';
  end if;

  -- Davetli sahibin / sorumlunun adı talepte görünsün.
  if v_name is null then
    select full_name into v_name from (
      select full_name, created_at from public.league_owner_invites
      where phone_raw10 = v_raw
      union all
      select full_name, created_at from public.region_owner_invites
      where phone_raw10 = v_raw
      union all
      select manager_name, created_at from public.teams
      where manager_phone = v_raw
    ) i order by created_at limit 1;
  end if;

  v_kind := case when v_has_account then 'reset' else 'register' end;

  update public.account_requests
  set kind = v_kind,
      full_name = coalesce(v_name, full_name)
  where phone_raw10 = v_raw and status = 'pending';
  if found then
    return 'already_pending';
  end if;

  insert into public.account_requests (phone_raw10, kind, full_name)
  values (v_raw, v_kind, left(v_name, 80));

  return case when v_has_account then 'reset_requested' else 'requested' end;
end;
$$;

-- Mevcut sorumluların telefon ve adı futbolcu kaydından doldurulur.
alter table public.teams disable trigger teams_manager_fill;
update public.teams t
set manager_phone = case when public.phone_raw10(p.phone) ~ '^5[0-9]{9}$'
                         then public.phone_raw10(p.phone) end,
    manager_name = trim(concat_ws(' ', nullif(trim(p.name), ''), nullif(trim(p.surname), '')))
from public.players p
where p.id = t.manager_id;
alter table public.teams enable trigger teams_manager_fill;

-- Panel: hesabı olmayan sorumlunun adı da görünür.
CREATE OR REPLACE FUNCTION public.desk_season(p_league_id uuid, p_season_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_season uuid;
  r jsonb;
begin
  if not (public.is_admin() or public.owns_league(p_league_id) or exists (
    select 1 from public.region_owners ro
      join public.season_regions sr on sr.id = ro.region_id
      join public.seasons s on s.id = sr.season_id
     where s.league_id = p_league_id and ro.user_id = auth.uid())) then
    raise exception 'Bu turnuvayı yönetme yetkiniz yok.' using errcode = '42501';
  end if;

  -- Seçilmediyse: varsayılan, yoksa aktif, yoksa en yeni sezon.
  select s.id into v_season
    from public.seasons s
   where s.league_id = p_league_id and s.deleted_at is null
     and (p_season_id is null or s.id = p_season_id)
   order by (s.id = p_season_id) desc nulls last, s.is_default desc nulls last,
            s.is_active desc nulls last, s.created_at desc
   limit 1;

  select jsonb_build_object(
    'season_id', v_season,
    'seasons', coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'active', s.is_active)
                       order by s.created_at desc)
      from public.seasons s where s.league_id = p_league_id and s.deleted_at is null
    ), '[]'::jsonb),
    'groups', coalesce((
      select jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name) order by g.name)
      from public.groups g where g.season_id = v_season and g.deleted_at is null
    ), '[]'::jsonb),
    'teams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'logo', t.logo_url, 'group_id', st.group_id,
        'managers', coalesce(nullif(t.manager_name, ''),
                     (select string_agg(coalesce(nullif(u.display_name, ''), u.name), ', ')
                        from public.team_managers tm
                        left join public.app_users u on u.auth_uid = tm.user_id::text
                       where tm.season_id = v_season and tm.team_id = t.id))
      ) order by t.name)
      from public.season_teams st join public.teams t on t.id = st.team_id
      where st.season_id = v_season
    ), '[]'::jsonb),
    'players', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'team_id', stp.team_id,
        'name', trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, '')),
        'no', stp.jersey_number, 'birth_year', p.birth_year,
        'pos', p.main_position, 'photo', p.photo_url
      ) order by p.name, p.surname)
      from public.season_team_players stp
      join public.players_public p on p.id = stp.player_id
      where stp.season_id = v_season and coalesce(stp.is_active, true)
    ), '[]'::jsonb),
    'matches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'week', m.week, 'group_id', m.group_id, 'date', m.match_date,
        'time', m.match_time, 'pitch_id', m.pitch_id, 'status', m.status,
        'hs', m.home_score, 'as', m.away_score, 'knockout', m.tiebreak is not null,
        'cup_round', m.cup_round, 'home_id', m.home_team_id, 'away_id', m.away_team_id
      ) order by m.week nulls last, m.match_date nulls last, m.match_time)
      from public.matches m
      where m.season_id = v_season and m.deleted_at is null
    ), '[]'::jsonb),
    'pitches', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name) order by p.name)
      from public.pitches p
    ), '[]'::jsonb),
    'penalties', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pe.id, 'player', trim(coalesce(pl.name, '') || ' ' || coalesce(pl.surname, '')),
        'player_id', pe.player_id, 'kind', pe.kind, 'status', pe.status,
        'match_count', pe.match_count, 'remaining', pe.remaining_matches,
        'active', pe.is_active, 'reason', pe.penalty_reason, 'created_at', pe.created_at,
        'match_id', pe.match_id
      ) order by pe.created_at desc)
      from public.player_penalties pe
      left join public.players_public pl on pl.id = pe.player_id
      where pe.season_id = v_season
    ), '[]'::jsonb),
    'sponsors', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', sp.id, 'name', sp.name, 'logo', sp.logo_url, 'tier', sp.tier,
        'link', sp.link_url, 'active', sp.is_active, 'sort', sp.sort_order,
        'style', sp.name_style
      ) order by sp.tier, sp.sort_order nulls last, sp.name)
      from public.sponsors sp where sp.league_id = p_league_id
    ), '[]'::jsonb),
    'news', coalesce((
      select jsonb_agg(x order by (x->>'created_at') desc) from (
        select jsonb_build_object(
          'id', n.id, 'content', n.content, 'image', n.image_url,
          'published', n.is_published, 'created_at', n.created_at, 'auto', n.auto_kind
        ) x
        from public.news n
        join public.seasons s on s.id = n.season_id
        where s.league_id = p_league_id and coalesce(n.auto_hidden, false) = false
        order by n.created_at desc limit 60
      ) q
    ), '[]'::jsonb)
  ) into r;
  return r;
end;
$function$;
