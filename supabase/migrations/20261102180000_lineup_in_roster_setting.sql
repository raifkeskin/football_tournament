-- Yeni özellik: diziliş Kadro sekmesinde; yalnız admin görür, açılınca herkese.
insert into public.app_settings (key, value)
values ('lineup_in_roster_enabled', 'false'::jsonb)
on conflict (key) do nothing;
