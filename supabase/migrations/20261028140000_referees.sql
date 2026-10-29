-- Hakemler: havuz (referees) → turnuvaya bağlama (league_referees) → maçta
-- orta hakem + 2 yardımcı. Hakem telefonuyla hesap açınca kendi maçlarını
-- görür (hesap telefonla eşleşir, ayrı bağlama yok). Telefon herkese açık
-- tabloda değil (referee_contacts, yalnız RPC). Yeni özellik: app_settings
-- referees_enabled açılana dek yalnız admin (UI + RPC).

create table if not exists public.referees (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 80),
  photo_url text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.referees enable row level security;
drop policy if exists referees_read on public.referees;
create policy referees_read on public.referees for select using (true);
grant select on public.referees to anon, authenticated;

create table if not exists public.referee_contacts (
  referee_id uuid primary key references public.referees(id) on delete cascade,
  phone_raw10 text not null unique check (phone_raw10 ~ '^5[0-9]{9}$')
);
alter table public.referee_contacts enable row level security;
revoke all on public.referee_contacts from anon, authenticated;

create table if not exists public.league_referees (
  league_id uuid not null references public.leagues(id) on delete cascade,
  referee_id uuid not null references public.referees(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (league_id, referee_id)
);
create index if not exists league_referees_ref_idx
  on public.league_referees (referee_id);
alter table public.league_referees enable row level security;
drop policy if exists league_referees_read on public.league_referees;
create policy league_referees_read on public.league_referees for select
  using (public.can_view_league(league_id));
grant select on public.league_referees to anon, authenticated;

alter table public.matches
  add column if not exists referee_id uuid references public.referees(id) on delete set null,
  add column if not exists assistant_referee1_id uuid references public.referees(id) on delete set null,
  add column if not exists assistant_referee2_id uuid references public.referees(id) on delete set null;
create index if not exists matches_referee_idx on public.matches (referee_id)
  where referee_id is not null;
create index if not exists matches_ar1_idx on public.matches (assistant_referee1_id)
  where assistant_referee1_id is not null;
create index if not exists matches_ar2_idx on public.matches (assistant_referee2_id)
  where assistant_referee2_id is not null;

-- Halısahada tek hakem: yan hakem alanları sezonda kapatılabilir.
alter table public.seasons
  add column if not exists assistant_referees_enabled boolean not null default true;

insert into public.app_settings (key, value)
values ('referees_enabled', 'false'::jsonb)
on conflict (key) do nothing;

-- Eski sürümler hakemi matches.referee_name'den okur: seçilen orta hakemin
-- adı oraya da yazılır.
create or replace function public.matches_referee_name_sync()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if new.referee_id is not null then
    select r.name into new.referee_name
      from public.referees r where r.id = new.referee_id;
  elsif tg_op = 'UPDATE' and old.referee_id is not null then
    new.referee_name := null;
  end if;
  return new;
end;
$function$;
drop trigger if exists matches_referee_name_sync on public.matches;
create trigger matches_referee_name_sync
  before insert or update of referee_id on public.matches
  for each row execute function public.matches_referee_name_sync();

-- Hakemin adı değişince maçlardaki ad da güncellenir.
create or replace function public.referees_name_sync()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.name is distinct from old.name then
    update public.matches set referee_name = new.name
     where referee_id = new.id;
  end if;
  return new;
end;
$function$;
drop trigger if exists referees_name_sync on public.referees;
create trigger referees_name_sync
  after update of name on public.referees
  for each row execute function public.referees_name_sync();

create or replace function public.referees_feature_on()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select public.is_admin() or coalesce((
    select value = 'true'::jsonb from public.app_settings
     where key = 'referees_enabled'), false)
$function$;
grant execute on function public.referees_feature_on() to anon, authenticated;

-- Hesabın hakem kaydı (giriş telefonu = hakem telefonu).
create or replace function public.my_referee_id()
returns uuid
language sql
stable
security definer
set search_path to ''
as $function$
  select c.referee_id
    from public.referee_contacts c
   where c.phone_raw10 =
         split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1)
   limit 1
$function$;
grant execute on function public.my_referee_id() to authenticated;

