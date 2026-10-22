-- Kimlik Yönetimi: kimlik doğrulama admin dışında hangi rollere açık
-- (admin panelinden aç/kapa). Değer rol anahtarları dizisi:
-- league_owner (kurucu başkan), region_owner (bölge sorumlusu),
-- team_manager (takım sorumlusu), player (futbolcu).
-- identity_verification_enabled (herkes) ve identity_verification_users
-- (deneme hesapları) olduğu gibi kalır.

insert into public.app_settings (key, value)
values ('identity_verification_roles', '[]'::jsonb)
on conflict (key) do nothing;

create or replace function public.identity_allowed()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  with r as (
    select coalesce((select value from public.app_settings
                      where key = 'identity_verification_roles'), '[]'::jsonb) as roles
  )
  select public.is_admin()
      or coalesce((select value = 'true'::jsonb from public.app_settings
                    where key = 'identity_verification_enabled'), false)
      or coalesce((select value ? auth.uid()::text from public.app_settings
                    where key = 'identity_verification_users'), false)
      or (auth.uid() is not null and (
            ((select roles from r) ? 'league_owner' and exists (
              select 1 from public.league_owners where user_id = auth.uid()))
         or ((select roles from r) ? 'region_owner' and exists (
              select 1 from public.region_owners where user_id = auth.uid()))
         or ((select roles from r) ? 'team_manager' and exists (
              select 1 from public.team_managers where user_id = auth.uid()))
         or ((select roles from r) ? 'player' and exists (
              select 1 from public.players where auth_uid = auth.uid()))
      ))
$function$;
