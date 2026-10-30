-- Yeni haberler (ana sayfa kart akışı, Haberler ekranı, küpür detay):
-- admin her zaman, diğerleri açılınca.
insert into public.app_settings (key, value)
values ('news_screen_enabled', 'false'::jsonb)
on conflict (key) do nothing;
