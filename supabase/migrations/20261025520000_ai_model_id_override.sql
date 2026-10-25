-- Gol kesitleri: "gemini-flash-latest" Gemini 3.5'e geçince YouTube linkine
-- 403 (PERMISSION_DENIED) dönmeye başladı (25.10.2026). ai_model_id_<amaç>
-- doluysa fonksiyon tam bu modeli kullanır; boşaltınca admin seçimine döner.
insert into public.app_private_settings (key, value)
values ('ai_model_id_clips', 'gemini-3-flash-preview')
on conflict (key) do update set value = excluded.value;
