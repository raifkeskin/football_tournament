-- Otomatik haber başlıkları her kelimenin ilk harfi büyük: '1. Hafta Sonuçları', 'Bugünün Maçları'.

CREATE OR REPLACE FUNCTION public.refresh_week_results_news(p_season_id uuid, p_region_id uuid, p_week integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_enabled boolean;
  v_pending int;
  v_items jsonb;
  v_content text;
  v_id uuid;
  v_hidden boolean;
  v_published boolean;
begin
  if p_season_id is null or p_week is null then
    return;
  end if;
  select l.auto_result_news into v_enabled
    from public.seasons s join public.leagues l on l.id = s.league_id
   where s.id = p_season_id;

  -- Bekleyen maç: başlamamış / oynanıyor / devre arası. Ertelenen ve iptal
  -- edilen maçlar özeti bekletmez (ertelenen sonradan biterse özete eklenir).
  with wm as (
    select m.* from public.matches m
    left join public.groups g on g.id = m.group_id
    where m.season_id = p_season_id and m.week = p_week
      and m.deleted_at is null
      and g.region_id is not distinct from p_region_id
  )
  select count(*) filter (where status in ('notStarted', 'live', 'halftime')),
         jsonb_agg(public.match_result_data(id)
                   order by match_date nulls last, match_time nulls last, created_at)
           filter (where status = 'finished')
    into v_pending, v_items
    from wm;

  select id, auto_hidden, is_published into v_id, v_hidden, v_published
    from public.news
   where auto_kind = 'week_results' and season_id = p_season_id
     and region_id is not distinct from p_region_id and week = p_week;

  -- Tek maçlık haftada özet açılmaz (maç kartıyla aynı olurdu).
  if coalesce(v_pending, 0) > 0 or coalesce(jsonb_array_length(v_items), 0) < 2 then
    -- Hafta yeniden açıldı (ör. maç geri alındı): özet gizlenir.
    if v_id is not null and v_published then
      update public.news set is_published = false, auto_hidden = true
       where id = v_id;
    end if;
    return;
  end if;

  v_content := p_week || '. Hafta Sonuçları' || E'\n\n' ||
    (select string_agg(public.result_text(x), E'\n\n' order by o)
       from jsonb_array_elements(v_items) with ordinality as a(x, o));

  if v_id is null then
    if not coalesce(v_enabled, true) then
      return;
    end if;
    insert into public.news (season_id, region_id, content, is_published,
                             auto_kind, week, auto_data)
    values (p_season_id, p_region_id, v_content, true, 'week_results', p_week,
            jsonb_build_object('week', p_week, 'matches', v_items));
  else
    update public.news
       set content = v_content,
           auto_data = jsonb_build_object('week', p_week, 'matches', v_items),
           is_published = case when auto_hidden then true else is_published end,
           auto_hidden = false
     where id = v_id;
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.refresh_day_preview_news(p_season_id uuid, p_region_id uuid, p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_enabled boolean;
  v_items jsonb;
  v_pending int;
  v_due timestamptz;
  v_last timestamptz;
  v_week int;
  v_data jsonb;
  v_content text;
  v_id uuid;
  v_published boolean;
begin
  if p_season_id is null or p_date is null then
    return;
  end if;
  select l.auto_preview_news into v_enabled
    from public.seasons s join public.leagues l on l.id = s.league_id
   where s.id = p_season_id;

  with dm as (
    select m.* from public.matches m
    left join public.groups g on g.id = m.group_id
    where m.season_id = p_season_id and m.match_date = p_date
      and m.deleted_at is null
      and m.status not in ('postponed', 'cancelled')
      and m.home_team_id is not null and m.away_team_id is not null
      and g.region_id is not distinct from p_region_id
  )
  select jsonb_agg(jsonb_build_object(
           'match_id', id, 'time', match_time, 'status', status,
           'home', (select jsonb_build_object('id', t.id, 'name', t.name,
                      'short', t.short_name, 'logo', t.logo_url, 'color', t.first_color)
                    from public.teams t where t.id = home_team_id),
           'away', (select jsonb_build_object('id', t.id, 'name', t.name,
                      'short', t.short_name, 'logo', t.logo_url, 'color', t.first_color)
                    from public.teams t where t.id = away_team_id),
           'pitch', (select p.name from public.pitches p where p.id = pitch_id))
           order by public.match_kickoff_ts(match_date, match_time), created_at),
         count(*) filter (where status in ('notStarted', 'live', 'halftime')),
         min(public.match_preview_due_at(match_date, match_time)),
         max(public.match_kickoff_ts(match_date, match_time)),
         min(week)
    into v_items, v_pending, v_due, v_last, v_week
    from dm;

  select id, is_published into v_id, v_published
    from public.news
   where auto_kind = 'day_preview' and season_id = p_season_id
     and region_id is not distinct from p_region_id
     and auto_data->>'date' = p_date::text;

  if coalesce(jsonb_array_length(v_items), 0) < 2 or coalesce(v_pending, 0) = 0
     or now() < v_due or now() > v_last + interval '6 hours' then
    if v_id is not null and v_published then
      update public.news set is_published = false, auto_hidden = true
       where id = v_id;
    end if;
    return;
  end if;

  v_data := jsonb_build_object('date', p_date::text, 'week', v_week, 'matches', v_items);
  v_content := 'Bugünün Maçları' || E'\n\n' ||
    (select string_agg(concat_ws(' · ', nullif(x->>'time', ''),
                         (x->'home'->>'name') || ' – ' || (x->'away'->>'name'),
                         nullif(x->>'pitch', '')), E'\n' order by o)
       from jsonb_array_elements(v_items) with ordinality as a(x, o));

  if v_id is null then
    if not coalesce(v_enabled, true) then
      return;
    end if;
    insert into public.news (season_id, region_id, content, is_published,
                             auto_kind, week, auto_data)
    values (p_season_id, p_region_id, v_content, true, 'day_preview', v_week, v_data);
  else
    update public.news
       set content = v_content,
           auto_data = v_data,
           week = v_week,
           is_published = case when auto_hidden then true else is_published end,
           auto_hidden = false
     where id = v_id
       and (auto_data is distinct from v_data or auto_hidden);
  end if;
end;
$function$
;

update public.news
   set content = regexp_replace(content, '^(\d+\. Hafta) sonuçları', '\1 Sonuçları')
 where auto_kind = 'week_results' and content ~ '^\d+\. Hafta sonuçları';
update public.news
   set content = regexp_replace(content, '^(Bugünün|Yarının|Günün) maçları', '\1 Maçları')
 where auto_kind = 'day_preview' and content ~ '^(Bugünün|Yarının|Günün) maçları';
