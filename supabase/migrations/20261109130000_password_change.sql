-- Kayıtlı kullanıcı şifresini telefon koduyla onaylayarak değiştirir.
-- Kod, kayıttaki gibi sms_otp_provider ayarına göre gider (SMS açıksa SMS,
-- kapalıyken yöneticiler WhatsApp'tan iletir).
insert into public.app_settings (key, value)
values ('password_change_enabled', 'false'::jsonb)
on conflict (key) do nothing;

alter table public.sms_otp_codes drop constraint if exists sms_otp_codes_kind_check;
alter table public.sms_otp_codes add constraint sms_otp_codes_kind_check
  check (kind = any (array['register', 'reset', 'phone_change', 'password_change']));

create or replace function public._own_phone_raw10()
 returns text language sql stable security definer set search_path to ''
as $$
  select case when split_part(u.email, '@', 2) = 'masterclass.com'
               and split_part(u.email, '@', 1) ~ '^5[0-9]{9}$'
              then split_part(u.email, '@', 1) end
    from auth.users u where u.id = auth.uid()
$$;
revoke all on function public._own_phone_raw10() from public, anon;
grant execute on function public._own_phone_raw10() to authenticated;

-- Dönüş: disabled | no_phone | sent | too_soon | too_many | not_configured
create or replace function public.password_change_otp_send()
 returns text language plpgsql security definer set search_path to ''
as $function$
declare v_raw text := public._own_phone_raw10();
begin
  if auth.uid() is null then return 'no_phone'; end if;
  if not public.ibraz_flag('password_change_enabled') then return 'disabled'; end if;
  if v_raw is null then return 'no_phone'; end if;
  return public._otp_issue(v_raw, 'password_change', 'Şifre değiştirme');
end;
$function$;

-- Dönüş: ok | disabled | no_phone | weak_password | expired | wrong_code |
-- too_many_attempts
create or replace function public.password_change_with_otp(p_code text, p_new text)
 returns text language plpgsql security definer set search_path to ''
as $function$
declare
  v_raw text := public._own_phone_raw10();
  v_res text;
begin
  if auth.uid() is null or v_raw is null then return 'no_phone'; end if;
  if not public.ibraz_flag('password_change_enabled') then return 'disabled'; end if;
  if p_new is null or length(p_new) not between 6 and 10 or p_new !~ '[^A-Za-z]' then
    return 'weak_password';
  end if;
  v_res := public._otp_consume(v_raw, p_code);
  if v_res <> 'ok' then return v_res; end if;
  update auth.users
     set encrypted_password = extensions.crypt(p_new, extensions.gen_salt('bf')),
         raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
           || '{"must_change_password": false}'::jsonb,
         updated_at = now()
   where id = auth.uid();
  -- Diğer cihazlardaki oturumlar kapanır; bu oturum açık kalır.
  delete from auth.sessions
   where user_id = auth.uid()
     and id::text <> coalesce(auth.jwt() ->> 'session_id', '');
  insert into public.identity_events (player_id, action, user_id)
  values (null, 'password_change', auth.uid());
  return 'ok';
end;
$function$;

grant execute on function public.password_change_otp_send() to authenticated;
grant execute on function public.password_change_with_otp(text, text) to authenticated;
