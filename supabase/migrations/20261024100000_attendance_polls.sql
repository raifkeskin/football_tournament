-- Katılım Durum Sorgulama: takım sorumlusu bir maç için kadrosuna katılım
-- durumunu sorar; oyuncu uygulamadan ya da kişisel bağlantısından (giriş
-- gerekmez, ligmasasi.com/katilim) "Geliyorum / Gelemiyorum" işaretler.
-- Başkası adına yalnızca takım sorumlusu işaretleyebilir.
-- Tablolara doğrudan erişim yok (RLS açık, politika yok); her şey aşağıdaki
-- yetki denetimli fonksiyonlardan geçer.

create table if not exists public.attendance_polls (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  season_id uuid not null references public.seasons(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  unique (match_id, team_id)
);

create table if not exists public.attendance_answers (
  poll_id uuid not null references public.attendance_polls(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  status text not null check (status in ('yes', 'no')),
  via text not null default 'app' check (via in ('app', 'link', 'manager')),
  answered_by uuid,
  updated_at timestamptz not null default now(),
  primary key (poll_id, player_id)
);

-- Oyuncunun kalıcı kişisel bağlantı anahtarı (tüm açık sorgularını gösterir).
create table if not exists public.player_links (
  player_id uuid primary key references public.players(id) on delete cascade,
  token text not null unique default replace(gen_random_uuid()::text, '-', ''),
  created_at timestamptz not null default now()
);

alter table public.attendance_polls enable row level security;
alter table public.attendance_answers enable row level security;
alter table public.player_links enable row level security;

-- Takımın sorumlusu mu (team_managers ya da takımın sorumlu oyuncusu).
create or replace function public.attendance_is_manager(p_season_id uuid, p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.manages_team(p_season_id, p_team_id) or exists (
    select 1 from public.teams t
    join public.players p on p.id = t.manager_id
    where t.id = p_team_id and p.auth_uid = auth.uid()
  )
$$;

-- Oyuncu takımın o sezonki aktif kadrosunda mı.
create or replace function public.attendance_in_roster(p_season_id uuid, p_team_id uuid, p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (
    select 1 from public.season_team_players s
    where s.season_id = p_season_id and s.team_id = p_team_id
      and s.player_id = p_player_id and coalesce(s.is_active, true)
  )
$$;

-- Maç henüz başlamadı mı (sorgu yalnız maç öncesi değişir).
create or replace function public.attendance_match_open(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (
    select 1 from public.matches m
    where m.id = p_match_id and m.deleted_at is null
      and m.status in ('notStarted', 'postponed')
  )
$$;

/** Sorguyu açar (kapalıysa yeniden açar). İlk açılışta hesabı olan kadro
    oyuncularına uygulama içi bildirim gider. */
create or replace function public.attendance_open(p_match_id uuid, p_team_id uuid)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  m public.matches;
  v_id uuid;
  v_new boolean := false;
  v_team text;
  v_rival text;
  v_when text;
  v_uids uuid[];
begin
  select * into m from public.matches where id = p_match_id and deleted_at is null;
  if not found or p_team_id not in (m.home_team_id, m.away_team_id) then
    raise exception 'Maç bulunamadı.';
  end if;
  if not public.attendance_is_manager(m.season_id, p_team_id) then
    raise exception 'Katılım sorgusunu yalnızca takım sorumlusu açabilir.'
      using errcode = '42501';
  end if;
  if not public.attendance_match_open(p_match_id) then
    raise exception 'Maç başladı; katılım sorgusu açılamaz.';
  end if;

  select id into v_id from public.attendance_polls
   where match_id = p_match_id and team_id = p_team_id;
  if v_id is null then
    insert into public.attendance_polls (match_id, team_id, season_id, created_by)
    values (p_match_id, p_team_id, m.season_id, auth.uid())
    returning id into v_id;
    v_new := true;
  else
    update public.attendance_polls set closed_at = null where id = v_id;
  end if;

  if v_new then
    select name into v_team from public.teams where id = p_team_id;
    select name into v_rival from public.teams
     where id = case when p_team_id = m.home_team_id then m.away_team_id else m.home_team_id end;
    v_when := case
      when m.match_date is null then ''
      else ' (' || to_char(m.match_date, 'DD.MM') || coalesce(' ' || nullif(m.match_time, ''), '') || ')'
    end;
    select array_agg(distinct p.auth_uid) into v_uids
      from public.season_team_players s
      join public.players p on p.id = s.player_id
     where s.season_id = m.season_id and s.team_id = p_team_id
       and coalesce(s.is_active, true)
       and p.auth_uid is not null and p.auth_uid <> auth.uid();
    if v_uids is not null then
      perform public.push_send(
        v_uids,
        'Katılım Durum Sorgulama',
        coalesce(v_team, '') || ' – ' || coalesce(v_rival, '') || v_when
          || ' maçına katılım durumunu bildir.',
        '/',
        'attend-' || p_match_id
      );
    end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.attendance_close(p_poll_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  p public.attendance_polls;
begin
  select * into p from public.attendance_polls where id = p_poll_id;
  if not found or not public.attendance_is_manager(p.season_id, p.team_id) then
    raise exception 'Katılım sorgusunu yalnızca takım sorumlusu kapatabilir.'
      using errcode = '42501';
  end if;
  update public.attendance_polls set closed_at = now() where id = p_poll_id;
end;
$$;

/** Uygulamadan işaretleme. Oyuncu yalnız kendisi için; takım sorumlusu
    herkes için (sorgu kapalıyken de). p_status null: işareti kaldırır. */
create or replace function public.attendance_set(p_poll_id uuid, p_player_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  p public.attendance_polls;
  v_manager boolean;
  v_self boolean;
begin
  if p_status is not null and p_status not in ('yes', 'no') then
    raise exception 'Geçersiz durum.';
  end if;
  select * into p from public.attendance_polls where id = p_poll_id;
  if not found then
    raise exception 'Sorgu bulunamadı.';
  end if;
  if not public.attendance_in_roster(p.season_id, p.team_id, p_player_id) then
    raise exception 'Oyuncu bu takımın kadrosunda değil.';
  end if;
  v_manager := public.attendance_is_manager(p.season_id, p.team_id);
  v_self := exists (
    select 1 from public.players where id = p_player_id and auth_uid = auth.uid()
  );
  if not v_manager and not v_self then
    raise exception 'Başkası adına yalnızca takım sorumlusu işaretleyebilir.'
      using errcode = '42501';
  end if;
  if not v_manager and (p.closed_at is not null or not public.attendance_match_open(p.match_id)) then
    raise exception 'Katılım sorgusu kapandı.';
  end if;

  if p_status is null then
    delete from public.attendance_answers where poll_id = p_poll_id and player_id = p_player_id;
  else
    insert into public.attendance_answers (poll_id, player_id, status, via, answered_by)
    values (p_poll_id, p_player_id, p_status,
            case when v_self then 'app' else 'manager' end, auth.uid())
    on conflict (poll_id, player_id) do update
      set status = excluded.status, via = excluded.via,
          answered_by = excluded.answered_by, updated_at = now();
  end if;
end;
$$;

/** Maçtaki takımın sorgusu ve kadro durumu. Takım sorumlusu, kadro
    oyuncuları, turnuva yöneticileri ve admin görebilir; telefon yalnızca
    sorumluya döner (WhatsApp'tan kişisel bağlantı göndermek için). */
create or replace function public.attendance_summary(p_match_id uuid, p_team_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  m public.matches;
  p public.attendance_polls;
  v_manager boolean;
  v_me uuid;
begin
  select * into m from public.matches where id = p_match_id and deleted_at is null;
  if not found or p_team_id not in (m.home_team_id, m.away_team_id) then
    return null;
  end if;
  v_manager := public.attendance_is_manager(m.season_id, p_team_id);
  select pl.id into v_me
    from public.players pl
    join public.season_team_players s on s.player_id = pl.id
   where pl.auth_uid = auth.uid() and s.season_id = m.season_id
     and s.team_id = p_team_id and coalesce(s.is_active, true)
   limit 1;
  if not (v_manager or v_me is not null or public.is_admin()
          or public.owns_league(m.league_id)) then
    return null;
  end if;

  select * into p from public.attendance_polls
   where match_id = p_match_id and team_id = p_team_id;

  return jsonb_build_object(
    'poll_id', p.id,
    'closed', p.closed_at is not null,
    'match_open', public.attendance_match_open(p_match_id),
    'can_manage', v_manager,
    'me', v_me,
    'players', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', pl.id,
          'name', trim(coalesce(pl.name, '') || ' ' || coalesce(pl.surname, '')),
          'photo', pl.photo_url,
          'number', s.jersey_number,
          'has_account', pl.auth_uid is not null,
          'phone', case when v_manager and pl.phone ~ '^5[0-9]{9}$' then pl.phone end,
          'status', a.status,
          'via', a.via
        ) order by s.jersey_number nulls last, pl.name)
        from public.season_team_players s
        join public.players pl on pl.id = s.player_id
        left join public.attendance_answers a on a.poll_id = p.id and a.player_id = pl.id
       where s.season_id = m.season_id and s.team_id = p_team_id
         and coalesce(s.is_active, true)
    ), '[]'::jsonb)
  );
end;
$$;

/** Takım sorumlusu için oyuncunun kişisel bağlantı anahtarı (yoksa üretir). */
create or replace function public.attendance_player_link(p_match_id uuid, p_team_id uuid, p_player_id uuid)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  m public.matches;
  v_token text;
begin
  select * into m from public.matches where id = p_match_id and deleted_at is null;
  if not found or not public.attendance_is_manager(m.season_id, p_team_id) then
    raise exception 'Kişisel bağlantıyı yalnızca takım sorumlusu alabilir.'
      using errcode = '42501';
  end if;
  if not public.attendance_in_roster(m.season_id, p_team_id, p_player_id) then
    raise exception 'Oyuncu bu takımın kadrosunda değil.';
  end if;
  insert into public.player_links (player_id) values (p_player_id)
  on conflict (player_id) do nothing;
  select token into v_token from public.player_links where player_id = p_player_id;
  return v_token;
end;
$$;

/** Kişisel bağlantı sayfası (giriş yok): oyuncu ve açık sorguları. */
create or replace function public.attendance_link_view(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_player uuid;
begin
  select player_id into v_player from public.player_links where token = p_token;
  if v_player is null then
    return null;
  end if;
  return jsonb_build_object(
    'name', (select trim(coalesce(name, '') || ' ' || coalesce(surname, ''))
               from public.players where id = v_player),
    'polls', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', ap.id,
          'team', t.name,
          'team_logo', t.logo_url,
          'home', h.name,
          'away', a.name,
          'date', m.match_date,
          'time', m.match_time,
          'pitch', pt.name,
          'status', ans.status,
          'yes', (select count(*) from public.attendance_answers x where x.poll_id = ap.id and x.status = 'yes'),
          'no', (select count(*) from public.attendance_answers x where x.poll_id = ap.id and x.status = 'no')
        ) order by m.match_date nulls last, m.match_time)
        from public.attendance_polls ap
        join public.matches m on m.id = ap.match_id
        join public.teams t on t.id = ap.team_id
        join public.teams h on h.id = m.home_team_id
        join public.teams a on a.id = m.away_team_id
        left join public.pitches pt on pt.id = m.pitch_id
        left join public.attendance_answers ans on ans.poll_id = ap.id and ans.player_id = v_player
       where ap.closed_at is null
         and public.attendance_match_open(ap.match_id)
         and public.attendance_in_roster(ap.season_id, ap.team_id, v_player)
    ), '[]'::jsonb)
  );
end;
$$;

/** Kişisel bağlantıdan işaretleme: yalnızca bağlantının sahibi için. */
create or replace function public.attendance_link_answer(p_token text, p_poll_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_player uuid;
  p public.attendance_polls;
begin
  if p_status not in ('yes', 'no') then
    raise exception 'Geçersiz durum.';
  end if;
  select player_id into v_player from public.player_links where token = p_token;
  if v_player is null then
    raise exception 'Bağlantı geçersiz.';
  end if;
  select * into p from public.attendance_polls where id = p_poll_id;
  if not found or p.closed_at is not null or not public.attendance_match_open(p.match_id)
     or not public.attendance_in_roster(p.season_id, p.team_id, v_player) then
    raise exception 'Katılım sorgusu kapandı.';
  end if;
  insert into public.attendance_answers (poll_id, player_id, status, via)
  values (p_poll_id, v_player, p_status, 'link')
  on conflict (poll_id, player_id) do update
    set status = excluded.status, via = 'link', answered_by = null, updated_at = now();
end;
$$;

revoke all on function public.attendance_is_manager(uuid, uuid) from public, anon;
revoke all on function public.attendance_in_roster(uuid, uuid, uuid) from public, anon;
revoke all on function public.attendance_match_open(uuid) from public, anon;
revoke all on function public.attendance_open(uuid, uuid) from public, anon;
revoke all on function public.attendance_close(uuid) from public, anon;
revoke all on function public.attendance_set(uuid, uuid, text) from public, anon;
revoke all on function public.attendance_summary(uuid, uuid) from public, anon;
revoke all on function public.attendance_player_link(uuid, uuid, uuid) from public, anon;
grant execute on function public.attendance_open(uuid, uuid) to authenticated;
grant execute on function public.attendance_close(uuid) to authenticated;
grant execute on function public.attendance_set(uuid, uuid, text) to authenticated;
grant execute on function public.attendance_summary(uuid, uuid) to authenticated;
grant execute on function public.attendance_player_link(uuid, uuid, uuid) to authenticated;
grant execute on function public.attendance_link_view(text) to anon, authenticated;
grant execute on function public.attendance_link_answer(text, uuid, text) to anon, authenticated;
