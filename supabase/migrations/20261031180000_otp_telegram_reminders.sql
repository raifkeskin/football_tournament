-- Telegram test modunda geçici kod kaçmasın: kod mesajına "✅ İlettim"
-- düğmesi eklenir. Düğmeye basılmadıkça ve kod kullanılmadıkça adminlere
-- dakikada bir hatırlatma gider (en fazla 10 kez). Kod kullanılınca, süresi
-- dolunca ya da aynı numaraya yeni kod verilince hatırlatma durur.
-- Hatırlatmada kodu yeniden göstermek için kod düz metin olarak yalnız
-- hatırlatma sürerken tutulur; bitince silinir.

create table if not exists public.otp_telegram_reminders (
  otp_id uuid primary key references public.sms_otp_codes (id) on delete cascade,
  phone_raw10 text not null,
  title text not null,
  code text,
  sent int not null default 0,
  created_at timestamptz not null default now(),
  done_at timestamptz
);
alter table public.otp_telegram_reminders enable row level security;
revoke all on public.otp_telegram_reminders from anon, authenticated;

create or replace function public._otp_telegram_buttons(p_otp uuid, p_raw text, p_code text)
returns jsonb
language sql
immutable
set search_path to ''
as $$
  select jsonb_build_array(
    jsonb_build_array(jsonb_build_object(
      'text', 'WhatsApp ile gönder',
      'url', 'https://wa.me/90' || p_raw
        || '?text=Lig%20Masas%C4%B1%20do%C4%9Frulama%20kodunuz%3A%20' || p_code)),
    jsonb_build_array(jsonb_build_object(
      'text', '✅ İlettim', 'callback_data', 'otp_ack:' || p_otp))
  );
$$;

