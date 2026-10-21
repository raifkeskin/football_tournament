-- Kimlik doğrulama şimdilik gizli: yalnız admin ve deneme hesapları görür.
-- Herkese açmak için identity_verification_enabled = true.
insert into public.app_settings (key, value) values
  ('identity_verification_enabled', 'false'::jsonb),
  ('identity_verification_users', '["a1da69df-7398-4bd9-9080-fa65ed873fb0"]'::jsonb)
on conflict (key) do nothing;
