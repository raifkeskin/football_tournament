-- Bireysel afiş + "Bu benim" yıldızı: ayar kapalıyken açık olan deneme
-- hesapları (auth kullanıcı id'leri). İlk deneme hesabı: Raif Keskin.
insert into public.app_settings (key, value)
values ('player_poster_users', '["a1da69df-7398-4bd9-9080-fa65ed873fb0"]'::jsonb)
on conflict (key) do update set value = excluded.value, updated_at = now();
