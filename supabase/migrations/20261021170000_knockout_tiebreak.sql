-- Eleme maçı: beraberlikte uzatma ve/veya penaltı atışları.
--
-- tiebreak: null → lig maçı (beraberlik olur, puan tablosuna sayılır);
--           'et_pens' → uzatma, sonra penaltı; 'pens' → doğrudan penaltı.
-- cup_name / cup_round: gösterim için kupa ve tur adı ("Yarı Final").
-- extra_time_at: uzatmanın başladığı an (sunucu saati).
-- shootout: penaltı atışları sırasıyla [{"t":"h"|"a","g":true|false}];
--           null → atışlar başlamadı. home_pens / away_pens bundan sayılır.
-- Penaltı atışı golleri match_events'e yazılmaz (gol krallığına sayılmaz).
--
-- Yalnız ekleme: eski sürümler yeni sütunları okumaz, maçı skoruyla
-- (ör. 2-2) gösterir.

alter table public.matches
  add column if not exists tiebreak text
    check (tiebreak in ('pens', 'et_pens')),
  add column if not exists cup_name text,
  add column if not exists cup_round text,
  add column if not exists extra_time_at timestamptz,
  add column if not exists shootout jsonb,
  add column if not exists home_pens smallint,
  add column if not exists away_pens smallint;

-- Gözlemci eleme kuralını değiştiremez.
create or replace function public.matches_guard_observer_edit()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if public.owns_match(old.id) then
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
     or new.cup_round is distinct from old.cup_round then
    raise exception 'Bu alanları yalnızca admin veya turnuva sahibi değiştirebilir.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function public.advance_match_phase(
  p_match_id uuid,
  p_action text
)
returns public.matches
language plpgsql
security definer
set search_path to ''
as $$
declare
  m public.matches;
  dur int;
begin
  if not public.can_manage_match(p_match_id) then
    raise exception 'Bu maçı yönetme yetkiniz yok.' using errcode = '42501';
  end if;

  select * into m from public.matches where id = p_match_id for update;
  if not found then
    raise exception 'Maç bulunamadı.';
  end if;

  select coalesce(nullif(s.match_period_duration, 0), 30) into dur
  from public.seasons s where s.id = m.season_id;
  dur := coalesce(dur, 30);

  if p_action = 'start' then
    -- Ertelenen maç yeni tarihinde doğrudan başlatılabilir.
    if m.status not in ('notStarted', 'postponed') then
      raise exception 'Maç zaten başlamış.';
    end if;
    update public.matches
       set status = 'live', kickoff_at = now(), second_half_at = null,
           extra_time_at = null, shootout = null,
           home_pens = null, away_pens = null,
           is_completed = false
     where id = p_match_id;

  elsif p_action = 'end_first_half' then
    if m.status <> 'live' or m.second_half_at is not null then
      raise exception 'İlk yarı oynanmıyor.';
    end if;
    update public.matches set status = 'halftime' where id = p_match_id;

  elsif p_action = 'start_second_half' then
    if m.status <> 'halftime' then
      raise exception 'Maç devre arasında değil.';
    end if;
    update public.matches
       set status = 'live', second_half_at = now()
     where id = p_match_id;

  elsif p_action = 'start_extra_time' then
    if m.status <> 'live' or m.second_half_at is null
       or m.extra_time_at is not null or m.shootout is not null then
      raise exception 'Uzatmaya geçilemez.';
    end if;
    if m.tiebreak is distinct from 'et_pens' then
      raise exception 'Bu maçta uzatma oynanmaz.';
    end if;
    if m.home_score <> m.away_score then
      raise exception 'Skor eşit değil; maç bitirilebilir.';
    end if;
    update public.matches set extra_time_at = now() where id = p_match_id;

  elsif p_action = 'start_shootout' then
    if m.status <> 'live' or m.second_half_at is null
       or m.shootout is not null then
      raise exception 'Penaltılara geçilemez.';
    end if;
    if m.tiebreak is null then
      raise exception 'Bu maç eleme maçı değil.';
    end if;
    if m.home_score <> m.away_score then
      raise exception 'Skor eşit değil; maç bitirilebilir.';
    end if;
    update public.matches
       set shootout = '[]'::jsonb, home_pens = 0, away_pens = 0
     where id = p_match_id;

  elsif p_action = 'finish' then
    if m.status <> 'live' or m.second_half_at is null then
      raise exception 'İkinci yarı oynanmıyor.';
    end if;
    if m.tiebreak is not null and m.home_score = m.away_score
       and coalesce(m.home_pens, 0) = coalesce(m.away_pens, 0) then
      raise exception 'Eleme maçı berabere bitemez: önce uzatma veya penaltılar oynanmalı.';
    end if;
    update public.matches
       set status = 'finished', is_completed = true
     where id = p_match_id;

  elsif p_action = 'undo' then
    if not public.owns_match(p_match_id) then
      raise exception 'Geri alma yalnızca admin veya turnuva sahibine açık.'
        using errcode = '42501';
    end if;
    if m.status = 'finished' then
      update public.matches set status = 'live', is_completed = false
       where id = p_match_id;
    elsif m.status = 'live' and m.shootout is not null then
      update public.matches
         set shootout = null, home_pens = null, away_pens = null
       where id = p_match_id;
    elsif m.status = 'live' and m.extra_time_at is not null then
      update public.matches set extra_time_at = null where id = p_match_id;
    elsif m.status = 'live' and m.second_half_at is not null then
      update public.matches set status = 'halftime', second_half_at = null
       where id = p_match_id;
    elsif m.status = 'halftime' then
      update public.matches set status = 'live' where id = p_match_id;
    elsif m.status = 'live' then
      update public.matches set status = 'notStarted', kickoff_at = null
       where id = p_match_id;
    else
      raise exception 'Geri alınacak adım yok.';
    end if;

  else
    raise exception 'Bilinmeyen adım: %', p_action;
  end if;

  select * into m from public.matches where id = p_match_id;
  return m;
