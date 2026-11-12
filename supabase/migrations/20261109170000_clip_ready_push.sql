-- Gol videosu (MP4) hazır olunca golü atana, asist yapana ve onları takip
-- edenlere bildirim. Yalnız yeni biten maçlar ve her kesit için bir kez.
alter table public.match_highlights
  add column if not exists clip_notified_at timestamptz;

create or replace function public.match_highlights_clip_ready_push()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
declare
  v_ev record;
  v_m record;
  v_scorer text;
  v_to uuid[];
  v_title text;
begin
  if new.kind <> 'goal' or new.status <> 'approved'
     or new.story_url is null or old.story_url is not null
     or new.clip_notified_at is not null then
    return new;
  end if;
  select m.id, m.match_date, th.name as hn, ta.name as an into v_m
    from public.matches m
    join public.teams th on th.id = m.home_team_id
    join public.teams ta on ta.id = m.away_team_id
   where m.id = new.match_id;
  if v_m.id is null or v_m.match_date < now() - interval '4 days' then
    return new;
  end if;

  select e.player_id, e.assist_player_id, e.is_own_goal into v_ev
    from public.match_events e where e.id = new.match_event_id;
  if v_ev.player_id is null and new.player_id is null then
    return new;
  end if;

  select trim(coalesce(name, '') || ' ' || coalesce(surname, '')) into v_scorer
    from public.players where id = coalesce(new.player_id, v_ev.player_id);

  v_to := coalesce((
    select array_agg(distinct pl.auth_uid) from public.players pl
     where pl.auth_uid is not null
       and pl.id in (coalesce(new.player_id, v_ev.player_id), v_ev.assist_player_id)), '{}');
  v_to := v_to || coalesce((
    select array_agg(uf.user_id) from public.user_follows uf
     where uf.kind = 'player'
       and uf.target_id in (coalesce(new.player_id, v_ev.player_id), v_ev.assist_player_id)), '{}');
  if cardinality(v_to) = 0 then
    update public.match_highlights set clip_notified_at = now() where id = new.id;
    return new;
  end if;

  perform set_config('push.scorer',
    coalesce(new.player_id, v_ev.player_id)::text, true);
  perform set_config('push.players',
    concat_ws(',', coalesce(new.player_id, v_ev.player_id)::text,
              v_ev.assist_player_id::text), true);
  v_title := 'Gol videosu hazır';
  perform public.push_send(
    v_to, v_title,
    coalesce(nullif(v_scorer, ''), 'Gol') || ' · '
      || coalesce(new.minute::text || E'\' ', '') || v_m.hn || ' – ' || v_m.an,
    '/', 'clip-' || new.match_id);
  perform set_config('push.scorer', '', true);
  perform set_config('push.players', '', true);
  update public.match_highlights set clip_notified_at = now() where id = new.id;
  return new;
exception when others then
  raise warning 'clip_ready_push: %', sqlerrm;
  return new;
end;
$function$;

drop trigger if exists match_highlights_clip_ready on public.match_highlights;
create trigger match_highlights_clip_ready
  after update of story_url on public.match_highlights
  for each row execute function public.match_highlights_clip_ready_push();
