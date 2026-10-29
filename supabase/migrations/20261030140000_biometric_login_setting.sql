-- Yüz tanıma / parmak izi ile giriş teklifi: admin her zaman, diğerleri açılınca.
insert into public.app_settings (key, value)
values ('biometric_login_enabled', 'false'::jsonb)
on conflict (key) do nothing;
