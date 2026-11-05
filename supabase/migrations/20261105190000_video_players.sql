-- Röportaj videolarında kişi etiketi (en çok 3 futbolcu). Etiketli videolar
-- futbolcunun profilinde (Medya sekmesi) görünür; fotoğraf izni yoksa yalnız
-- futbolcunun kendisine (ve yöneticilere). Haber verisinde video başına
-- 'players' listesi.

create table if not exists public.video_players (
  video_id uuid not null references public.videos(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (video_id, player_id)
);
create index if not exists video_players_player_idx on public.video_players (player_id);
alter table public.video_players enable row level security;

drop policy if exists video_players_read on public.video_players;
create policy video_players_read on public.video_players for select using (
  exists (select 1 from public.videos v
           where v.id = video_id and public.can_view_season(v.season_id)));

create or replace function public._video_json(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select jsonb_build_object(
           'id', v.id, 'url', v.url, 'code', v.code, 'title', v.title,
           'cover', v.cover_url,
           'team_id', v.team_id, 'team', t.name, 'team_logo', t.logo_url,
           'players', coalesce((
             select jsonb_agg(jsonb_build_object(
                      'id', p.id,
                      'name', trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, '')),
                      'photo', case when public.player_photos_public(p.id) then p.photo_url end)
                    order by vp.created_at)
               from public.video_players vp
               join public.players p on p.id = vp.player_id
              where vp.video_id = v.id), '[]'::jsonb))
    from public.videos v
    left join public.teams t on t.id = v.team_id
   where v.id = p_id
$$;
revoke all on function public._video_json(uuid) from public, anon, authenticated;

-- Etiketlenebilecek futbolcular: maçın iki takımının o sezondaki kadrosu.
create or replace function public.video_tag_candidates(p_match uuid)
returns table (player_id uuid, name text, team_id uuid, team_name text, photo_url text)
language sql
stable
security definer
set search_path to ''
as $$
  select p.id,
         trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, '')),
         t.id, t.name,
         case when public.player_photos_public(p.id) then p.photo_url end
    from public.matches m
    join public.season_team_players stp
      on stp.season_id = m.season_id
     and stp.team_id in (m.home_team_id, m.away_team_id)
     and coalesce(stp.is_active, true)
    join public.players p on p.id = stp.player_id
    join public.teams t on t.id = stp.team_id
   where m.id = p_match
     and public.can_manage_season_media(m.season_id)
   order by t.name, p.name, p.surname
$$;
revoke all on function public.video_tag_candidates(uuid) from public, anon;
grant execute on function public.video_tag_candidates(uuid) to authenticated;

-- Videonun etiketlerini verilen listeyle değiştirir; haberi günceller.
create or replace function public.video_set_players(p_id uuid, p_players uuid[])
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v record;
begin
  select * into v from public.videos where id = p_id;
  if v.id is null or not public.can_manage_season_media(v.season_id) then
    raise exception 'Yetkiniz yok.';
  end if;
  if coalesce(array_length(p_players, 1), 0) > 3 then
    raise exception 'Bir videoda en çok 3 kişi etiketlenebilir.';
  end if;
  delete from public.video_players
   where video_id = p_id and not (player_id = any (coalesce(p_players, '{}')));
  insert into public.video_players (video_id, player_id)
  select p_id, x from unnest(coalesce(p_players, '{}')) x
  on conflict do nothing;
  if v.match_id is not null then
    perform public._interview_news_sync(v.match_id, v.kind);
  elsif v.news_id is not null then
    update public.news
       set auto_data = coalesce(auto_data, '{}'::jsonb)
                       || jsonb_build_object('videos', jsonb_build_array(public._video_json(p_id)))
     where id = v.news_id and auto_kind = 'video';
  end if;
end;
$$;
revoke all on function public.video_set_players(uuid, uuid[]) from public, anon;
grant execute on function public.video_set_players(uuid, uuid[]) to authenticated;

-- Futbolcunun etiketli röportajları (profil). Fotoğraf izni yoksa yalnız
-- kendisi ve yöneticiler görür.
create or replace function public.player_videos(p_player uuid)
returns table (
  id uuid, season_id uuid, match_id uuid, kind text, title text, url text,
  cover_url text, team_name text, team_logo text, match_label text,
  week int, created_at timestamptz
)
language sql
stable
security definer
set search_path to ''
as $$
  select v.id, v.season_id, v.match_id, v.kind, v.title, v.url, v.cover_url,
         t.name, t.logo_url,
         case when ht.id is not null then ht.name || ' – ' || at.name end,
         m.week, v.created_at
    from public.video_players vp
    join public.videos v on v.id = vp.video_id
    left join public.teams t on t.id = v.team_id
    left join public.matches m on m.id = v.match_id
    left join public.teams ht on ht.id = m.home_team_id
    left join public.teams at on at.id = m.away_team_id
   where vp.player_id = p_player
     and public.can_view_season(v.season_id)
     and (public.player_photos_public(p_player)
          or public.is_admin()
          or public.can_manage_season_media(v.season_id)
          or exists (select 1 from public.players p
                      where p.id = p_player and p.auth_uid = auth.uid()))
   order by v.created_at desc
$$;
grant execute on function public.player_videos(uuid) to anon, authenticated;

-- Mevcut haberler yeni alanla yeniden kurulur.
do $$
declare r record;
begin
  for r in select distinct match_id, kind from public.videos where match_id is not null loop
    perform public._interview_news_sync(r.match_id, r.kind);
  end loop;
end $$;
