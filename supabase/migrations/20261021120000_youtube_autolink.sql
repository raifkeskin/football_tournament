-- YouTube yayınlarını maça otomatik bağlama.
--
-- Turnuvanın YouTube kanalı (leagues.youtube_url) maç günlerinde 5 dakikada
-- bir taranır (edge function youtube-autolink, YouTube Data API). Yayın
-- başlığındaki maç kodu (#LMxxxxxx) ya da iki takımın adı + yakın saat ile
-- maç bulunur ve "Maç Yayın Linki" olarak eklenir. Elle girilmiş link
-- varsa dokunulmaz; bir kez bağlanan video yeniden bağlanmaz (elle
-- silinirse geri gelmez).
--
-- Gerekli: Supabase secret YOUTUBE_API_KEY. Yoksa fonksiyon hiçbir şey
-- yapmaz.

-- Kanal adresinden çözülen kanal kimliği (UC...); fonksiyon doldurur.
alter table public.leagues
  add column if not exists youtube_channel_id text;

-- Kanal adresi değişince eski kimlik silinir (yeniden çözülür).
create or replace function public.leagues_reset_youtube_channel()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if new.youtube_url is distinct from old.youtube_url then
    new.youtube_channel_id := null;
  end if;
  return new;
end;
$$;

drop trigger if exists leagues_reset_youtube_channel on public.leagues;
create trigger leagues_reset_youtube_channel
  before update of youtube_url on public.leagues
  for each row execute function public.leagues_reset_youtube_channel();

-- İşlenmiş (bir maça bağlanmış) videolar.
create table if not exists public.youtube_video_links (
  video_id   text primary key,
  league_id  uuid not null references public.leagues(id) on delete cascade,
  match_id   uuid references public.matches(id) on delete set null,
  title      text,
  matched_by text check (matched_by in ('code', 'teams')),
  created_at timestamptz not null default now()
);

alter table public.youtube_video_links enable row level security;
-- İstemci erişimi yok; yalnızca service role (edge function).

insert into public.app_private_settings (key, value)
values ('youtube_sync_secret', encode(extensions.gen_random_bytes(24), 'hex'))
on conflict (key) do nothing;

-- Cron: yalnızca kanalı olan ve -2..+1 gün içinde linksiz maçı bulunan
-- turnuva varsa edge function çağrılır (API kotası boşa harcanmaz).
create or replace function public.youtube_autolink_tick()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_secret text;
  v_today date := (now() at time zone 'Europe/Istanbul')::date;
begin
  if not exists (
    select 1
      from public.matches m
      join public.leagues l on l.id = m.league_id
     where nullif(trim(l.youtube_url), '') is not null
       and m.deleted_at is null
       and m.match_date between v_today - 2 and v_today + 1
       and not exists (
         select 1 from public.match_media mm
          where mm.match_id = m.id and mm.media_type = 'Maç Yayın Linki'
       )
  ) then
    return;
  end if;
  select value into v_secret from public.app_private_settings
   where key = 'youtube_sync_secret';
  perform net.http_post(
    url := 'https://qxdjebzszikeslobrozf.supabase.co/functions/v1/youtube-autolink',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-sync-secret', v_secret
    ),
    timeout_milliseconds := 60000
  );
exception when others then
  raise warning 'youtube_autolink_tick: %', sqlerrm;
end;
$$;

revoke all on function public.youtube_autolink_tick() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'youtube-autolink';
select cron.schedule('youtube-autolink', '*/5 * * * *',
  'select public.youtube_autolink_tick()');
