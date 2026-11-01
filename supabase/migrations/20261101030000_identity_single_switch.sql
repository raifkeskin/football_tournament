-- Kimlik doğrulama tek anahtar (Kimlik Yönetimi › Aktif/Pasif): aktifken
-- giriş yapan herkes, pasifken yalnız admin ve deneme hesapları. Rol bazlı
-- ayar (identity_verification_roles) kullanılmıyor.
create or replace function public.identity_allowed()
returns boolean
language sql
stable security definer
set search_path to ''
as $$
  select public.is_admin()
      or coalesce((select value = 'true'::jsonb from public.app_settings
                    where key = 'identity_verification_enabled'), false)
      or coalesce((select value ? auth.uid()::text from public.app_settings
                    where key = 'identity_verification_users'), false)
$$;
grant execute on function public.identity_allowed() to authenticated;

delete from public.app_settings where key = 'identity_verification_roles';
