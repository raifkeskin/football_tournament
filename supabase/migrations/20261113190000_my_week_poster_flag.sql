-- "Bu hafta sen" kartındaki maç afişi kısayolu: önce yalnız admin.
-- Herkese açmak: update app_settings set value = 'true' where key = 'my_week_poster_enabled';
insert into public.app_settings (key, value)
values ('my_week_poster_enabled', 'false'::jsonb)
on conflict (key) do nothing;
