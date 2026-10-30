-- Ana sayfada "Profilini onayla" rozeti: admin her zaman, diğerleri açılınca.
insert into public.app_settings (key, value)
values ('verify_prompt_home_enabled', 'false'::jsonb)
on conflict (key) do nothing;
