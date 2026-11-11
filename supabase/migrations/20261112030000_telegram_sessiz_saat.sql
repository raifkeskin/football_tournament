-- Telegram sessiz saatleri: 00:00-10:00 (İstanbul) arasında hiçbir Telegram
-- bildirimi gönderilmez. Bu aralıkta gelenler sırada bekler ve saat 10:00'da
-- gönderilir (kaybolmaz). Gol kesiti uyarısı sessiz saatte hiç kuyruğa
-- girmez; 10:00'da durum yeniden bakılır (kesit bu arada üretildiyse uyarı çıkmaz).

alter table public.telegram_outbox add column if not exists send_after timestamptz;
alter table public.telegram_outbox drop constraint if exists telegram_outbox_status_check;
alter table public.telegram_outbox add constraint telegram_outbox_status_check
  check (status = any (array['pending','sent','failed','queued']));

create or replace function public.telegram_quiet_now()
returns boolean
language sql
stable
as $$
  select extract(hour from now() at time zone 'Europe/Istanbul') < 10
$$;

-- Bir sonraki 10:00 (İstanbul).
create or replace function public.telegram_quiet_until()
returns timestamptz
language sql
stable
as $$
  select (date_trunc('day', now() at time zone 'Europe/Istanbul') + interval '10 hours')
         at time zone 'Europe/Istanbul'
$$;

create or replace function public.telegram_notify(p_user_ids uuid[], p_text text, p_buttons jsonb default null::jsonb, p_photo text default null::text)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_chat bigint;
  v_markup jsonb;
  v_id bigint;
  v_quiet boolean := public.telegram_quiet_now();
  v_until timestamptz := public.telegram_quiet_until();
begin
  if not exists (
    select 1 from public.app_private_settings
    where key = 'telegram_bot_token' and coalesce(value, '') <> ''
  ) then
    return;
  end if;

  v_markup := jsonb_build_object(
    'inline_keyboard',
    coalesce(p_buttons, '[]'::jsonb) || jsonb_build_array(jsonb_build_array(
      jsonb_build_object('text', 'Siteyi Aç', 'url', 'https://ligmasasi.com')
    ))
  );

  for v_chat in
    select distinct chat_id from public.telegram_links where user_id = any (p_user_ids)
  loop
    if coalesce(p_photo, '') <> '' then
      insert into public.telegram_outbox (method, body, status, send_after)
      values ('sendPhoto', jsonb_build_object('chat_id', v_chat, 'photo', p_photo,
                                              'caption', p_text, 'reply_markup', v_markup),
              case when v_quiet then 'queued' else 'pending' end,
              case when v_quiet then v_until end)
      returning id into v_id;
    else
      insert into public.telegram_outbox (method, body, status, send_after)
      values ('sendMessage', jsonb_build_object('chat_id', v_chat, 'text', p_text,
                                                'reply_markup', v_markup),
              case when v_quiet then 'queued' else 'pending' end,
              case when v_quiet then v_until end)
      returning id into v_id;
    end if;
    if not v_quiet then
      perform public.telegram_outbox_send(v_id);
    end if;
  end loop;
exception when others then
  raise warning 'telegram_notify: %', sqlerrm;
end;
$function$;

-- Kuyrukta bekleyenleri saati gelince gönder (retry her dakika çalışır).
create or replace function public.telegram_outbox_release()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  r record;
begin
  if public.telegram_quiet_now() then
    return;
  end if;
  for r in
    select id from public.telegram_outbox
     where status = 'queued' and send_after <= now()
     order by id limit 100
  loop
    update public.telegram_outbox set status = 'pending', updated_at = now() where id = r.id;
    perform public.telegram_outbox_send(r.id);
  end loop;
end;
$$;
revoke all on function public.telegram_outbox_release() from public, anon, authenticated;

select cron.unschedule('telegram-outbox-release')
 where exists (select 1 from cron.job where jobname = 'telegram-outbox-release');
select cron.schedule('telegram-outbox-release', '* * * * *',
                     'select public.telegram_outbox_release()');
