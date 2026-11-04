-- Kaynak kullanımı: trafik (indirilen veri), depolama ve Drive arşivi.
--   usage_hourly  saatlik trafik; usage-collect işlevi Supabase istek
--                 kayıtlarından (edge_logs, yanıt boyutu) her saat yazar.
--                 kind: video (clips deposu) / dosya (diğer depolama) /
--                 veri (REST; çoğu yanıtta boyut yazmaz, eksik sayılır) /
--                 canli / diger. cache: HIT ise Supabase "önbellekli trafik"
--                 sayar (ayrı kota).
--   usage_drive   Mac'teki gol betiğinin günlük ölçtüğü Drive LigMasasi boyutu.
-- admin_usage_stats() İstatistikler ekranını besler. usage_alarm_check()
-- kotanın %70'ini geçen kalem için ayda bir kez Telegram uyarısı yollar.

create table if not exists public.usage_hourly (
  hour timestamptz not null,
  kind text not null,
  cache text not null default '',
  requests bigint not null default 0,
  bytes bigint not null default 0,
  primary key (hour, kind, cache)
);
alter table public.usage_hourly enable row level security;

create table if not exists public.usage_drive (
  day date primary key,
  bytes bigint not null,
  by_league jsonb not null default '{}'::jsonb
);
alter table public.usage_drive enable row level security;

-- Pro paket kotaları (GB); paket değişirse buradan güncellenir.
insert into public.app_settings (key, value) values
  ('usage_quotas', '{"egress_gb": 250, "cached_egress_gb": 250, "storage_gb": 100}'::jsonb)
on conflict (key) do nothing;

create or replace function public.admin_usage_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_month timestamptz := date_trunc('month', now());
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.';
  end if;
  return jsonb_build_object(
    'quotas', (select value from public.app_settings where key = 'usage_quotas'),
    'collected_since', (select min(hour) from public.usage_hourly),
    'last_hour', (select max(hour) from public.usage_hourly),
    -- Bu ay: önbelleksiz ve önbellekli trafik, türe göre.
    'month', coalesce((
      select jsonb_object_agg(kind, jsonb_build_object('bytes', b, 'cached', c, 'requests', r))
        from (select kind,
                     sum(bytes) filter (where cache <> 'HIT') as b,
                     sum(bytes) filter (where cache = 'HIT') as c,
                     sum(requests) as r
                from public.usage_hourly where hour >= v_month group by kind) t
    ), '{}'::jsonb),
    -- Son 30 gün, gün gün (İstanbul saatiyle).
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object('day', d, 'bytes', b, 'cached', c) order by d)
        from (select (hour at time zone 'Europe/Istanbul')::date as d,
                     sum(bytes) filter (where cache <> 'HIT') as b,
                     sum(bytes) filter (where cache = 'HIT') as c
                from public.usage_hourly
               where hour >= now() - interval '30 days' group by 1) t
    ), '[]'::jsonb),
    -- Depolama: depo (bucket) bazında.
    'storage', coalesce((
      select jsonb_object_agg(bucket_id, jsonb_build_object('bytes', b, 'files', n))
        from (select bucket_id, sum(coalesce((metadata ->> 'size')::bigint, 0)) as b, count(*) as n
                from storage.objects group by bucket_id) t
    ), '{}'::jsonb),
    -- Depolamada en çok yer kaplayan turnuvalar (maç yolundaki kimlikten).
    'storage_leagues', coalesce((
      select jsonb_agg(jsonb_build_object('league', name, 'bytes', b) order by b desc)
        from (select l.name, sum(coalesce((o.metadata ->> 'size')::bigint, 0)) as b
                from storage.objects o
                -- Gol videosu yolunda maç kimliği var; maç fotoğrafı
                -- match_media adresinden bulunur.
                join public.matches m
                  on m.id = coalesce(
                       substring(o.name from '^goals/([0-9a-f-]{36})/')::uuid,
                       (select mm.match_id from public.match_media mm
                         where o.bucket_id = 'media' and mm.url like '%/' || o.name
                         limit 1))
                join public.leagues l on l.id = m.league_id
               group by l.name
               order by 2 desc
               limit 6) t
    ), '[]'::jsonb),
    'drive', (select jsonb_build_object('day', day, 'bytes', bytes, 'by_league', by_league)
                from public.usage_drive order by day desc limit 1)
  );
end;
$$;

revoke all on function public.admin_usage_stats() from public, anon;
grant execute on function public.admin_usage_stats() to authenticated;

-- %70 uyarısı: bu ay önbelleksiz / önbellekli trafik ve depolama. Her kalem
-- için ayda bir kez (app_private_settings'te işaret).
create or replace function public.usage_alarm_check()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  q jsonb := (select value from public.app_settings where key = 'usage_quotas');
  v_month timestamptz := date_trunc('month', now());
  v_tag text := to_char(now(), 'YYYYMM');
  r record;
  v_admins uuid[] := (select array_agg(user_id) from public.admins);
begin
  for r in
    select 'egress' as k, 'Trafik' as label, (q ->> 'egress_gb')::numeric as quota,
           coalesce(sum(bytes) filter (where cache <> 'HIT'), 0) / 1e9 as used
      from public.usage_hourly where hour >= v_month
    union all
    select 'cached', 'Önbellekli trafik', (q ->> 'cached_egress_gb')::numeric,
           coalesce(sum(bytes) filter (where cache = 'HIT'), 0) / 1e9
      from public.usage_hourly where hour >= v_month
    union all
    select 'storage', 'Depolama', (q ->> 'storage_gb')::numeric,
           coalesce(sum((metadata ->> 'size')::bigint), 0) / 1e9
      from storage.objects
  loop
    if r.quota > 0 and r.used >= r.quota * 0.7
       and not exists (select 1 from public.app_private_settings
                        where key = 'usage_alarm_' || r.k || '_' || v_tag) then
      insert into public.app_private_settings (key, value)
      values ('usage_alarm_' || r.k || '_' || v_tag, 'true');
      if v_admins is not null then
        perform public.telegram_notify(
          v_admins,
          format('⚠️ %s kotanın %%%s''ine ulaştı: %s / %s GB (bu ay). R2''ye geçiş zamanı yaklaşıyor.',
                 r.label, round(r.used / r.quota * 100), round(r.used, 1), r.quota));
      end if;
    end if;
  end loop;
end;
$$;

revoke all on function public.usage_alarm_check() from public, anon, authenticated;
grant execute on function public.usage_alarm_check() to service_role;

-- Saatlik toplama: usage-collect işlevini çağırır (drive-sync ile aynı gizli
-- anahtar).
create or replace function public.usage_collect_tick()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_secret text;
begin
  select value into v_secret from public.app_private_settings
   where key = 'drive_sync_secret';
  if v_secret is null then
    return;
  end if;
  perform net.http_post(
    url := 'https://qxdjebzszikeslobrozf.supabase.co/functions/v1/usage-collect',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-sync-secret', v_secret),
    timeout_milliseconds := 60000
  );
exception when others then
  raise warning 'usage_collect_tick: %', sqlerrm;
end;
$$;

revoke all on function public.usage_collect_tick() from public, anon, authenticated;

select cron.unschedule('usage-collect') where exists (select 1 from cron.job where jobname = 'usage-collect');
select cron.schedule('usage-collect', '7 * * * *', 'select public.usage_collect_tick()');
