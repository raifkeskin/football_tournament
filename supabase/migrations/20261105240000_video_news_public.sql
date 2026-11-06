-- Video ve röportaj haberlerini sezonu görüntüleyebilen tüm rollere aç.
insert into public.app_settings (key, value)
values ('video_news_public', 'true'::jsonb)
on conflict (key) do update set value = excluded.value;