-- Turnuvanın hakemleri; telefon ve hesap durumu yalnız turnuva yöneticisine.
create or replace function public.league_referees_list(p_league_id uuid)
returns table (
  id uuid, name text, photo_url text, phone_raw10 text,
  has_account boolean, match_count int
)
language sql
stable
security definer
set search_path to ''
as $function$
  select r.id, r.name, r.photo_url,
         case when public.owns_league(p_league_id) then c.phone_raw10 end,
         case when public.owns_league(p_league_id) then exists (
           select 1 from auth.users u
            where u.email = c.phone_raw10 || '@masterclass.com') end,
         (select count(*)::int from public.matches m
           where m.league_id = p_league_id and m.deleted_at is null
             and r.id in (m.referee_id, m.assistant_referee1_id,
                          m.assistant_referee2_id))
    from public.league_referees lr
    join public.referees r on r.id = lr.referee_id
    left join public.referee_contacts c on c.referee_id = r.id
   where lr.league_id = p_league_id
     and (public.owns_league(p_league_id)
          or public.is_region_owner_of_league(p_league_id))
   order by r.name
$function$;
grant execute on function public.league_referees_list(uuid) to authenticated;

-- Turnuvaya eklenecek hakem için havuzda eşleşenler (aynı telefon ya da
-- benzer ad): "mevcudu bağla" önerisi. Başka turnuvaların adı görünür,
-- telefon görünmez.
create or replace function public.referee_candidates(
  p_league_id uuid, p_name text, p_phone text default null)
returns table (id uuid, name text, photo_url text, same_phone boolean, leagues text)
language sql
stable
security definer
set search_path to ''
as $function$
  select r.id, r.name, r.photo_url,
         c.phone_raw10 is not null
           and c.phone_raw10 = public.phone_raw10(p_phone),
         (select string_agg(l.name, ', ' order by l.name)
            from public.league_referees x
            join public.leagues l on l.id = x.league_id
           where x.referee_id = r.id)
    from public.referees r
    left join public.referee_contacts c on c.referee_id = r.id
   where public.owns_league(p_league_id)
     and public.referees_feature_on()
     and not exists (select 1 from public.league_referees x
                      where x.league_id = p_league_id and x.referee_id = r.id)
     and ((public.phone_raw10(p_phone) is not null
           and c.phone_raw10 = public.phone_raw10(p_phone))
          or lower(public._id_fold(r.name)) = lower(public._id_fold(p_name)))
   limit 5
$function$;
grant execute on function public.referee_candidates(uuid, text, text) to authenticated;

-- Yeni hakem (p_referee_id null) ya da turnuvadaki hakemi düzenleme.
create or replace function public.referee_save(
  p_league_id uuid, p_referee_id uuid, p_name text, p_phone text,
  p_photo_url text default null)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_id uuid := p_referee_id;
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_raw text := public.phone_raw10(p_phone);
  v_other text;
begin
  if not public.owns_league(p_league_id) or not public.referees_feature_on() then
    raise exception 'Yetkiniz yok.';
  end if;
  if v_name is null or length(v_name) < 2 then
    raise exception 'Hakemin adını girin.';
  end if;
  if v_raw is not null and v_raw !~ '^5[0-9]{9}$' then
    raise exception 'Telefon numarası 5 ile başlayan 10 hane olmalı.';
  end if;
  if v_raw is not null then
    select r.name into v_other
      from public.referee_contacts c join public.referees r on r.id = c.referee_id
     where c.phone_raw10 = v_raw and c.referee_id is distinct from v_id;
    if v_other is not null then
      raise exception 'Bu telefon % adlı hakemde kayıtlı; listeden bağlayın.', v_other;
    end if;
  end if;

  if v_id is null then
    insert into public.referees (name, photo_url)
    values (v_name, nullif(trim(coalesce(p_photo_url, '')), ''))
    returning id into v_id;
    insert into public.league_referees (league_id, referee_id)
    values (p_league_id, v_id);
  else
    if not exists (select 1 from public.league_referees
                    where league_id = p_league_id and referee_id = v_id) then
      raise exception 'Hakem bu turnuvada değil.';
    end if;
    update public.referees
       set name = v_name,
           photo_url = nullif(trim(coalesce(p_photo_url, '')), ''),
           updated_at = now()
     where id = v_id;
  end if;

  if v_raw is null then
    delete from public.referee_contacts where referee_id = v_id;
  else
    insert into public.referee_contacts (referee_id, phone_raw10)
    values (v_id, v_raw)
    on conflict (referee_id) do update set phone_raw10 = excluded.phone_raw10;
  end if;
  return v_id;
