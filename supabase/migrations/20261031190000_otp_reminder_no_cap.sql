-- Geçici kod hatırlatması: 10 sınırı kalktı; "✅ İlettim"e basılana, kod
-- kullanılana ya da süresi (30 dk) dolana kadar dakikada bir gider.

CREATE OR REPLACE FUNCTION public.otp_reminder_tick()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r record;
begin
  update public.otp_telegram_reminders t
     set done_at = now(), code = null
    from public.sms_otp_codes c
   where c.id = t.otp_id and t.done_at is null
     and (c.used_at is not null or c.expires_at <= now());

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
$function$

;
