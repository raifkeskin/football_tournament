-- Play-Off ağacı: kupa eşleşmeleri ve turların kendiliğinden ilerlemesi.
--
-- cup_brackets: bir sezonun (grubun) bir kupası. first_round ilk turun
--   eşleşmeleri, ağaç sırasıyla: [{"h": uuid|null, "a": uuid|null,
--   "hr": sıra, "ar": sıra}]; null taraf bay (rakipsiz tur atlar).
-- matches.cup_bracket_id / cup_stage / cup_slot: maçın ağaçtaki yeri.
--   cup_stage 1 ilk tur; son tur finaldir (slot 0 final, slot 1 3.lük).
--
-- cup_advance(): ağacı baştan dolaşır; iki tarafı belli olan her eşleşme
-- için maç yoksa oluşturur, tarafı değiştiyse (başlamamışsa) günceller,
-- tarafı belirsizleştiyse (önceki maç geri alındı) başlamamış maçı siler.
-- Bir eleme maçının durumu / sonucu değişince tetikleyici çağırır.
--
-- Yalnız ekleme: eski sürümler yeni tablo ve sütunları okumaz; eleme
-- maçlarını normal fikstürde görür.

create table if not exists public.cup_brackets (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete cascade,
  league_id uuid,
  group_id uuid references public.groups(id) on delete cascade,
  cup_name text not null,
  cup_index smallint not null default 0,
  tiebreak text not null default 'et_pens' check (tiebreak in ('pens', 'et_pens')),
  third boolean not null default false,
  first_round jsonb not null,
  base_week int not null default 0,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);

create unique index if not exists cup_brackets_unique
  on public.cup_brackets (season_id, coalesce(group_id, '00000000-0000-0000-0000-000000000000'::uuid), cup_name);

alter table public.cup_brackets enable row level security;

drop policy if exists cup_brackets_select on public.cup_brackets;
create policy cup_brackets_select on public.cup_brackets
  for select using (public.can_view_season(season_id));

grant select on public.cup_brackets to anon, authenticated;

alter table public.matches
  add column if not exists cup_bracket_id uuid
    references public.cup_brackets(id) on delete set null,
  add column if not exists cup_stage smallint,
  add column if not exists cup_slot smallint;

create index if not exists matches_cup_bracket_idx
  on public.matches (cup_bracket_id) where cup_bracket_id is not null;

-- Gözlemci eleme kuralını değiştiremez; ağacın kendi güncellemesi serbest.
create or replace function public.matches_guard_observer_edit()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if public.owns_match(old.id)
     or current_setting('app.cup_advance', true) = '1' then
    return new;
  end if;
  if new.observer_id is distinct from old.observer_id
     or new.season_id is distinct from old.season_id
     or new.league_id is distinct from old.league_id
     or new.group_id is distinct from old.group_id
     or new.home_team_id is distinct from old.home_team_id
     or new.away_team_id is distinct from old.away_team_id
     or new.match_date is distinct from old.match_date
     or new.match_time is distinct from old.match_time
     or new.week is distinct from old.week
     or new.tiebreak is distinct from old.tiebreak
     or new.cup_name is distinct from old.cup_name
     or new.cup_round is distinct from old.cup_round
     or new.cup_bracket_id is distinct from old.cup_bracket_id
     or new.cup_stage is distinct from old.cup_stage
     or new.cup_slot is distinct from old.cup_slot then
    raise exception 'Bu alanları yalnızca admin veya turnuva sahibi değiştirebilir.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

-- Bitmiş maçın galibi (p_loser: mağlubu); bitmediyse ya da berabereyse null.
create or replace function public.cup_match_side(m public.matches, p_loser boolean)
returns uuid
language sql
immutable
set search_path to ''
as $$
  select case
    when m.status <> 'finished' then null
    when m.home_score > m.away_score
      or (m.home_score = m.away_score
          and coalesce(m.home_pens, 0) > coalesce(m.away_pens, 0))
      then case when p_loser then m.away_team_id else m.home_team_id end
    when m.away_score > m.home_score
      or (m.home_score = m.away_score
          and coalesce(m.away_pens, 0) > coalesce(m.home_pens, 0))
      then case when p_loser then m.home_team_id else m.away_team_id end
    else null
  end
