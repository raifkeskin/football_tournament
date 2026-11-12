-- İstatistikler: İletiMerkezi SMS bakiyesi + eşik altı Telegram uyarısı.
-- Bakiye 15 dakikada bir pg_net ile sorulur; yanıt bir sonraki turda okunur.
insert into public.app_settings (key, value) values ('sms_low_threshold', '1000'::jsonb)
on conflict (key) do nothing;

create or replace function public.sms_balance_tick()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_req bigint;
  v_content text;
  v_bal int;
  v_thr int;
  v_alerted boolean;
  v_key text;
  v_hash text;
  v_new bigint;
  v_admins uuid[] := (select array_agg(user_id) from public.admins where user_id is not null);
begin
  select nullif(value, '')::bigint into v_req
    from public.app_private_settings where key = 'sms_balance_req';
  if v_req is not null then
    select content into v_content from net._http_response
     where id = v_req and status_code = 200;
    if v_content is not null then
      begin
        v_bal := (v_content::jsonb #>> '{response,balance,sms}')::int;
      exception when others then v_bal := null;
      end;
      if v_bal is not null then
        insert into public.app_private_settings (key, value)
        values ('sms_balance', v_bal::text), ('sms_balance_at', now()::text)
        on conflict (key) do update set value = excluded.value;
        v_thr := coalesce((select (value #>> '{}')::int from public.app_settings
                            where key = 'sms_low_threshold'), 1000);
        v_alerted := coalesce((select value from public.app_private_settings
                                where key = 'sms_balance_alerted'), 'false') = 'true';
        if v_bal < v_thr and not v_alerted then
          insert into public.app_private_settings (key, value)
          values ('sms_balance_alerted', 'true')
          on conflict (key) do update set value = 'true';
          if v_admins is not null then
            perform public.telegram_notify(
              v_admins,
              '⚠️ SMS bakiyeniz ' || replace(to_char(v_thr, 'FM999,999'), ',', '.')
                || '''in altına düştü: ' || replace(to_char(v_bal, 'FM999,999'), ',', '.')
                || ' SMS kaldı. İletiMerkezi › Ödemeler › SMS Satın Al.');
          end if;
        elsif v_bal >= v_thr and v_alerted then
          update public.app_private_settings set value = 'false'
           where key = 'sms_balance_alerted';
        end if;
      end if;
    end if;
  end if;

  select value into v_key from public.app_private_settings where key = 'iletimerkezi_key';
  select value into v_hash from public.app_private_settings where key = 'iletimerkezi_hash';
  if coalesce(v_key, '') = '' or coalesce(v_hash, '') = '' then
    return;
  end if;
  select net.http_post(
    url := 'https://api.iletimerkezi.com/v1/get-balance/json',
    body := jsonb_build_object('request', jsonb_build_object(
      'authentication', jsonb_build_object('key', v_key, 'hash', v_hash))),
    headers := '{"Content-Type": "application/json"}'::jsonb
  ) into v_new;
  insert into public.app_private_settings (key, value) values ('sms_balance_req', v_new::text)
  on conflict (key) do update set value = excluded.value;
end;
$$;
revoke all on function public.sms_balance_tick() from public, anon, authenticated;

create or replace function public.sms_balance_refresh()
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.';
  end if;
  perform public.sms_balance_tick();
end;
$$;
revoke all on function public.sms_balance_refresh() from public, anon;
grant execute on function public.sms_balance_refresh() to authenticated;

select cron.schedule('sms-balance', '*/15 * * * *', 'select public.sms_balance_tick()');

CREATE OR REPLACE FUNCTION public.admin_usage_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    'sms', jsonb_build_object(
      'balance', (select nullif(value, '')::int from public.app_private_settings where key = 'sms_balance'),
      'at', (select value from public.app_private_settings where key = 'sms_balance_at'),
      'threshold', coalesce((select (value #>> '{}')::int from public.app_settings where key = 'sms_low_threshold'), 1000)),
    'drive', (select jsonb_build_object('day', day, 'bytes', bytes, 'by_league', by_league)
                from public.usage_drive order by day desc limit 1)
  );
end;
$function$;
