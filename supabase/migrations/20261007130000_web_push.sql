-- Web Push bildirimleri (Firebase'siz): tarayıcı abonelikleri burada saklanır,
-- gönderimi send-push Edge Function'ı yapar (VAPID). Tetikleyiciler:
--   * maç tarihi/saati belirlendi ya da değişti
--   * maçtan 2 saat önce hatırlatma (pg_cron, 10 dakikada bir)
--   * maç sonucu
--   * yayınlanan haber
-- Alıcılar: maçın takımlarındaki aktif oyuncular (hesabı olanlar), takım
-- sorumluları, turnuva sahipleri; sonuç ve haberde turnuvayı takip edenler de.

create extension if not exists pg_cron;

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  platform text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists push_subscriptions_user_idx
  on public.push_subscriptions (user_id);

alter table public.push_subscriptions enable row level security;

drop policy if exists push_subscriptions_own on public.push_subscriptions;
create policy push_subscriptions_own on public.push_subscriptions
  for select to authenticated using (user_id = auth.uid());

revoke insert, update, delete on public.push_subscriptions from anon, authenticated;

-- Aynı cihaz/tarayıcı başka hesaba geçtiyse abonelik yeni hesaba taşınır.
create or replace function public.save_push_subscription(
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_platform text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Giriş yapmalısınız.';
  end if;
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, platform)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth, p_platform)
  on conflict (endpoint) do update
    set user_id = excluded.user_id,
        p256dh = excluded.p256dh,
        auth = excluded.auth,
        platform = excluded.platform,
        updated_at = now();
end;
$$;

