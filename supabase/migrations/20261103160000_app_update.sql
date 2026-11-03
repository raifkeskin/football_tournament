-- Uygulama içi güncelleme uyarısı (lib/core/services/app_update.dart).
-- Derleme numarası `latest`ten eski kurulumlar altta kapatılabilir
-- "Yeni sürüm mevcut" kartı, `min`den eskiler kapatılamayan "yeni sürümü
-- yüklemeniz gerekiyor" penceresi görür. null = uyarı yok. `url` boşsa
-- App Store / Play bağlantısı kullanılır.
--
-- Örnek (yeni sürüm iki mağazada da yayında olduktan sonra):
--   update public.app_settings
--      set value = jsonb_set(value, '{android,latest}', '120'), updated_at = now()
--    where key = 'app_update';
insert into public.app_settings (key, value)
values ('app_update', '{
  "android": {"latest": null, "min": null, "url": null},
  "ios":     {"latest": null, "min": null, "url": null}
}'::jsonb)
on conflict (key) do nothing;
