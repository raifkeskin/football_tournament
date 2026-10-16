-- Kart cezası kaldırılınca bildirim. Kırmızı kart (ya da ikinci sarı)
-- girilince kurucu başkan ve bölge sorumlularına "Onay bekleyen ceza"
-- gidiyor; kart silinir ya da VAR ile iptal edilirse aynı kişilere bunun da
-- haberi gider. Ceza onaylanmışsa oyuncuya ve takım sorumlularına da gider.
--   * VAR: olay 'red_card_cancelled' olmuş → "VAR: Kart iptali"
--   * Olay silinmiş (ceza cascade ile düşer) → "Kart iptal edildi"
--   * Olay duruyor, ceza elle kaldırılmış → "Ceza kaldırıldı"
-- Ayrıca VAR iptalinde karta bağlı ceza tetikleyiciyle silinir (gözlemcinin
-- ceza silme yetkisi olmasa da düşsün).

create or replace function public.match_events_card_var_cancel()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if old.event_type = 'red_card' and new.event_type = 'red_card_cancelled' then
    delete from public.player_penalties where source_event_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists match_events_card_var_cancel on public.match_events;
create trigger match_events_card_var_cancel
  after update of event_type on public.match_events
  for each row execute function public.match_events_card_var_cancel();

create or replace function public.player_penalties_removed_push()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_type text;
  v_minute int;
  v_league uuid;
  v_name text;
  v_title text;
  v_ids uuid[];
begin
  if old.kind not in ('red_card', 'second_yellow') or old.status = 'rejected' then
    return old;
  end if;

  select event_type, minute into v_type, v_minute
    from public.match_events where id = old.source_event_id;
  v_title := case
    when v_type = 'red_card_cancelled' then 'VAR: Kart iptali'
    when v_type is null then 'Kart iptal edildi'
    else 'Ceza kaldırıldı'
  end;

  select league_id into v_league from public.matches where id = old.match_id;
  select trim(coalesce(name, '') || ' ' || coalesce(surname, ''))
    into v_name from public.players where id = old.player_id;

  -- "Onay bekleyen ceza"yı alanlar + (onaylıysa) oyuncu ve takım sorumluları.
  select array_agg(distinct uid) into v_ids from (
    select user_id as uid from public.league_owners where league_id = v_league
    union
    select ro.user_id from public.matches m
    join public.groups g on g.id = m.group_id
    join public.region_owners ro on ro.region_id = g.region_id
    where m.id = old.match_id
    union
    select p.auth_uid from public.players p
    where old.status = 'approved' and p.id = old.player_id
    union
    select tm.user_id from public.team_managers tm
    join public.season_team_players stp
      on stp.season_id = tm.season_id and stp.team_id = tm.team_id
    where old.status = 'approved'
      and stp.season_id = old.season_id and stp.player_id = old.player_id
  ) x where uid is not null;

  perform public.push_send(
    v_ids,
    v_title,
    coalesce(nullif(v_name, ''), 'Oyuncu') || ' · '
      || case when v_minute is not null then v_minute::text || '''' || ' ' else '' end
      || case old.kind when 'red_card' then 'Kırmızı kart' else 'İkinci sarı kart' end
      || ' · ceza kaldırıldı',
    '/',
    'penalty-' || old.id
  );
  return old;
exception when others then
  raise warning 'penalty removed push: %', sqlerrm;
  return old;
end;
$$;

drop trigger if exists player_penalties_removed_push on public.player_penalties;
create trigger player_penalties_removed_push
  after delete on public.player_penalties
  for each row execute function public.player_penalties_removed_push();