create or replace function public.delete_push_subscription(p_endpoint text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.push_subscriptions
  where endpoint = p_endpoint and user_id = auth.uid();
$$;

revoke all on function public.save_push_subscription(text, text, text, text) from public, anon;
revoke all on function public.delete_push_subscription(text) from public, anon;
grant execute on function public.save_push_subscription(text, text, text, text) to authenticated;
grant execute on function public.delete_push_subscription(text) to authenticated;

-- Gönderim: aboneliği olan alıcı varsa Edge Function'a iletir. Hata maç /
-- haber kaydını asla engellemez.
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
begin
  if p_user_ids is null or not exists (
    select 1 from public.push_subscriptions where user_id = any (p_user_ids)
  ) then
    return;
  end if;
  select value into v_secret from public.app_private_settings where key = 'push_secret';
  if coalesce(v_secret, '') = '' then
    return;
  end if;
  perform net.http_post(
    url := 'https://qxdjebzszikeslobrozf.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'user_ids', to_jsonb(p_user_ids),
      'title', p_title,
      'body', p_body,
      'url', coalesce(p_url, '/'),
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

revoke all on function public.push_send(uuid[], text, text, text, text) from public, anon, authenticated;

-- Maçla ilgili kişiler.
create or replace function public.match_audience(
  p_match_id uuid,
  p_include_followers boolean
)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  with m as (
    select season_id, league_id, home_team_id, away_team_id
    from public.matches where id = p_match_id
  ),
  ids as (
    select p.auth_uid as uid
    from public.season_team_players stp
    join public.players p on p.id = stp.player_id
    join m on stp.season_id = m.season_id
      and stp.team_id in (m.home_team_id, m.away_team_id)
    where stp.is_active
    union
    select tm.user_id from public.team_managers tm
    join m on tm.season_id = m.season_id
      and tm.team_id in (m.home_team_id, m.away_team_id)
    union
    select o.user_id from public.league_owners o
    join m on o.league_id = m.league_id
    union
    select f.user_id from public.league_followers f
    join m on f.league_id = m.league_id
    where p_include_followers
  )
  select coalesce(array_agg(distinct uid), '{}') from ids where uid is not null
$$;

-- "Yeşil FK - Beyaz FK"
create or replace function public.match_title(p_match_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(h.name, '?') || ' - ' || coalesce(a.name, '?')
  from public.matches m
  left join public.teams h on h.id = m.home_team_id
  left join public.teams a on a.id = m.away_team_id
  where m.id = p_match_id
$$;

-- "29 Eylül 22:00"
create or replace function public.tr_match_when(p_date date, p_time text)
returns text
language sql
immutable
as $$
  select extract(day from p_date)::int || ' ' ||
    (array['Ocak','Şubat','Mart','Nisan','Mayıs','Haziran','Temmuz',
           'Ağustos','Eylül','Ekim','Kasım','Aralık'])[extract(month from p_date)::int] ||
    coalesce(' ' || nullif(left(coalesce(p_time, ''), 5), ''), '')
$$;

alter table public.matches add column if not exists reminder_sent_at timestamptz;

-- Tarih/saat değişirse hatırlatma yeniden gönderilebilir.
create or replace function public.matches_reset_reminder()
returns trigger
language plpgsql
as $$
begin
  if new.match_date is distinct from old.match_date
     or new.match_time is distinct from old.match_time then
    new.reminder_sent_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists matches_reset_reminder on public.matches;
create trigger matches_reset_reminder
  before update on public.matches
  for each row execute function public.matches_reset_reminder();

create or replace function public.matches_push_notify()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Uygulamada henüz adres (route) yok; bildirim ana sayfayı açar.
  v_url text := '/';
begin
  -- Sonuç
  if tg_op = 'UPDATE' and new.status = 'finished'
     and old.status is distinct from 'finished' then
    perform public.push_send(
      public.match_audience(new.id, true),
      'Maç sonucu',
      (select coalesce(h.name, '?') || ' ' || coalesce(new.home_score, 0) || ' - ' ||
              coalesce(new.away_score, 0) || ' ' || coalesce(a.name, '?')
       from public.teams h, public.teams a
       where h.id = new.home_team_id and a.id = new.away_team_id),
      v_url,
      'result-' || new.id
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
      public.match_title(new.id) || ' · ' ||
        public.tr_match_when(new.match_date, new.match_time),
      v_url,
      'schedule-' || new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists matches_push_notify on public.matches;
create trigger matches_push_notify
  after insert or update of status, match_date, match_time on public.matches
  for each row execute function public.matches_push_notify();

-- Maçtan 2 saat önce hatırlatma (saatler İstanbul saati).
create or replace function public.push_match_reminders()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  for r in
    select m.id, m.match_date, m.match_time
    from public.matches m
    where m.status = 'notStarted'
      and m.reminder_sent_at is null
      and m.match_date between current_date - 1 and current_date + 1
      and m.match_time ~ '^\d{1,2}:\d{2}'
      and ((m.match_date + left(m.match_time, 5)::time)
             at time zone 'Europe/Istanbul')
          between now() and now() + interval '2 hours'
  loop
    update public.matches set reminder_sent_at = now() where id = r.id;
    perform public.push_send(
      public.match_audience(r.id, false),
      'Maçın yaklaşıyor',
      public.match_title(r.id) || ' · Bugün ' || left(r.match_time, 5),
      '/',
      'reminder-' || r.id
    );
  end loop;
end;
$$;

revoke all on function public.push_match_reminders() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'push-match-reminders';
select cron.schedule('push-match-reminders', '*/10 * * * *',
  'select public.push_match_reminders()');

-- Haber yayınlandığında turnuvadaki herkese.
create or replace function public.news_push_notify()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
  v_league text;
begin
  if not coalesce(new.is_published, false) then
    return new;
  end if;
  if tg_op = 'UPDATE' and coalesce(old.is_published, false) then
    return new;
  end if;
  if new.league_id is null then
    return new;
  end if;

  select name into v_league from public.leagues where id = new.league_id;
  with ids as (
    select p.auth_uid as uid
    from public.season_team_players stp
    join public.seasons s on s.id = stp.season_id and s.is_active
    join public.players p on p.id = stp.player_id
    where s.league_id = new.league_id and stp.is_active
    union
    select tm.user_id from public.team_managers tm
    join public.seasons s on s.id = tm.season_id and s.is_active
    where s.league_id = new.league_id
    union
    select o.user_id from public.league_owners o where o.league_id = new.league_id
    union
    select f.user_id from public.league_followers f where f.league_id = new.league_id
  )
  select array_agg(distinct uid) into v_ids from ids where uid is not null;

  perform public.push_send(
    v_ids,
    coalesce(v_league, 'Turnuva') || ' · Yeni haber',
    left(regexp_replace(coalesce(new.content, ''), '\s+', ' ', 'g'), 120),
    '/',
    'news-' || new.id
  );
  return new;
end;
$$;

drop trigger if exists news_push_notify on public.news;
create trigger news_push_notify
  after insert or update of is_published on public.news
  for each row execute function public.news_push_notify();
