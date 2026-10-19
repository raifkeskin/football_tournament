-- Telegram bildirimleri kaybolmasın: 2026-10-19 14:53'te bir şifre talebi
-- bildirimi Telegram bağlantısı 5 sn'de kurulamadığı için gitmedi ve
-- yeniden denenmedi.
--
-- * Her mesaj telegram_outbox'a yazılır ve hemen gönderilir (süre 15 sn).
-- * telegram-outbox-retry (her dakika) cevabı kontrol eder: başarılıysa
--   'sent', değilse toplam 3 denemeye kadar yeniden gönderir; 3'te de
--   olmazsa 'failed'.
-- * 7 günden eski kayıtlar silinir.

create table if not exists public.telegram_outbox (
  id          bigint generated always as identity primary key,
  method      text not null check (method in ('sendMessage', 'sendPhoto')),
  body        jsonb not null,
  attempts    smallint not null default 0,
  request_id  bigint,
  status      text not null default 'pending'
                check (status in ('pending', 'sent', 'failed')),
  last_error  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists telegram_outbox_pending_idx
  on public.telegram_outbox (id) where status = 'pending';

alter table public.telegram_outbox enable row level security;
-- Politika yok: yalnız security definer fonksiyonlar erişir (gövdede
-- kişisel veri var).

-- Bir kaydı (yeniden) gönderir.
create or replace function public.telegram_outbox_send(p_id bigint)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_token text;
  r public.telegram_outbox;
  v_req bigint;
begin
  select value into v_token from public.app_private_settings where key = 'telegram_bot_token';
  if coalesce(v_token, '') = '' then
    return;
  end if;
  select * into r from public.telegram_outbox where id = p_id;
  if r.id is null then
    return;
  end if;
  v_req := net.http_post(
    url := 'https://api.telegram.org/bot' || v_token || '/' || r.method,
    body := r.body,
    headers := '{"Content-Type": "application/json"}'::jsonb,
    timeout_milliseconds := 15000
  );
  update public.telegram_outbox
  set attempts = attempts + 1, request_id = v_req, updated_at = now()
  where id = p_id;
end;
$$;
revoke all on function public.telegram_outbox_send(bigint) from public, anon, authenticated;

create or replace function public.telegram_notify(
  p_user_ids uuid[],
  p_text text,
  p_buttons jsonb default null,
  p_photo text default null
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_chat bigint;
  v_markup jsonb;
  v_id bigint;
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
      insert into public.telegram_outbox (method, body)
      values ('sendPhoto', jsonb_build_object('chat_id', v_chat, 'photo', p_photo,
                                              'caption', p_text, 'reply_markup', v_markup))
      returning id into v_id;
    else
      insert into public.telegram_outbox (method, body)
      values ('sendMessage', jsonb_build_object('chat_id', v_chat, 'text', p_text,
                                                'reply_markup', v_markup))
      returning id into v_id;
    end if;
    perform public.telegram_outbox_send(v_id);
  end loop;
exception when others then
  raise warning 'telegram_notify: %', sqlerrm;
end;
$$;

-- Cevapları kontrol eder, başarısızları yeniden dener (en çok 3 deneme).
create or replace function public.telegram_outbox_retry()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  r record;
begin
  for r in
    select o.id, o.attempts, o.updated_at, h.status_code, h.timed_out,
           h.error_msg, h.content, h.id is not null as answered
    from public.telegram_outbox o
    left join net._http_response h on h.id = o.request_id
    where o.status = 'pending'
    order by o.id
    limit 200
  loop
    if r.answered and r.status_code = 200 then
      update public.telegram_outbox
      set status = 'sent', last_error = null, updated_at = now()
      where id = r.id;
    elsif r.answered or r.updated_at < now() - interval '2 minutes' then
      -- Hata ya da cevap hiç gelmedi.
      if r.attempts >= 3 then
        update public.telegram_outbox
        set status = 'failed',
            last_error = left(coalesce(r.error_msg, r.content,
                                       'yanıt yok') || ' (' || coalesce(r.status_code::text, '-') || ')', 300),
            updated_at = now()
        where id = r.id;
      else
        update public.telegram_outbox
        set last_error = left(coalesce(r.error_msg, r.content, 'yanıt yok'), 300)
        where id = r.id;
        perform public.telegram_outbox_send(r.id);
      end if;
    end if;
  end loop;

  delete from public.telegram_outbox where created_at < now() - interval '7 days';
end;
$$;
revoke all on function public.telegram_outbox_retry() from public, anon, authenticated;

select cron.unschedule('telegram-outbox-retry')
where exists (select 1 from cron.job where jobname = 'telegram-outbox-retry');
select cron.schedule('telegram-outbox-retry', '* * * * *',
                     'select public.telegram_outbox_retry()');
