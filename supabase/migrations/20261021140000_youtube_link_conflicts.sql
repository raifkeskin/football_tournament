-- Elle girilen yayın linki ile turnuva kanalında bulunan yayın farklıysa
-- kurucu başkan ve bölge sorumlusunun "Bekleyen Onaylar"ına düşer
-- (edge function youtube-autolink oluşturur). Karar: kanaldakini kullan /
-- elle gireni koru. Eski sürümler bu tabloyu hiç okumaz.

create table if not exists public.youtube_link_conflicts (
  id               uuid primary key default gen_random_uuid(),
  match_id         uuid not null references public.matches(id) on delete cascade,
  league_id        uuid not null references public.leagues(id) on delete cascade,
  manual_url       text not null,
  manual_video_id  text,
  manual_title     text,
  manual_at        timestamptz,
  auto_video_id    text not null,
  auto_title       text,
  auto_at          timestamptz,
  status           text not null default 'pending'
                   check (status in ('pending', 'use_auto', 'keep_manual')),
  resolved_by      uuid references auth.users(id) on delete set null,
  resolved_at      timestamptz,
  created_at       timestamptz not null default now(),
  unique (match_id, auto_video_id)
);

create index if not exists youtube_link_conflicts_pending_idx
  on public.youtube_link_conflicts (league_id) where status = 'pending';

alter table public.youtube_link_conflicts enable row level security;

-- Admin, kurucu başkan ve maçın bölge sorumlusu görür; yazma yalnızca
-- edge function (service role) ve resolve_youtube_conflict ile.
drop policy if exists youtube_link_conflicts_read on public.youtube_link_conflicts;
create policy youtube_link_conflicts_read on public.youtube_link_conflicts
  for select to authenticated
  using (public.owns_match(match_id));

-- Kararı uygular: kanaldakini kullan → maçın yayın linki değişir.
create or replace function public.resolve_youtube_conflict(
  p_id uuid,
  p_use_auto boolean
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  c public.youtube_link_conflicts;
  v_url text;
begin
  select * into c from public.youtube_link_conflicts where id = p_id for update;
  if not found or not public.owns_match(c.match_id) then
    raise exception 'Yetkiniz yok.';
  end if;
  if c.status <> 'pending' then
    return;
  end if;
  if p_use_auto then
    v_url := 'https://www.youtube.com/watch?v=' || c.auto_video_id;
    update public.match_media
       set url = v_url
     where match_id = c.match_id and media_type = 'Maç Yayın Linki';
    if not found then
      insert into public.match_media (match_id, media_type, url)
      values (c.match_id, 'Maç Yayın Linki', v_url);
    end if;
  end if;
  update public.youtube_link_conflicts
     set status = case when p_use_auto then 'use_auto' else 'keep_manual' end,
         resolved_by = auth.uid(),
         resolved_at = now()
   where id = p_id;
end;
$$;

revoke all on function public.resolve_youtube_conflict(uuid, boolean) from public, anon;
grant execute on function public.resolve_youtube_conflict(uuid, boolean) to authenticated;

-- Yeni uyuşmazlıkta kurucu başkan(lar) + maçın bölge sorumlusuna bildirim.
create or replace function public.youtube_link_conflicts_push()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_ids uuid[];
  v_title text;
begin
  with ids as (
    select lo.user_id as uid from public.league_owners lo
     where lo.league_id = new.league_id
    union
    select ro.user_id from public.matches m
      join public.groups g on g.id = m.group_id
      join public.region_owners ro on ro.region_id = g.region_id
     where m.id = new.match_id
  )
  select array_agg(distinct uid) into v_ids from ids where uid is not null;
  select concat_ws(' – ', h.name, a.name) into v_title
    from public.matches m
    left join public.teams h on h.id = m.home_team_id
    left join public.teams a on a.id = m.away_team_id
   where m.id = new.match_id;
  perform public.push_send(
    v_ids,
    'Yayın linki kontrolü',
    coalesce(v_title, 'Maç') || ' maçındaki yayın linki kanaldaki yayınla '
      || 'uyuşmuyor. Bekleyen Onaylar''dan kontrol edin.',
    '/',
    'yt-conflict-' || new.id
  );
  return new;
exception when others then
  raise warning 'youtube_link_conflicts_push: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists youtube_link_conflicts_push on public.youtube_link_conflicts;
create trigger youtube_link_conflicts_push
  after insert on public.youtube_link_conflicts
  for each row execute function public.youtube_link_conflicts_push();

-- Cron: maç saatinde (linksiz maç) 5 dk; saatte bir son 2 günün tüm
-- maçları (linksiz olanlara ekleme + linklilerde uyuşmazlık kontrolü).
create or replace function public.youtube_autolink_tick()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_secret text;
  v_now timestamptz := now();
  v_today date := (now() at time zone 'Europe/Istanbul')::date;
  v_hourly boolean := extract(minute from now()) < 5;
begin
  if not exists (
    select 1
      from public.matches m
      join public.leagues l on l.id = m.league_id
     where l.youtube_live
       and nullif(trim(l.youtube_url), '') is not null
       and m.deleted_at is null
       and m.match_date between v_today - 2 and v_today + 1
       and (
         (v_hourly and m.match_date <= v_today)
         or (
           m.match_time ~ '^\d{1,2}:\d{2}'
           and (m.match_date + substring(m.match_time from '^\d{1,2}:\d{2}')::time)
                 at time zone 'Europe/Istanbul'
               between v_now - interval '4 hours' and v_now + interval '30 minutes'
           and not exists (
             select 1 from public.match_media mm
              where mm.match_id = m.id and mm.media_type = 'Maç Yayın Linki'
           )
         )
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