end;
$function$;
grant execute on function public.referee_save(uuid, uuid, text, text, text) to authenticated;

create or replace function public.referee_link(p_league_id uuid, p_referee_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not public.owns_league(p_league_id) or not public.referees_feature_on() then
    raise exception 'Yetkiniz yok.';
  end if;
  insert into public.league_referees (league_id, referee_id)
  values (p_league_id, p_referee_id)
  on conflict do nothing;
end;
$function$;
grant execute on function public.referee_link(uuid, uuid) to authenticated;

-- Turnuvadan çıkarma: atandığı maçlar kalır (geçmiş korunur); hakem
-- hiçbir turnuvada ve maçta değilse kaydı da silinir.
create or replace function public.referee_unlink(p_league_id uuid, p_referee_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not public.owns_league(p_league_id) or not public.referees_feature_on() then
    raise exception 'Yetkiniz yok.';
  end if;
  delete from public.league_referees
   where league_id = p_league_id and referee_id = p_referee_id;
  if not exists (select 1 from public.league_referees where referee_id = p_referee_id)
     and not exists (select 1 from public.matches m
                      where p_referee_id in (m.referee_id, m.assistant_referee1_id,
                                             m.assistant_referee2_id)) then
    delete from public.referees where id = p_referee_id;
  end if;
end;
$function$;
grant execute on function public.referee_unlink(uuid, uuid) to authenticated;

-- Maça hakem atama: maçın yöneticisi (admin, kurucu, bölge sorumlusu);
-- yalnız turnuvaya bağlı hakemler, aynı kişi iki görevde olamaz.
create or replace function public.match_set_referees(
  p_match_id uuid, p_referee uuid, p_assistant1 uuid, p_assistant2 uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_league uuid;
  v_ids uuid[] := array_remove(array[p_referee, p_assistant1, p_assistant2], null);
begin
  if not public.owns_match(p_match_id) or not public.referees_feature_on() then
    raise exception 'Yetkiniz yok.';
  end if;
  select coalesce(m.league_id, s.league_id) into v_league
    from public.matches m left join public.seasons s on s.id = m.season_id
   where m.id = p_match_id;
  if (select count(distinct x) from unnest(v_ids) x) <> cardinality(v_ids) then
    raise exception 'Aynı hakem iki görevde olamaz.';
  end if;
  if exists (select 1 from unnest(v_ids) x
              where not exists (select 1 from public.league_referees lr
                                 where lr.league_id = v_league and lr.referee_id = x)) then
    raise exception 'Seçilen hakem bu turnuvanın listesinde değil.';
  end if;
  update public.matches
     set referee_id = p_referee,
         assistant_referee1_id = p_assistant1,
         assistant_referee2_id = p_assistant2,
         updated_at = now()
   where id = p_match_id;
  -- Hatırlatma gönderildiyse kaydı kalır; yeniden boşaltılırsa tekrar gitmez.
end;
$function$;
grant execute on function public.match_set_referees(uuid, uuid, uuid, uuid) to authenticated;

-- 5 gün içindeki, hakemi atanmamış maçlar (yöneticinin turnuvaları /
-- bölgeleri). Ana sayfa uyarısı.
create or replace function public.unassigned_referee_matches(p_league_id uuid)
returns table (id uuid, home_name text, away_name text, match_date date, match_time text)
language sql
stable
security definer
set search_path to ''
as $function$
  select m.id, th.name, ta.name, m.match_date::date, m.match_time::text
    from public.matches m
    left join public.teams th on th.id = m.home_team_id
    left join public.teams ta on ta.id = m.away_team_id
   where m.league_id = p_league_id
     and public.referees_feature_on()
     and public.owns_match(m.id)
     and m.deleted_at is null
     and m.status = 'notStarted'
     and m.referee_id is null
     and coalesce(trim(m.referee_name), '') = ''
     and m.match_date is not null
     and m.match_date::date between (now() at time zone 'Europe/Istanbul')::date
                                and (now() at time zone 'Europe/Istanbul')::date + 5
     and not public.is_demo_league(m.league_id)
   order by m.match_date, m.match_time
$function$;
grant execute on function public.unassigned_referee_matches(uuid) to authenticated;

-- Hakemin maçları (gelecek + geçmiş) ve görevi.
create or replace function public.referee_matches(p_referee_id uuid)
returns table (
  id uuid, league_id uuid, league_name text, season_id uuid,
  home_name text, away_name text, home_score int, away_score int,
  status text, match_date date, match_time text, week int,
  pitch_name text, role text
)
language sql
stable
security definer
set search_path to ''
as $function$
  select m.id, l.id, l.name, m.season_id, th.name, ta.name,
         m.home_score, m.away_score, m.status, m.match_date::date,
         m.match_time::text, m.week, p.name,
         case when m.referee_id = p_referee_id then 'center' else 'assistant' end
    from public.matches m
    join public.leagues l on l.id = m.league_id
    left join public.teams th on th.id = m.home_team_id
    left join public.teams ta on ta.id = m.away_team_id
    left join public.pitches p on p.id = m.pitch_id
   where m.deleted_at is null
     and p_referee_id in (m.referee_id, m.assistant_referee1_id, m.assistant_referee2_id)
     and public.can_view_league(l.id)
   order by m.match_date nulls last, m.match_time
$function$;
grant execute on function public.referee_matches(uuid) to anon, authenticated;

-- Hakemin turnuva bazında sayıları: orta/yardımcı maç, orta hakemken
-- girilen sarı/kırmızı/penaltı/gol (bitmiş maçlar).
create or replace function public.referee_stats(p_referee_id uuid)
returns table (
  league_id uuid, league_name text, center int, assistant int,
  yellow int, red int, penalty int, goals int
)
language sql
stable
security definer
set search_path to ''
as $function$
  with ms as (
    select m.id, m.league_id, (m.referee_id = p_referee_id) as is_center
      from public.matches m
     where m.deleted_at is null and m.status = 'finished'
       and p_referee_id in (m.referee_id, m.assistant_referee1_id, m.assistant_referee2_id)
       and public.can_view_league(m.league_id)
  ), ev as (
    select ms.league_id,
           count(*) filter (where e.event_type = 'yellow_card') y,
           count(*) filter (where e.event_type = 'red_card') r,
           count(*) filter (where e.event_type = 'goal' and e.is_penalty) pen,
           count(*) filter (where e.event_type = 'goal') g
      from ms join public.match_events e on e.match_id = ms.id
     where ms.is_center
     group by ms.league_id
  )
  select l.id, l.name,
         count(*) filter (where ms.is_center)::int,
         count(*) filter (where not ms.is_center)::int,
         coalesce(max(ev.y), 0)::int, coalesce(max(ev.r), 0)::int,
         coalesce(max(ev.pen), 0)::int, coalesce(max(ev.g), 0)::int
    from ms join public.leagues l on l.id = ms.league_id
    left join ev on ev.league_id = ms.league_id
   group by l.id, l.name
   order by l.name
$function$;
grant execute on function public.referee_stats(uuid) to anon, authenticated;

-- Hakem hesabı turnuvalarını görür (kapsam) ve hesap açabilir.
create or replace function public.my_league_ids()
 returns uuid[]
 language sql
 stable security definer
 set search_path to ''
as $function$
  with me as (
    select auth.uid() as uid,
           split_part(coalesce(auth.jwt() ->> 'email', ''), '@', 1) as raw
  ),
  ids as (
    select s.league_id
    from public.season_team_players stp
    join public.players p on p.id = stp.player_id
    join public.seasons s on s.id = stp.season_id
    cross join me
    where coalesce(stp.is_active, true)
      and (p.auth_uid = me.uid
           or (me.raw ~ '^5[0-9]{9}$' and public.phone_raw10(p.phone) = me.raw))
    union
    select s.league_id
    from public.team_managers tm
    join public.seasons s on s.id = tm.season_id
    cross join me where tm.user_id = me.uid
    union
    select s.league_id
    from public.teams t
    join public.season_teams st on st.team_id = t.id
    join public.seasons s on s.id = st.season_id
    cross join me where t.manager_id = me.uid
    union
    select o.league_id from public.league_owners o, me where o.user_id = me.uid
    union
    select s.league_id
    from public.region_owners ro
    join public.season_regions r on r.id = ro.region_id
    join public.seasons s on s.id = r.season_id
    cross join me where ro.user_id = me.uid
    union
    select coalesce(m.league_id, s.league_id)
    from public.matches m
    left join public.seasons s on s.id = m.season_id
    cross join me where m.observer_id = me.uid
    union
    select f.league_id from public.league_followers f, me where f.user_id = me.uid
    union
    select lr.league_id
    from public.league_referees lr
    join public.referee_contacts c on c.referee_id = lr.referee_id
    cross join me where me.raw ~ '^5[0-9]{9}$' and c.phone_raw10 = me.raw
  )
  select coalesce(array_agg(distinct league_id), '{}')
  from ids where league_id is not null
$function$;

create or replace function public.request_account_password(p_phone text, p_full_name text DEFAULT NULL::text, p_reset boolean DEFAULT false)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  if p_reset and not v_has_account and not exists (
    select 1 from public.players p where public.phone_raw10(p.phone) = v_raw
  ) then
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
       select 1 from public.team_manager_contacts c where c.phone_raw10 = v_raw
     )
     and not exists (
       select 1 from public.referee_contacts c where c.phone_raw10 = v_raw
     ) then
    return 'unknown_phone';
  end if;

  -- Davetli sahibin / sorumlunun / hakemin adı talepte görünsün.
  if v_name is null then
    select full_name into v_name from (
      select full_name, created_at from public.league_owner_invites
      where phone_raw10 = v_raw
      union all
      select full_name, created_at from public.region_owner_invites
      where phone_raw10 = v_raw
      union all
      select t.manager_name, c.updated_at from public.team_manager_contacts c
      join public.teams t on t.id = c.team_id
      where c.phone_raw10 = v_raw
      union all
      select r.name, r.created_at from public.referee_contacts c
      join public.referees r on r.id = c.referee_id
      where c.phone_raw10 = v_raw
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
$function$;

-- 5 gün kala hakem atanmamış maç: maç başına bir kez kurucu başkanlara ve
-- maçın bölge sorumlularına bildirim (özellik herkese açıkken).
create table if not exists public.referee_reminders (
  match_id uuid primary key references public.matches(id) on delete cascade,
  sent_at timestamptz not null default now()
);
alter table public.referee_reminders enable row level security;
revoke all on public.referee_reminders from anon, authenticated;

create or replace function public.referee_reminder_tick()
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r record;
  v_users uuid[];
  v_today date := (now() at time zone 'Europe/Istanbul')::date;
begin
  if not coalesce((select value = 'true'::jsonb from public.app_settings
                    where key = 'referees_enabled'), false) then
    return;
  end if;
  for r in
    select m.id, m.league_id, m.group_id, m.match_date::date as d,
           left(coalesce(m.match_time::text, ''), 5) as t,
           coalesce(th.name, '') || ' - ' || coalesce(ta.name, '') as title
      from public.matches m
      left join public.teams th on th.id = m.home_team_id
      left join public.teams ta on ta.id = m.away_team_id
     where m.deleted_at is null
       and m.status = 'notStarted'
       and m.referee_id is null
       and coalesce(trim(m.referee_name), '') = ''
       and m.match_date::date between v_today and v_today + 5
       and not public.is_demo_league(m.league_id)
       and not exists (select 1 from public.referee_reminders x where x.match_id = m.id)
     limit 200
  loop
    insert into public.referee_reminders (match_id) values (r.id)
    on conflict do nothing;
    select array_agg(distinct u) into v_users from (
      select lo.user_id u from public.league_owners lo where lo.league_id = r.league_id
      union
      select ro.user_id from public.groups g
        join public.region_owners ro on ro.region_id = g.region_id
       where g.id = r.group_id
    ) x;
    if v_users is not null then
      perform public.push_send(
        v_users,
        'Hakem atanmadı',
        r.title || ' · ' || to_char(r.d, 'DD.MM') ||
          case when r.t <> '' then ' ' || r.t else '' end ||
          ' maçına henüz hakem seçilmedi. Dokun, hemen ata.',
        '/?n=referee-' || r.id,
        'referee-' || r.id
      );
    end if;
  end loop;
end;
$function$;
revoke all on function public.referee_reminder_tick() from public, anon, authenticated;

select cron.unschedule('referee-reminder')
 where exists (select 1 from cron.job where jobname = 'referee-reminder');
-- Her gün 10:00 (TSİ = 07:00 UTC).
select cron.schedule('referee-reminder', '0 7 * * *',
  'select public.referee_reminder_tick()');