end;
$$;

grant execute on function public.advance_match_phase(uuid, text) to authenticated;

-- Penaltı atışı: p_side 'h' / 'a' bir atış ekler (p_scored gol mü);
-- p_side null son atışı geri alır.
create or replace function public.shootout_kick(
  p_match_id uuid,
  p_side text,
  p_scored boolean
)
returns public.matches
language plpgsql
security definer
set search_path to ''
as $$
declare
  m public.matches;
  kicks jsonb;
  n int;
begin
  if not public.can_manage_match(p_match_id) then
    raise exception 'Bu maçı yönetme yetkiniz yok.' using errcode = '42501';
  end if;

  select * into m from public.matches where id = p_match_id for update;
  if not found then
    raise exception 'Maç bulunamadı.';
  end if;
  if m.status <> 'live' or m.shootout is null then
    raise exception 'Penaltı atışları başlamadı.';
  end if;

  n := jsonb_array_length(m.shootout);
  if p_side is null then
    if n = 0 then
      raise exception 'Geri alınacak atış yok.';
    end if;
    kicks := m.shootout - (n - 1);
  elsif p_side in ('h', 'a') then
    kicks := m.shootout
      || jsonb_build_array(jsonb_build_object('t', p_side, 'g', coalesce(p_scored, false)));
  else
    raise exception 'Geçersiz taraf: %', p_side;
  end if;

  update public.matches
     set shootout = kicks,
         home_pens = (select count(*) from jsonb_array_elements(kicks) e
                       where e->>'t' = 'h' and (e->>'g')::boolean),
         away_pens = (select count(*) from jsonb_array_elements(kicks) e
                       where e->>'t' = 'a' and (e->>'g')::boolean)
   where id = p_match_id;

  select * into m from public.matches where id = p_match_id;
  return m;
end;
$$;

revoke execute on function public.shootout_kick(uuid, text, boolean) from public, anon;
grant execute on function public.shootout_kick(uuid, text, boolean) to authenticated;
