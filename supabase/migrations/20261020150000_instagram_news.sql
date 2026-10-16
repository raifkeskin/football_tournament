-- Instagram → Haberler (2. aşama): bağlı hesabın gönderileri turnuvanın aktif
-- sezonuna otomatik haber olarak düşer (auto_kind = 'instagram').
--
-- * league_instagram_accounts.import_news: turnuva formundaki "Haberlere
--   aktar" anahtarı (admin + kurucu başkan). last_synced_at / last_error:
--   son eşitlemenin durumu.
-- * instagram_seen_media: bir kez görülen gönderi bir daha alınmaz (haber
--   silinse de geri gelmez). Yalnız sunucu.
-- * news.ig_media_id: haberin Instagram gönderisi (B'de uygulamadan
--   paylaşılan haberin geri alınmaması için de kullanılır).
-- * instagram-sync Edge Function'ı her 15 dakikada cron ile çağrılır; istek
--   app_private_settings.instagram_sync_secret ile doğrulanır.
-- * Instagram haberleri bildirim göndermez (news_push_notify auto_kind'i atlar).

-- Mevcut bağlantılar kapalı başlar (Champions'taki test bağlantısına
-- tanıtım gönderileri düşmesin); yeni bağlantılarda açık.
alter table public.league_instagram_accounts
  add column if not exists import_news boolean not null default false,
  add column if not exists last_synced_at timestamptz,
  add column if not exists last_error text;
alter table public.league_instagram_accounts
  alter column import_news set default true;

create table if not exists public.instagram_seen_media (
  league_id uuid not null references public.leagues(id) on delete cascade,
  media_id text not null,
  seen_at timestamptz not null default now(),
  primary key (league_id, media_id)
);

alter table public.instagram_seen_media enable row level security;
revoke all on public.instagram_seen_media from anon, authenticated;

alter table public.news drop constraint if exists news_auto_kind_check;
alter table public.news add constraint news_auto_kind_check
  check (auto_kind in ('match_result', 'week_results', 'instagram'));

alter table public.news add column if not exists ig_media_id text;
create unique index if not exists news_ig_media_uq
  on public.news (season_id, ig_media_id) where ig_media_id is not null;

-- Durum özetine aktarım ayarı ve son eşitleme eklendi (dönüş tipi değişti).
drop function if exists public.league_instagram_status(uuid);
create function public.league_instagram_status(p_league_id uuid)
returns table (
  username text,
  connected_at timestamptz,
  expires_at timestamptz,
  can_publish boolean,
  import_news boolean,
  last_synced_at timestamptz,
  last_error text
)
language sql
stable
security definer
set search_path to ''
as $$
  select a.username, a.connected_at, a.expires_at,
         'instagram_business_content_publish' = any (a.permissions),
         a.import_news, a.last_synced_at, a.last_error
  from public.league_instagram_accounts a
  where a.league_id = p_league_id
    and public.owns_league(p_league_id)
$$;

create or replace function public.set_league_instagram_import(
  p_league_id uuid, p_on boolean)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not public.owns_league(p_league_id) then
    raise exception 'Bu turnuva için yetkiniz yok.';
  end if;
  update public.league_instagram_accounts
     set import_news = coalesce(p_on, false)
   where league_id = p_league_id;
end;
$$;

revoke all on function public.league_instagram_status(uuid) from public, anon;
revoke all on function public.set_league_instagram_import(uuid, boolean) from public, anon;
grant execute on function public.league_instagram_status(uuid) to authenticated;
grant execute on function public.set_league_instagram_import(uuid, boolean) to authenticated;

-- Cron isteğinin gizli anahtarı (yoksa üret).
insert into public.app_private_settings (key, value)
values ('instagram_sync_secret', encode(extensions.gen_random_bytes(24), 'hex'))
on conflict (key) do nothing;

create or replace function public.instagram_sync_tick()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_secret text;
begin
  if not exists (
    select 1 from public.league_instagram_accounts
     where import_news or expires_at < now() + interval '10 days'
  ) then
    return;
  end if;
  select value into v_secret from public.app_private_settings
   where key = 'instagram_sync_secret';
  perform net.http_post(
    url := 'https://qxdjebzszikeslobrozf.supabase.co/functions/v1/instagram-sync',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-sync-secret', v_secret
    ),
    timeout_milliseconds := 60000
  );
exception when others then
  raise warning 'instagram_sync_tick: %', sqlerrm;
end;
$$;

revoke all on function public.instagram_sync_tick() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'instagram-sync';
select cron.schedule('instagram-sync', '*/15 * * * *',
  'select public.instagram_sync_tick()');