CREATE OR REPLACE FUNCTION public._otp_issue(p_raw text, p_kind text, p_title text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_provider text;
  v_code text;
  v_key text;
  v_hash text;
  v_sender text;
  v_template text;
  v_request bigint;
  v_id uuid;
begin
  if exists (
    select 1 from public.sms_otp_codes
     where phone_raw10 = p_raw and created_at > now() - interval '60 seconds'
  ) then
    return 'too_soon';
  end if;
  if (select count(*) from public.sms_otp_codes
       where phone_raw10 = p_raw
         and created_at > now() - interval '1 hour') >= 5 then
    return 'too_many';
  end if;

  select value #>> '{}' into v_provider
    from public.app_settings where key = 'sms_otp_provider';
  v_provider := coalesce(v_provider, 'telegram');

  v_code := lpad(
    ((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint)
      % 1000000)::text,
    6, '0');

  if v_provider = 'iletimerkezi' then
    select value into v_key from public.app_private_settings where key = 'iletimerkezi_key';
    select value into v_hash from public.app_private_settings where key = 'iletimerkezi_hash';
    select value into v_sender from public.app_private_settings where key = 'iletimerkezi_sender';
    select value into v_template from public.app_private_settings where key = 'sms_otp_template';
    v_template := coalesce(nullif(v_template, ''),
      'Doğrulama kodunuz: {kod}. Kodu kimseyle paylaşmayın.');
    if coalesce(v_key, '') = '' or coalesce(v_hash, '') = ''
       or coalesce(v_sender, '') = '' then
      return 'not_configured';
    end if;
    select net.http_post(
      url := 'https://api.iletimerkezi.com/v1/send-sms/json',
      body := jsonb_build_object('request', jsonb_build_object(
        'authentication', jsonb_build_object('key', v_key, 'hash', v_hash),
        'order', jsonb_build_object(
          'sender', v_sender,
          'sendDateTime', '',
          'iys', '0',
          'message', jsonb_build_object(
            'text', replace(v_template, '{kod}', v_code),
            'receipents', jsonb_build_object('number', jsonb_build_array(p_raw))
          )
        )
      )),
      headers := '{"Content-Type": "application/json"}'::jsonb
    ) into v_request;
  end if;

  insert into public.sms_otp_codes (
    phone_raw10, kind, code_hash, provider, request_id, expires_at
  ) values (
    p_raw, p_kind, extensions.crypt(v_code, extensions.gen_salt('bf')),
    v_provider, v_request,
    -- Elle iletilen kod için daha uzun süre.
    now() + case when v_provider = 'iletimerkezi'
                 then interval '3 minutes' else interval '30 minutes' end
  ) returning id into v_id;

  if v_provider <> 'iletimerkezi' then
    -- Test modu: kod adminlere gider, admin WhatsApp'tan iletir. Aynı
    -- numaranın önceki kodu için hatırlatma durur.
    update public.otp_telegram_reminders
       set done_at = now(), code = null
     where phone_raw10 = p_raw and done_at is null;
    insert into public.otp_telegram_reminders (otp_id, phone_raw10, title, code)
    values (v_id, p_raw, p_title, v_code);
    perform public.telegram_notify(
      array(select user_id from public.admins where user_id is not null),
      '📱 ' || p_title
        || E'\n' || public.format_phone_raw10(p_raw)
        || E'\nKod: ' || v_code,
      public._otp_telegram_buttons(v_id, p_raw, v_code)
    );
  end if;
  return 'sent';
end;
$function$;

-- Her dakika: iletilmemiş kodlar için hatırlatma.
create or replace function public.otp_reminder_tick()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  r record;
begin
  update public.otp_telegram_reminders t
     set done_at = now(), code = null
    from public.sms_otp_codes c
   where c.id = t.otp_id and t.done_at is null
     and (c.used_at is not null or c.expires_at <= now() or t.sent >= 10);

  for r in
    select t.* from public.otp_telegram_reminders t
     where t.done_at is null
       and t.created_at + make_interval(mins => t.sent + 1) <= now() + interval '5 seconds'
     order by t.created_at
  loop
    update public.otp_telegram_reminders set sent = sent + 1 where otp_id = r.otp_id;
    perform public.telegram_notify(
      array(select user_id from public.admins where user_id is not null),
      '⏰ KOD BEKLİYOR (' || (r.sent + 1) || '. hatırlatma)'
        || E'\n📱 ' || r.title
        || E'\n' || public.format_phone_raw10(r.phone_raw10)
        || E'\nKod: ' || r.code,
      public._otp_telegram_buttons(r.otp_id, r.phone_raw10, r.code)
    );
  end loop;
end;
$$;
revoke all on function public.otp_reminder_tick() from public, anon, authenticated;
revoke all on function public._otp_telegram_buttons(uuid, text, text) from public, anon, authenticated;

select cron.schedule('otp-telegram-reminder', '* * * * *',
                     'select public.otp_reminder_tick()');

CREATE OR REPLACE FUNCTION public.telegram_act(p_chat_id bigint, p_action text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user uuid;
  v_status text;
  v_grant jsonb;
  r public.profile_change_requests%rowtype;
begin
  select user_id into v_user from public.telegram_links where chat_id = p_chat_id;
  if v_user is null then
    raise exception 'Bu Telegram hesabı bir kullanıcıya bağlı değil.';
  end if;
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_user, 'role', 'authenticated')::text,
    true
  );

  if p_action in ('acc_ok', 'acc_no') then
    if not public.is_admin() then
      raise exception 'Bu talebi inceleme yetkiniz yok.';
    end if;
    select status into v_status from public.account_requests where id = p_id for update;
    if v_status is null then
      raise exception 'Talep bulunamadı.';
    end if;
    if v_status <> 'pending' then
      raise exception 'Talep zaten sonuçlanmış.';
    end if;
    if p_action = 'acc_ok' then
      v_grant := public.approve_account_request(p_id);
      return v_grant || jsonb_build_object('status', 'approved');
    end if;
    update public.account_requests
    set status = 'rejected', reviewed_by = v_user, reviewed_at = now()
    where id = p_id;
    return jsonb_build_object('status', 'rejected');
  end if;

  if p_action in ('prof_ok', 'prof_no') then
    perform public.review_profile_change(p_id, p_action = 'prof_ok', null);
    select * into r from public.profile_change_requests where id = p_id;
    return jsonb_build_object(
      'status', r.status,
      'delete_photo', case
        when r.status = 'rejected' then r.changes ->> 'photo_url'
        when r.status = 'approved' and r.changes ? 'photo_url'
             and (r.previous ->> 'photo_url') like '%/media/profile_requests/%'
          then r.previous ->> 'photo_url'
      end
    );
  end if;

  -- Geçici kod iletildi: hatırlatma durur (mesaja "✅ Onaylandı" eklenir).
  if p_action = 'otp_ack' then
    if not public.is_admin() then
      raise exception 'Yetkiniz yok.';
    end if;
    update public.otp_telegram_reminders
       set done_at = coalesce(done_at, now()), code = null
     where otp_id = p_id;
    return jsonb_build_object('status', 'approved');
  end if;

  raise exception 'Bilinmeyen işlem.';
end;
$function$;
