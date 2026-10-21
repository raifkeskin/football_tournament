-- Kimlik doğrulama sunucuda da gizli: eski APK'larda menü görünse bile
-- yalnız admin, deneme hesapları (identity_verification_users) ya da
-- özellik herkese açıldıysa (identity_verification_enabled) kullanılabilir.
create or replace function public.identity_allowed()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select public.is_admin()
      or coalesce((select value = 'true'::jsonb from public.app_settings
                    where key = 'identity_verification_enabled'), false)
      or coalesce((select value ? auth.uid()::text from public.app_settings
                    where key = 'identity_verification_users'), false)
$function$;
grant execute on function public.identity_allowed() to authenticated;

create or replace function public._identity_guard(p_tc text)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if auth.uid() is null
     or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Kimlik doğrulama için giriş yapın.';
  end if;
  if not public.identity_allowed() then
    raise exception 'Kimlik doğrulama henüz kullanıma açık değil.';
  end if;
  if not public.tc_valid(p_tc) then
    raise exception 'Kimlik numarası okunamadı. Kartı tekrar okutun.';
  end if;
  if (select count(*) from public.identity_events
       where user_id = auth.uid()
         and created_at > now() - interval '1 hour') >= 150 then
    raise exception 'Çok fazla deneme. Bir süre sonra tekrar deneyin.';
  end if;
end;
$function$;
revoke all on function public._identity_guard(text) from public, anon, authenticated;
