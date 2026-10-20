-- Yapay Zekâ Yönetimi (yalnız admin):
--  * Sezon bazında aç/kapa: esame okuma, gol videosu yakalama.
--  * Model seçimi (flash / pro): sunucu fonksiyonları her işlemde okur.
--  * İşlem başına TL maliyet: işlem anındaki TCMB dolar satış kuru
--    (sunucu fonksiyonu günde bir kez günceller) ile hesaplanıp saklanır.

-- 1) Sezon bayrakları ---------------------------------------------------------
alter table public.seasons
  add column if not exists ai_esame_enabled boolean not null default true,
  add column if not exists ai_clips_enabled boolean not null default true;

-- Sezonu düzenleyebilen kurucu başkan bu iki alanı değiştiremez; ileride
-- ücretli üyelikle açılacak özellikler.
create or replace function public.seasons_ai_flags_guard()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.ai_esame_enabled := true;
    new.ai_clips_enabled := true;
  else
    new.ai_esame_enabled := old.ai_esame_enabled;
    new.ai_clips_enabled := old.ai_clips_enabled;
  end if;
  return new;
end $$;

drop trigger if exists seasons_ai_flags_guard on public.seasons;
create trigger seasons_ai_flags_guard
  before insert or update on public.seasons
  for each row execute function public.seasons_ai_flags_guard();

-- 2) Model ve kur ayarları ----------------------------------------------------
insert into public.app_private_settings (key, value) values
  ('ai_model_esame', 'flash'),
  ('ai_model_clips', 'flash'),
  ('usd_try', '49.5523'),
  ('usd_try_date', '19.10.2026')
on conflict (key) do nothing;

-- 3) İşlem başına TL ----------------------------------------------------------
alter table public.ai_usage_log
  add column if not exists usd_try numeric(10,4),
  add column if not exists cost_try numeric(12,4);

create or replace function public.ai_usage_log_try()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.usd_try is null then
    select nullif(value, '')::numeric into new.usd_try
      from public.app_private_settings where key = 'usd_try';
  end if;
  new.cost_try := round(new.cost_usd * coalesce(new.usd_try, 0), 4);
  return new;
end $$;

drop trigger if exists ai_usage_log_try on public.ai_usage_log;
create trigger ai_usage_log_try
  before insert on public.ai_usage_log
  for each row execute function public.ai_usage_log_try();

-- Eski kayıtlar bugünkü kurla.
update public.ai_usage_log
   set usd_try = 49.5523, cost_try = round(cost_usd * 49.5523, 4)
 where usd_try is null;

-- 4) Admin RPC'leri -----------------------------------------------------------
create or replace function public.ai_admin_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  r jsonb;
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.';
  end if;
  select jsonb_object_agg(key, value) into r
    from public.app_private_settings
   where key in ('ai_model_esame', 'ai_model_clips', 'usd_try',
                 'usd_try_date', 'ai_clip_monthly_usd');
  return coalesce(r, '{}'::jsonb);
end $$;

create or replace function public.ai_admin_set_model(p_purpose text, p_model text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.';
  end if;
  if p_purpose not in ('esame', 'clips') or p_model not in ('flash', 'pro') then
    raise exception 'Geçersiz seçim.';
  end if;
  insert into public.app_private_settings (key, value, updated_at)
  values ('ai_model_' || p_purpose, p_model, now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
end $$;

-- İşlem listesi: esame her okuma ayrı; gol videosu bir maçın aynı gündeki
-- adımları (başlangıç bulma, gol tarama) tek işlem.
create or replace function public.ai_usage_list(p_from timestamptz, p_to timestamptz)
returns table (
  at timestamptz,
  kind text,
  model text,
  match_id uuid,
  home_name text,
  away_name text,
  league_name text,
  cost_usd numeric,
  cost_try numeric
)
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.';
  end if;
  return query
  with ops as (
    select max(l.created_at) as at,
           case when l.purpose = 'esame' then 'esame' else 'clips' end as kind,
           max(l.model) as model,
           l.match_id,
           sum(l.cost_usd) as cost_usd,
           sum(l.cost_try) as cost_try
      from public.ai_usage_log l
     where l.created_at >= p_from and l.created_at < p_to
     group by case when l.purpose = 'esame' then l.id::text
                   else coalesce(l.match_id::text, '') || '|' ||
                        ((l.created_at at time zone 'Europe/Istanbul')::date)::text
              end,
              case when l.purpose = 'esame' then 'esame' else 'clips' end,
              l.match_id
  )
  select o.at, o.kind, o.model, o.match_id,
         th.name::text, ta.name::text, lg.name::text,
         round(o.cost_usd, 5), round(o.cost_try, 2)
    from ops o
    left join public.matches m on m.id = o.match_id
    left join public.teams th on th.id = m.home_team_id
    left join public.teams ta on ta.id = m.away_team_id
    left join public.seasons s on s.id = m.season_id
    left join public.leagues lg on lg.id = s.league_id
   order by o.at desc;
end $$;

revoke all on function public.ai_admin_settings() from public, anon;
revoke all on function public.ai_admin_set_model(text, text) from public, anon;
revoke all on function public.ai_usage_list(timestamptz, timestamptz) from public, anon;
grant execute on function public.ai_admin_settings() to authenticated;
grant execute on function public.ai_admin_set_model(text, text) to authenticated;
grant execute on function public.ai_usage_list(timestamptz, timestamptz) to authenticated;
