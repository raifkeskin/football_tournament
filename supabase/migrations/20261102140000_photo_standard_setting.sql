-- Profil fotoğrafı standardı (kadraj kılavuzu + yüz kontrolü): yeni özellik,
-- yalnız admin görür; açılınca herkese.
insert into public.app_settings (key, value)
values ('photo_standard_enabled', 'false'::jsonb)
on conflict (key) do nothing;
