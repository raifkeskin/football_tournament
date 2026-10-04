-- Kart cezaları: kırmızı kart (2 maç) ve aynı maçta ikinci sarı (1 maç)
-- girildiğinde otomatik, onay bekleyen ceza kaydı açılır. Turnuva sahibi
-- onaylayınca ceza geçerli olur; oyuncunun takımı o sezonda her maç bitirdikçe
-- kalan maç sayısı düşer, sıfırlanınca ceza kalkar. Ceza sezona bağlıdır:
-- oyuncunun başka turnuvadaki maçlarını etkilemez.

alter table public.player_penalties
  add column if not exists status text not null default 'approved'
    check (status in ('pending', 'approved', 'rejected')),
  add column if not exists kind text not null default 'manual'
    check (kind in ('manual', 'red_card', 'second_yellow')),
  add column if not exists match_id uuid references public.matches(id) on delete set null,
  add column if not exists source_event_id uuid references public.match_events(id) on delete cascade,
  add column if not exists remaining_matches integer,
  add column if not exists reviewed_by uuid,
  add column if not exists reviewed_at timestamptz;

-- Aynı maçta aynı oyuncuya tek otomatik ceza (kırmızı ya da ikinci sarı).
create unique index if not exists player_penalties_auto_once
  on public.player_penalties (match_id, player_id)
  where kind <> 'manual';

-- Takımın, cezanın verildiği maçtan sonra bitmiş maç sayısı.
create or replace function public.penalty_served_matches(p_penalty_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::int
  from public.player_penalties pp
  join public.matches src on src.id = pp.match_id
  join public.season_team_players stp
    on stp.player_id = pp.player_id and stp.season_id = pp.season_id
  join public.matches m
    on m.season_id = pp.season_id
   and m.status = 'finished'
   and m.id <> src.id
   and (m.home_team_id = stp.team_id or m.away_team_id = stp.team_id)
   and coalesce(m.match_date, src.match_date) >= src.match_date
  where pp.id = p_penalty_id
$$;

-- Kart girilince onay bekleyen ceza + turnuva sahibine bildirim.
create or replace function public.match_events_card_penalty()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
  v_count int;
  v_season uuid;
  v_league uuid;
  v_name text;
  v_id uuid;
  v_owners uuid[];
begin
  if new.player_id is null then
    return new;
  end if;
  if new.event_type = 'red_card' then
    v_kind := 'red_card';
    v_count := 2;
  elsif new.event_type = 'yellow_card' and exists (
    select 1 from public.match_events e
    where e.match_id = new.match_id
      and e.player_id = new.player_id
      and e.event_type = 'yellow_card'
      and e.id <> new.id
  ) then
    v_kind := 'second_yellow';
    v_count := 1;
  else
    return new;
  end if;

  select season_id, league_id into v_season, v_league
  from public.matches where id = new.match_id;
  if v_season is null then
    return new;
  end if;

  insert into public.player_penalties
    (player_id, season_id, match_count, penalty_reason, is_active, status,
     kind, match_id, source_event_id)
  values
    (new.player_id, v_season, v_count,
     case v_kind when 'red_card' then 'Kırmızı kart' else 'İkinci sarı kart' end,
     false, 'pending', v_kind, new.match_id, new.id)
  on conflict do nothing
  returning id into v_id;

  if v_id is not null then
    select trim(coalesce(name, '') || ' ' || coalesce(surname, ''))
      into v_name from public.players where id = new.player_id;
    select array_agg(user_id) into v_owners
    from public.league_owners where league_id = v_league;
    perform public.push_send(
      v_owners,
      'Onay bekleyen ceza',
      coalesce(v_name, 'Oyuncu') || ' · ' ||
        case v_kind when 'red_card' then 'Kırmızı kart (2 maç)'
                    else 'İkinci sarı kart (1 maç)' end,
      '/',
      'penalty-' || v_id
    );
  end if;
  return new;
exception when others then
  raise warning 'card penalty: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists match_events_card_penalty on public.match_events;
create trigger match_events_card_penalty
  after insert on public.match_events
  for each row execute function public.match_events_card_penalty();

-- Turnuva sahibi / admin onaylar ya da reddeder. Onayda maç sayısı
-- değiştirilebilir; onaya kadar oynanmış maçlar cezadan düşülür.
create or replace function public.review_player_penalty(
  p_penalty_id uuid,
  p_approve boolean,
  p_match_count integer default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_season uuid;
  v_count int;
  v_remaining int;
begin
  select season_id, coalesce(p_match_count, match_count)
    into v_season, v_count
  from public.player_penalties where id = p_penalty_id;
  if v_season is null then
    raise exception 'Ceza bulunamadı.';
  end if;
  if not public.owns_season(v_season) then
    raise exception 'Bu cezayı onaylama yetkiniz yok.';
  end if;

  if not p_approve then
    update public.player_penalties
       set status = 'rejected', is_active = false,
           reviewed_by = auth.uid(), reviewed_at = now()
     where id = p_penalty_id;
    return;
  end if;

  if v_count is null or v_count < 1 then
    raise exception 'Ceza en az 1 maç olmalı.';
  end if;
  v_remaining := greatest(v_count - public.penalty_served_matches(p_penalty_id), 0);
  update public.player_penalties
     set status = 'approved', match_count = v_count,
         remaining_matches = v_remaining, is_active = v_remaining > 0,
         reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_penalty_id;
end;
$$;

revoke all on function public.review_player_penalty(uuid, boolean, integer) from public, anon;
grant execute on function public.review_player_penalty(uuid, boolean, integer) to authenticated;

-- Maç bitince o takımın cezalı oyuncularının kalan maçı bir azalır.
create or replace function public.matches_serve_penalties()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> 'finished' or old.status = 'finished' then
    return new;
  end if;
  update public.player_penalties pp
     set remaining_matches = greatest(coalesce(pp.remaining_matches, pp.match_count) - 1, 0),
         is_active = coalesce(pp.remaining_matches, pp.match_count) - 1 > 0
   where pp.season_id = new.season_id
     and pp.status = 'approved'
     and pp.is_active
     and pp.match_id is distinct from new.id
     and exists (
       select 1 from public.season_team_players stp
       where stp.player_id = pp.player_id
         and stp.season_id = new.season_id
         and stp.team_id in (new.home_team_id, new.away_team_id)
     );
  return new;
end;
$$;

drop trigger if exists matches_serve_penalties on public.matches;
create trigger matches_serve_penalties
  after update of status on public.matches
  for each row execute function public.matches_serve_penalties();
