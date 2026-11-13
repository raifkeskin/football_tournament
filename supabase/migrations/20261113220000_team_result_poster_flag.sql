-- "Bu hafta sen" kartında takım sorumlusuna takım (maç sonucu) afişi:
-- önce yalnız admin.
-- Herkese açmak: update app_settings set value = 'true' where key = 'team_result_poster_enabled';
insert into public.app_settings (key, value)
values ('team_result_poster_enabled', 'false'::jsonb)
on conflict (key) do nothing;
