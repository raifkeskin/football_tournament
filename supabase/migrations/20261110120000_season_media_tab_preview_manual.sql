-- Sezon Medya sekmesi (canlı yayın / yayıncı / fotoğrafçı var mı) ve
-- maç önü haberini elle oluşturma.
alter table public.seasons
  add column if not exists live_stream_enabled boolean not null default true,
  add column if not exists broadcaster_enabled boolean not null default true,
  add column if not exists photographer_enabled boolean not null default true;

alter table public.news
  add column if not exists preview_manual boolean not null default false;

-- Elle oluşturulan kart, maç günü 09:00 gelmeden otomatik gizlenmesin.
create or replace function public.refresh_preview_news(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  m record;
  v_region uuid;
  v_enabled boolean;
  v_data jsonb;
  v_id uuid;
  v_published boolean;
  v_kick timestamptz;
  v_manual boolean;
begin
  select * into m from public.matches where id = p_match_id;
  if not found or m.season_id is null then
    return;
  end if;
  select g.region_id into v_region from public.groups g where g.id = m.group_id;
  select l.auto_preview_news into v_enabled
    from public.seasons s join public.leagues l on l.id = s.league_id
   where s.id = m.season_id;

  select id, is_published, preview_manual into v_id, v_published, v_manual
    from public.news
   where auto_kind = 'match_preview' and match_id = p_match_id;

  v_kick := public.match_kickoff_ts(m.match_date, m.match_time);

  if m.deleted_at is null
     and m.status in ('notStarted', 'live', 'halftime')
     and m.home_team_id is not null and m.away_team_id is not null
     and v_kick is not null
     and now() >= public.match_preview_due_at(m.match_date, m.match_time)
     and now() <= v_kick + interval '6 hours' then
    v_data := public.match_preview_data(p_match_id);
    if v_id is null then
      if coalesce(v_enabled, true) then
        insert into public.news (season_id, region_id, content, is_published,
                                 auto_kind, match_id, week, auto_data)
        values (m.season_id, v_region, public.preview_text(v_data), true,
                'match_preview', p_match_id, m.week, v_data);
      end if;
    else
      update public.news
         set content = public.preview_text(v_data),
             auto_data = v_data,
             week = m.week,
             region_id = v_region,
             is_published = case when auto_hidden then true else is_published end,
             auto_hidden = false
       where id = v_id
         and (auto_data is distinct from v_data or auto_hidden
              or region_id is distinct from v_region);
    end if;
  elsif v_id is not null and v_published
        and not (coalesce(v_manual, false) and m.deleted_at is null
                 and m.status in ('notStarted', 'live', 'halftime')) then
    update public.news set is_published = false, auto_hidden = true
     where id = v_id;
  end if;

  perform public.refresh_day_preview_news(m.season_id, v_region, m.match_date);
end;
$$;

-- Elle oluştur: otomatik kapalı ya da vakit gelmemiş olsa da kartı açar.
create or replace function public.create_preview_news(p_match_id uuid)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  m record;
  v_region uuid;
  v_data jsonb;
  v_id uuid;
begin
  select * into m from public.matches where id = p_match_id;
  if not found or m.season_id is null or m.deleted_at is not null then
    raise exception 'Maç bulunamadı';
  end if;
  if not public.can_manage_season_media(m.season_id) then
    raise exception 'Yetkiniz yok';
  end if;
  if m.home_team_id is null or m.away_team_id is null then
    raise exception 'Takımlar belli değil';
  end if;
  select g.region_id into v_region from public.groups g where g.id = m.group_id;
  v_data := public.match_preview_data(p_match_id);
  select id into v_id from public.news
   where auto_kind = 'match_preview' and match_id = p_match_id;
  if v_id is null then
    insert into public.news (season_id, region_id, content, is_published,
                             auto_kind, match_id, week, auto_data, preview_manual)
    values (m.season_id, v_region, public.preview_text(v_data), true,
            'match_preview', p_match_id, m.week, v_data, true)
    returning id into v_id;
  else
    update public.news
       set content = public.preview_text(v_data), auto_data = v_data,
           week = m.week, region_id = v_region, is_published = true,
           auto_hidden = false, preview_manual = true
     where id = v_id;
  end if;
  return v_id;
end;
$$;
revoke all on function public.create_preview_news(uuid) from public, anon;
grant execute on function public.create_preview_news(uuid) to authenticated;
