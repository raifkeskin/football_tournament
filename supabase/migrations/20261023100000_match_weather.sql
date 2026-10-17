-- Maç saatinde hava durumu.
--
-- * Saha koordinatı: sahanın Google Maps linki (location) girildiğinde ya da
--   değiştiğinde match-weather edge function'ı bir kez çağrılır; link
--   çözülür, adres OpenStreetMap (Photon) ile koordinata çevrilir ve
--   pitches.lat/lng'ye yazılır. geo_location = çözülen link; link
--   değişmedikçe bir daha sorulmaz. Bulunamazsa ilçe, o da yoksa Beşiktaş.
-- * Tahmin: saatlik cron (weather_tick) yalnız gereken maç varsa function'ı
--   çağırır. Pencere: maça 5 gün kalandan başlama saatine kadar; normalde
--   6 saatte bir, son 24 saatte saatte bir yenilenir (OpenWeatherMap 5 gün /
--   3 saatlik tahmin, aynı konum tek istek). Başlama saati geçince satır
--   dondurulur (frozen) ve "maç oynanırken" havası olarak kalır.
-- * Uygulama match_weather'ı okur; hava servisine istemci hiç gitmez.
--
-- Eski sürümler yeni sütun/tabloyu kullanmaz (pitches select=* zararsız).

alter table public.pitches
  add column if not exists lat double precision,
  add column if not exists lng double precision,
  add column if not exists geo_location text,
  add column if not exists geo_area text,
  add column if not exists geo_precision text;

comment on column public.pitches.geo_location is
  'Koordinatın çıkarıldığı location değeri; location bundan farklıysa yeniden çözülür.';
comment on column public.pitches.geo_area is 'Panelde gösterilen bölge (ilçe), ör. Kağıthane.';
comment on column public.pitches.geo_precision is 'link | saha | adres | ilce | varsayilan';

create table if not exists public.match_weather (
  match_id     uuid primary key references public.matches(id) on delete cascade,
  pitch_id     uuid references public.pitches(id) on delete set null,
  kickoff_at   timestamptz not null,
  slot_at      timestamptz not null,
  temp         numeric(4,1) not null,
  feels_like   numeric(4,1),
  humidity     smallint,
  wind_kmh     numeric(5,1),
  pop          smallint,          -- yağış olasılığı, %
  rain_mm      numeric(5,1),      -- 3 saatlik yağış
  code         smallint not null, -- OpenWeatherMap hava kodu
  description  text,
  is_day       boolean not null default true,
  frozen       boolean not null default false,
  updated_at   timestamptz not null default now()
);

alter table public.match_weather enable row level security;
drop policy if exists match_weather_read on public.match_weather;
create policy match_weather_read on public.match_weather
  for select to anon, authenticated using (true);
grant select on public.match_weather to anon, authenticated;

insert into public.app_private_settings (key, value)
values ('weather_sync_secret', encode(extensions.gen_random_bytes(24), 'hex'))
on conflict (key) do nothing;

-- Maçın başlama anı (İstanbul saati); saati girilmemiş maçta null.
create or replace function public.match_kickoff_at(p_date date, p_time text)
returns timestamptz
language sql
stable
set search_path to ''
as $$
  select case
    when p_date is null or coalesce(p_time, '') !~ '^\s*\d{1,2}:\d{2}' then null
    else (p_date + substring(trim(p_time) from '^\d{1,2}:\d{2}')::time)
           at time zone 'Europe/Istanbul'
  end
$$;

create or replace function public.weather_call(p_body jsonb)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_secret text;
begin
  select value into v_secret from public.app_private_settings
   where key = 'weather_sync_secret';
  perform net.http_post(
    url := 'https://qxdjebzszikeslobrozf.supabase.co/functions/v1/match-weather',
    body := p_body,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-sync-secret', v_secret
    ),
    timeout_milliseconds := 60000
  );
exception when others then
  raise warning 'weather_call: %', sqlerrm;
end;
$$;

revoke all on function public.weather_call(jsonb) from public, anon, authenticated;

-- Saha linki değişince koordinatı bir kez çöz.
create or replace function public.pitch_geocode_trigger()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.location is distinct from new.geo_location
     or (new.lat is null and new.geo_location is null) then
    perform public.weather_call(jsonb_build_object('action', 'geocode', 'pitch_id', new.id));
  end if;
  return null;
end;
$$;

drop trigger if exists pitch_geocode on public.pitches;
create trigger pitch_geocode
  after insert or update of location on public.pitches
  for each row execute function public.pitch_geocode_trigger();

-- Tahmini yenilenmesi gereken maçlar (edge function ve cron kullanır).
create or replace function public.weather_due_matches()
returns table (match_id uuid, pitch_id uuid, kickoff_at timestamptz, lat double precision, lng double precision)
language sql
stable
security definer
set search_path to ''
as $$
  select m.id, p.id, k.kickoff_at, p.lat, p.lng
    from public.matches m
    join public.pitches p on p.id = m.pitch_id
    cross join lateral (select public.match_kickoff_at(m.match_date, m.match_time) as kickoff_at) k
    left join public.match_weather w on w.match_id = m.id
   where m.deleted_at is null
     and m.status in ('notStarted', 'postponed')
     and p.lat is not null
     and k.kickoff_at > now()
     and k.kickoff_at < now() + interval '5 days'
     and (w.match_id is null
          or w.kickoff_at is distinct from k.kickoff_at
          or w.pitch_id is distinct from p.id
          or w.updated_at < now() - case when k.kickoff_at < now() + interval '24 hours'
                                         then interval '55 minutes'
                                         else interval '6 hours' end)
$$;

revoke all on function public.weather_due_matches() from public, anon, authenticated;

create or replace function public.weather_tick()
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  -- Başlama saati geçen maçın havası dondurulur.
  update public.match_weather w
     set frozen = true
   where not w.frozen and w.kickoff_at <= now();
  -- Tarihi/sahası değişip penceresinden çıkan maçın eski tahmini silinir.
  delete from public.match_weather w
   using public.matches m
   where m.id = w.match_id and not w.frozen
     and public.match_kickoff_at(m.match_date, m.match_time) is distinct from w.kickoff_at
     and coalesce(public.match_kickoff_at(m.match_date, m.match_time), now() + interval '1 year')
         >= now() + interval '5 days';
  if exists (select 1 from public.weather_due_matches()) then
    perform public.weather_call(jsonb_build_object('action', 'refresh'));
  end if;
exception when others then
  raise warning 'weather_tick: %', sqlerrm;
end;
$$;

revoke all on function public.weather_tick() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'match-weather';
select cron.schedule('match-weather', '7 * * * *', 'select public.weather_tick()');

grant execute on function public.weather_due_matches() to service_role;
