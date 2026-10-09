-- Bildirim ayarları.
-- * Kişi başına tercihler (notification_prefs). Satırı olmayan varsayılanı alır.
-- * "Hangi maçlar" seçenekleri alıcı listesini belirler. Bildirim türü
--   kapatılınca telefona gitmez, uygulama içi listeye yine düşer.
-- * Takip edilen takım (cihazdan DB'ye) ve takip edilen turnuva (misafir de).
-- * Yeni bildirimler: maç başladı, ilk yarı sonucu, gol, ceza onaylandı.
-- * Maç planlandı: tarih alt satırda. Uygulama içi bildirimler 14 gün durur.
-- * Telefon bildirimine basınca ilgili maç / haber açılır (/?n=<tür>-<id>).

create table if not exists public.notification_prefs (
  user_id          uuid primary key references auth.users (id) on delete cascade,
  push_enabled     boolean not null default true,
  scope_my_team    boolean not null default true,
  scope_followed   boolean not null default true,
  scope_group      boolean not null default false,
  scope_league     boolean not null default false,
  k_schedule       boolean not null default true,
  k_live           boolean not null default true,
  k_goal           boolean not null default true,
  k_result         boolean not null default true,
  k_news           text    not null default 'region'
                     check (k_news in ('off', 'region', 'league')),
  k_penalty        boolean not null default true,
  k_admin_penalty  boolean not null default true,
  k_admin_requests boolean not null default true,
  updated_at       timestamptz not null default now()
);
alter table public.notification_prefs enable row level security;
drop policy if exists notification_prefs_own on public.notification_prefs;
create policy notification_prefs_own on public.notification_prefs for all
  to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop trigger if exists set_updated_at on public.notification_prefs;
create trigger set_updated_at before update on public.notification_prefs
  for each row execute function public.set_updated_at();

-- Turnuva başına takip edilen takım (ana sayfadaki "Takımımı takip et").
create table if not exists public.followed_teams (
  user_id    uuid not null references auth.users (id) on delete cascade,
  league_id  uuid not null references public.leagues (id) on delete cascade,
  team_id    uuid not null references public.teams (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, league_id)
);
create index if not exists followed_teams_team_idx on public.followed_teams (team_id);
alter table public.followed_teams enable row level security;
drop policy if exists followed_teams_own on public.followed_teams;
create policy followed_teams_own on public.followed_teams for all
  to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Bildirim için takip edilen turnuva (misafir dahil).
create table if not exists public.followed_leagues (
  user_id    uuid not null references auth.users (id) on delete cascade,
  league_id  uuid not null references public.leagues (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, league_id)
);
create index if not exists followed_leagues_league_idx on public.followed_leagues (league_id);
alter table public.followed_leagues enable row level security;
drop policy if exists followed_leagues_own on public.followed_leagues;
create policy followed_leagues_own on public.followed_leagues for all
  to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Kişi bu türü telefonda istiyor mu? (satırı yoksa varsayılanlar)
create or replace function public.notif_wants(p_uid uuid, p_kind text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not coalesce(p.push_enabled, true) then false
    else case p_kind
      when 'schedule'  then coalesce(p.k_schedule, true)
      when 'live'      then coalesce(p.k_live, true)
      when 'goal'      then coalesce(p.k_goal, true)
      when 'result'    then coalesce(p.k_result, true)
      when 'news'      then coalesce(p.k_news, 'region') <> 'off'
      when 'penaltyok' then coalesce(p.k_penalty, true)
      when 'penalty'   then coalesce(p.k_admin_penalty, true)
      else true -- hatırlatma (sabit) ve diğerleri
    end
  end
  from (select 1) x
  left join public.notification_prefs p on p.user_id = p_uid
$$;

-- Maçla ilgili bildirimin alıcıları (uygulama içi liste). Telefona gidip
-- gitmeyeceğine push_send tür ayarına göre karar verir.
create or replace function public.match_audience(p_match_id uuid, p_include_followers boolean)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  with m as (
    select mt.season_id, mt.league_id, mt.group_id,
           mt.home_team_id, mt.away_team_id, g.region_id
    from public.matches mt
    left join public.groups g on g.id = mt.group_id
    where mt.id = p_match_id
  ),
  -- Sezondaki oyuncular ve takım sorumluları, takımlarının grubuyla.
  members as (
    select p.auth_uid as uid, stp.team_id
    from public.season_team_players stp
    join public.players p on p.id = stp.player_id
    join m on stp.season_id = m.season_id
    where stp.is_active
    union
    select tm.user_id, tm.team_id
    from public.team_managers tm
    join m on tm.season_id = m.season_id
  ),
  member_groups as (
    select mb.uid, mb.team_id, st.group_id
    from members mb
    join m on true
    left join public.season_teams st
      on st.season_id = m.season_id and st.team_id = mb.team_id
  ),
  ids as (
    -- Takımımın maçları
    select mg.uid from member_groups mg
    join m on mg.team_id in (m.home_team_id, m.away_team_id)
    left join public.notification_prefs np on np.user_id = mg.uid
    where coalesce(np.scope_my_team, true)
    union
    -- Grubumdaki tüm maçlar
    select mg.uid from member_groups mg
    join m on mg.group_id = m.group_id
    join public.notification_prefs np on np.user_id = mg.uid
    where np.scope_group
    union
    -- Turnuvanın tüm maçları
    select mg.uid from member_groups mg
    join public.notification_prefs np on np.user_id = mg.uid
    where np.scope_league
    union
    -- Takip ettiğim takımlar
    select f.user_id from public.followed_teams f
    join m on f.team_id in (m.home_team_id, m.away_team_id)
    left join public.notification_prefs np on np.user_id = f.user_id
    where coalesce(np.scope_followed, true)
    union
    -- Takip ettiğim turnuvalar (misafir dahil)
    select fl.user_id from public.followed_leagues fl
    join m on fl.league_id = m.league_id
    union
    -- Yöneticiler
    select o.user_id from public.league_owners o
    join m on o.league_id = m.league_id
    union
    select ro.user_id from m
    join public.region_owners ro on ro.region_id = m.region_id
    union
    -- Kodla takip edenler (yalnız sonuç)
    select f.user_id from public.league_followers f
    join m on f.league_id = m.league_id
    where p_include_followers
  )
  select coalesce(array_agg(distinct uid), '{}') from ids where uid is not null
$$;

-- Uygulama içi listeye herkes; telefona yalnız o türü isteyenler.
create or replace function public.push_send(
  p_user_ids uuid[],
  p_title text,
  p_body text,
  p_url text default '/',
  p_tag text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret text;
  v_kind text := nullif(split_part(coalesce(p_tag, ''), '-', 1), '');
  v_ref text := nullif(substr(coalesce(p_tag, ''), length(coalesce(v_kind, '')) + 2), '');
  v_push uuid[];
  v_url text;
begin
  if p_user_ids is null then
    return;
  end if;

  begin
    insert into public.notifications (user_id, title, body, kind, ref_id)
    select distinct u, p_title, p_body, v_kind,
           case when v_ref ~* '^[0-9a-f-]{36}$' then v_ref::uuid end
      from unnest(p_user_ids) u
     where u is not null
       and exists (select 1 from auth.users au where au.id = u);
  exception when others then
    raise warning 'push_send notifications: %', sqlerrm;
  end;

  select coalesce(array_agg(distinct u), '{}') into v_push
    from unnest(p_user_ids) u
   where u is not null and public.notif_wants(u, coalesce(v_kind, ''));
  if cardinality(v_push) = 0 or not exists (
    select 1 from public.push_subscriptions where user_id = any (v_push)
  ) then
    return;
  end if;
  select value into v_secret from public.app_private_settings where key = 'push_secret';
  if coalesce(v_secret, '') = '' then
    return;
  end if;
  -- Bildirime basınca ilgili ekran açılsın.
  v_url := case
    when p_tag is not null and coalesce(p_url, '/') = '/' then '/?n=' || p_tag
    else coalesce(p_url, '/')
  end;
  perform net.http_post(
    url := 'https://qxdjebzszikeslobrozf.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'user_ids', to_jsonb(v_push),
      'title', p_title,
      'body', p_body,
      'url', v_url,
      'tag', p_tag
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    )
  );
exception when others then
  raise warning 'push_send: %', sqlerrm;
end;
$$;

-- Skor metni: "Beyaz FK 2 - 1 Yeşil FK".
create or replace function public.match_score_text(p_match_id uuid, p_home int, p_away int)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(h.name, '?') || ' ' || p_home || ' - ' || p_away || ' ' || coalesce(a.name, '?')
  from public.matches m
  left join public.teams h on h.id = m.home_team_id
  left join public.teams a on a.id = m.away_team_id
  where m.id = p_match_id
$$;

create or replace function public.matches_push_notify()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Sonuç
  if tg_op = 'UPDATE' and new.status = 'finished'
     and old.status is distinct from 'finished' then
    perform public.push_send(
      public.match_audience(new.id, true),
      'Maç sonucu',
      public.match_score_text(new.id, coalesce(new.home_score, 0), coalesce(new.away_score, 0)),
      '/',
      'result-' || new.id
    );
    return new;
  end if;

  -- Maç başladı
  if tg_op = 'UPDATE' and new.status = 'live'
     and old.status = 'notStarted' then
    perform public.push_send(
      public.match_audience(new.id, false),
      'Maç başladı',
      public.match_title(new.id),
      '/',
      'live-' || new.id
    );
    return new;
  end if;

  -- İlk yarı sonucu
  if tg_op = 'UPDATE' and new.status = 'halftime'
     and old.status is distinct from 'halftime' then
    perform public.push_send(
      public.match_audience(new.id, false),
      'İlk yarı sonucu',
      public.match_score_text(new.id, coalesce(new.home_score, 0), coalesce(new.away_score, 0)),
      '/',
      'live-' || new.id
    );
    return new;
  end if;

  -- Tarih / saat belirlendi ya da değişti (yalnızca oynanmamış maç).
  -- Yeni eklenen maçta yalnızca 7 gün içindekiler bildirilir (toplu
  -- fikstür girişinde onlarca bildirim gitmesin).
  if new.status = 'notStarted' and new.match_date is not null
     and coalesce(new.match_time, '') <> ''
     and (
       (tg_op = 'INSERT' and new.match_date <= current_date + 7)
       or (tg_op = 'UPDATE' and (
         new.match_date is distinct from old.match_date
         or new.match_time is distinct from old.match_time))
     ) then
    perform public.push_send(
      public.match_audience(new.id, false),
      case
        when tg_op = 'UPDATE' and old.match_date is not null
          then 'Maç saati değişti'
        else 'Maç planlandı'
      end,
      public.match_title(new.id) || E'\n' ||
        public.tr_match_when(new.match_date, new.match_time),
      '/',
      'schedule-' || new.id
    );
  end if;
  return new;
end;
$$;

-- Canlı gol: skor gollerden sayılır (uygulama skoru olaydan sonra yazar).
create or replace function public.match_events_goal_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m record;
  v_home int;
  v_away int;
  v_scorer text;
  v_assist text;
  v_body text;
begin
  if new.event_type <> 'goal' then
    return new;
  end if;
  select id, status, home_team_id, away_team_id into v_m
    from public.matches where id = new.match_id;
  if v_m.id is null or v_m.status not in ('live', 'halftime') then
    return new;
  end if;

  select
    count(*) filter (where (e.team_id = v_m.home_team_id and not coalesce(e.is_own_goal, false))
                        or (e.team_id = v_m.away_team_id and coalesce(e.is_own_goal, false))),
    count(*) filter (where (e.team_id = v_m.away_team_id and not coalesce(e.is_own_goal, false))
                        or (e.team_id = v_m.home_team_id and coalesce(e.is_own_goal, false)))
    into v_home, v_away
    from public.match_events e
   where e.match_id = new.match_id and e.event_type = 'goal';

  select trim(coalesce(name, '') || ' ' || coalesce(surname, '')) into v_scorer
    from public.players where id = new.player_id;
  select trim(coalesce(name, '') || ' ' || coalesce(surname, '')) into v_assist
    from public.players where id = new.assist_player_id;

  v_body := public.match_score_text(new.match_id, v_home, v_away)
    || ' · '
    || case when new.minute is not null then new.minute::text || '''' || ' ' else '' end
    || coalesce(nullif(v_scorer, ''), 'Gol')
    || case when coalesce(new.is_own_goal, false) then ' (K.K.)'
            when coalesce(new.is_penalty, false) then ' (P)' else '' end
    || case when nullif(v_assist, '') is not null
            then ' (Asist: ' || v_assist || ')' else '' end;

  perform public.push_send(
    public.match_audience(new.match_id, false),
    'GOL!',
    v_body,
    '/',
    'goal-' || new.match_id
  );
  return new;
end;
$$;

drop trigger if exists match_events_goal_push on public.match_events;
create trigger match_events_goal_push
  after insert on public.match_events
  for each row execute function public.match_events_goal_push();

-- Ceza onaylandı: yalnız cezalı oyuncu ve takımının sorumlusu.
create or replace function public.player_penalties_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
  v_name text;
  v_reason text;
begin
  if new.status <> 'approved'
     or (tg_op = 'UPDATE' and old.status = 'approved') then
    return new;
  end if;

  select trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, '')) into v_name
    from public.players p where p.id = new.player_id;

  with ids as (
    select p.auth_uid as uid from public.players p where p.id = new.player_id
    union
    select tm.user_id from public.team_managers tm
    join public.season_team_players stp
      on stp.season_id = tm.season_id and stp.team_id = tm.team_id
    where stp.season_id = new.season_id and stp.player_id = new.player_id
  )
  select array_agg(distinct uid) into v_ids from ids where uid is not null;

  v_reason := case new.kind
    when 'red_card' then 'Kırmızı kart'
    when 'second_yellow' then 'İkinci sarı kart'
    else coalesce(nullif(trim(new.penalty_reason), ''), 'Disiplin cezası')
  end;

  perform public.push_send(
    v_ids,
    'Ceza onaylandı',
    coalesce(nullif(v_name, ''), 'Oyuncu') || ' · ' || v_reason || ' · '
      || coalesce(new.match_count, 1) || ' maç ceza',
    '/',
    'penaltyok-' || new.id
  );
  return new;
end;
$$;

drop trigger if exists player_penalties_push on public.player_penalties;
create trigger player_penalties_push
  after insert or update of status on public.player_penalties
  for each row execute function public.player_penalties_push();

-- Haber: bölgeye göre. Kişi "Tüm turnuva" seçtiyse başka bölgenin haberi de.
create or replace function public.news_push_notify()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
  v_league uuid;
  v_name text;
begin
  if not coalesce(new.is_published, false) then
    return new;
  end if;
  if tg_op = 'UPDATE' and coalesce(old.is_published, false) then
    return new;
  end if;
  select s.league_id, l.name into v_league, v_name
    from public.seasons s join public.leagues l on l.id = s.league_id
   where s.id = new.season_id;
  if v_league is null then
    return new;
  end if;

  with members as (
    select p.auth_uid as uid, g.region_id
    from public.season_team_players stp
    join public.players p on p.id = stp.player_id
    left join public.season_teams st
      on st.season_id = stp.season_id and st.team_id = stp.team_id
    left join public.groups g on g.id = st.group_id
    where stp.season_id = new.season_id and stp.is_active
    union
    select tm.user_id, g.region_id
    from public.team_managers tm
    left join public.season_teams st
      on st.season_id = tm.season_id and st.team_id = tm.team_id
    left join public.groups g on g.id = st.group_id
    where tm.season_id = new.season_id
  ),
  ids as (
    select mb.uid from members mb
    left join public.notification_prefs np on np.user_id = mb.uid
    where new.region_id is null
       or mb.region_id = new.region_id
       or coalesce(np.k_news, 'region') = 'league'
    union
    select o.user_id from public.league_owners o where o.league_id = v_league
    union
    select ro.user_id from public.region_owners ro
    join public.season_regions r on r.id = ro.region_id
    where r.season_id = new.season_id
      and (new.region_id is null or r.id = new.region_id)
    union
    select f.user_id from public.league_followers f where f.league_id = v_league
    union
    select fl.user_id from public.followed_leagues fl where fl.league_id = v_league
    union
    select ft.user_id from public.followed_teams ft where ft.league_id = v_league
  )
  select array_agg(distinct uid) into v_ids from ids where uid is not null;

  perform public.push_send(
    v_ids,
    coalesce(v_name, 'Turnuva') || ' · Yeni haber',
    left(regexp_replace(coalesce(new.content, ''), '\s+', ' ', 'g'), 120),
    '/',
    'news-' || new.id
  );
  return new;
end;
$$;

-- Uygulama içi bildirimler 14 gün durur.
select cron.schedule(
  'notifications-cleanup',
  '30 3 * * *',
  $$delete from public.notifications where created_at < now() - interval '14 days'$$
);
