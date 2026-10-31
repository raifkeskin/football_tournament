-- Geçici kod hatırlatması: 10 saniyede bir, en fazla 5 dakika ("✅ İlettim",
-- kodun kullanılması ya da aynı numaraya yeni kod da durdurur).

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
     and (c.used_at is not null or c.expires_at <= now()
          or t.created_at + interval '5 minutes' <= now());

  for r in
    select t.* from public.otp_telegram_reminders t
     where t.done_at is null
       and t.created_at + make_interval(secs => (t.sent + 1) * 10) <= now() + interval '2 seconds'
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

select cron.schedule('otp-telegram-reminder', '10 seconds',
                     'select public.otp_reminder_tick()');