$$;

create or replace function public.cup_round_name(p_teams int)
returns text
language sql
immutable
set search_path to ''
as $$
  select case p_teams
    when 2 then 'Final'
    when 4 then 'Yarı Final'
    when 8 then 'Çeyrek Final'
    else 'Son ' || p_teams
  end
$$;

-- Bir eşleşmenin maçını tarafları belliyse oluşturur / günceller, değilse
-- (başlamamışsa) siler. Maçı döndürür (yoksa null satır).
create or replace function public.cup_sync_slot(
  b public.cup_brackets,
  p_stage int,
  p_slot int,
  p_round text,
  p_home uuid,
  p_away uuid
)
returns public.matches
language plpgsql
security definer
set search_path to ''
as $$
declare
  m public.matches;
begin
  select * into m from public.matches
   where cup_bracket_id = b.id and cup_stage = p_stage and cup_slot = p_slot
   order by created_at
   limit 1;

  if p_home is null or p_away is null then
    if found and m.status = 'notStarted' then
      delete from public.matches where id = m.id;
      return null;
    end if;
    return m;
  end if;

  if not found then
    insert into public.matches (
      season_id, league_id, group_id, home_team_id, away_team_id, week,
      status, tiebreak, cup_name, cup_round,
      cup_bracket_id, cup_stage, cup_slot
    ) values (
      b.season_id, b.league_id, b.group_id, p_home, p_away,
      b.base_week + p_stage,
      'notStarted', b.tiebreak, b.cup_name, p_round,
      b.id, p_stage, p_slot
    )
    returning * into m;
  elsif m.status = 'notStarted'
        and (m.home_team_id is distinct from p_home
             or m.away_team_id is distinct from p_away) then
    update public.matches
       set home_team_id = p_home, away_team_id = p_away
     where id = m.id
    returning * into m;
  end if;
  return m;
end;
$$;

create or replace function public.cup_advance(p_bracket_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  b public.cup_brackets;
  n int;
  rounds int := 1;
  slots int;
  r int;
  s int;
  h uuid;
  a uuid;
  m public.matches;
  winners uuid[];
  next_w uuid[];
  losers uuid[] := array[null::uuid, null::uuid];
begin
  select * into b from public.cup_brackets where id = p_bracket_id;
  if not found then
    return;
  end if;
  perform set_config('app.cup_advance', '1', true);

  n := jsonb_array_length(b.first_round);
  slots := n;
  while slots > 1 loop
    slots := slots / 2;
    rounds := rounds + 1;
  end loop;

  slots := n;
  for r in 1..rounds loop
    next_w := array_fill(null::uuid, array[slots]);
    for s in 0..slots - 1 loop
      if r = 1 then
        h := nullif(b.first_round -> s ->> 'h', '')::uuid;
        a := nullif(b.first_round -> s ->> 'a', '')::uuid;
        if h is null or a is null then
          -- Bay: rakipsiz taraf tur atlar.
          next_w[s + 1] := coalesce(h, a);
          continue;
        end if;
      else
        h := winners[2 * s + 1];
        a := winners[2 * s + 2];
      end if;
      m := public.cup_sync_slot(
        b, r, s, public.cup_round_name(slots * 2), h, a
      );
      if m.id is not null then
        next_w[s + 1] := public.cup_match_side(m, false);
        if r = rounds - 1 and s < 2 then
          losers[s + 1] := public.cup_match_side(m, true);
        end if;
      end if;
    end loop;
    winners := next_w;
    slots := slots / 2;
  end loop;

  -- 3.lük maçı: yarı final mağlupları (final turunda slot 1).
  if b.third and rounds >= 2 then
    perform public.cup_sync_slot(
      b, rounds, 1, '3.lük Maçı', losers[1], losers[2]
    );
  end if;

  perform set_config('app.cup_advance', '', true);
end;
$$;

-- Eleme maçının durumu ya da (bitmişse) sonucu değişince ağaç ilerler.
create or replace function public.matches_cup_advance()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.cup_bracket_id is not null
     and (new.status is distinct from old.status
          or (new.status = 'finished'
              and (new.home_score is distinct from old.home_score
                   or new.away_score is distinct from old.away_score
                   or new.home_pens is distinct from old.home_pens
                   or new.away_pens is distinct from old.away_pens))) then
    perform public.cup_advance(new.cup_bracket_id);
  end if;
  return null;
end;
$$;

drop trigger if exists matches_cup_advance on public.matches;
create trigger matches_cup_advance
  after update on public.matches
  for each row execute function public.matches_cup_advance();

-- Eşleşmeleri oluşturur (lig sırasına göre ilk tur; istemci hesaplar).
create or replace function public.create_cup_bracket(
  p_season_id uuid,
  p_group_id uuid,
  p_cup_name text,
  p_cup_index int,
  p_tiebreak text,
  p_third boolean,
  p_first_round jsonb
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id uuid;
  v_league uuid;
  v_week int;
  n int;
begin
  if not public.owns_season(p_season_id) then
    raise exception 'Eşleşmeleri yalnızca admin veya turnuva sahibi oluşturabilir.'
      using errcode = '42501';
  end if;
  n := coalesce(jsonb_array_length(p_first_round), 0);
  if n < 1 or (n & (n - 1)) <> 0 then
    raise exception 'Geçersiz eşleşme listesi.';
  end if;
  if exists (
    select 1 from public.cup_brackets
     where season_id = p_season_id
       and group_id is not distinct from p_group_id
       and cup_name = p_cup_name
  ) then
    raise exception '"%" eşleşmeleri zaten oluşturuldu.', p_cup_name;
  end if;

  select league_id into v_league from public.seasons where id = p_season_id;
  select coalesce(max(week), 0) into v_week from public.matches
   where season_id = p_season_id
     and group_id is not distinct from p_group_id
     and tiebreak is null;

  insert into public.cup_brackets (
    season_id, league_id, group_id, cup_name, cup_index, tiebreak, third,
    first_round, base_week
  ) values (
    p_season_id, v_league, p_group_id, p_cup_name, coalesce(p_cup_index, 0),
    case when p_tiebreak = 'pens' then 'pens' else 'et_pens' end,
    coalesce(p_third, false), p_first_round, v_week
  )
  returning id into v_id;

  perform public.cup_advance(v_id);
  return v_id;
end;
$$;

-- Eşleşmeleri geri alır: hiçbir maçı başlamamışsa kupanın maçları silinir.
create or replace function public.reset_cup_bracket(p_bracket_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  b public.cup_brackets;
begin
  select * into b from public.cup_brackets where id = p_bracket_id;
  if not found then
    return;
  end if;
  if not public.owns_season(b.season_id) then
    raise exception 'Yalnızca admin veya turnuva sahibi geri alabilir.'
      using errcode = '42501';
  end if;
  if exists (
    select 1 from public.matches
     where cup_bracket_id = b.id and status <> 'notStarted'
  ) then
    raise exception 'Bu kupada oynanmış maç var; eşleşmeler geri alınamaz.';
  end if;
  delete from public.matches where cup_bracket_id = b.id;
  delete from public.cup_brackets where id = b.id;
end;
$$;

revoke execute on function public.cup_advance(uuid) from public, anon, authenticated;
revoke execute on function public.cup_sync_slot(public.cup_brackets, int, int, text, uuid, uuid) from public, anon, authenticated;
revoke execute on function public.create_cup_bracket(uuid, uuid, text, int, text, boolean, jsonb) from public, anon;
revoke execute on function public.reset_cup_bracket(uuid) from public, anon;
grant execute on function public.create_cup_bracket(uuid, uuid, text, int, text, boolean, jsonb) to authenticated;
grant execute on function public.reset_cup_bracket(uuid) to authenticated;
