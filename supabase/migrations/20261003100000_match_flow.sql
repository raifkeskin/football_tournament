-- Maç akışı: başlama düdüğü / ilk yarı sonu / 2. yarı / maç sonu.
--
-- * status metin yerine enum (match_status) olur.
-- * kickoff_at / second_half_at: düğmeye basıldığı SUNUCU saati. Maç geç
--   başlasa da (17:30 yerine 17:45) sayaç gerçek başlangıçtan sayar.
-- * Devre süresi seasons.match_period_duration'dan okunur (yeni alan yok).
-- * observer_id: maçın gözlemcisi. Admin, turnuva sahibi ve gözlemci maç
--   detayındaki yetkilere (akış, olaylar, kadro) sahiptir.
-- * Akış yalnızca advance_match_phase() ile ilerler.
--
-- Not: Playoff uzatması / penaltı akışı henüz tasarlanmadı; ileride yeni
-- adımlar (ör. extra_time) bu fonksiyona eklenebilir.

begin;

-- 1) Hatalı veri ve status enum'u ---------------------------------------
update public.matches set status = 'notStarted'
where status is null or status = 'notStarter';

-- Veritabanında hiçbir kolonun kullanmadığı, küçük harfli değerlerle (notstarted,
-- canceled) tanımlanmış eski bir match_status türü vardı; uygulamanın kullandığı
-- değerlerle yeniden oluşturulur.
drop type if exists public.match_status;
create type public.match_status as enum (
  'notStarted', 'live', 'halftime', 'finished', 'postponed', 'cancelled'
);

alter table public.matches
  alter column status drop default,
  alter column status type public.match_status
    using status::public.match_status,
  alter column status set default 'notStarted',
  alter column status set not null;

-- 2) Akış zamanları ve gözlemci -------------------------------------------
alter table public.matches
  add column if not exists kickoff_at timestamptz,
  add column if not exists second_half_at timestamptz,
  add column if not exists observer_id uuid
    references auth.users(id) on delete set null;

create index if not exists matches_observer_id_idx
  on public.matches(observer_id) where observer_id is not null;

-- 3) Yetki: admin / turnuva sahibi / gözlemci -----------------------------
create or replace function public.can_manage_match(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select public.owns_match(p_match_id) or exists (
    select 1 from public.matches m
    where m.id = p_match_id and m.observer_id = auth.uid()
  )
$$;

grant execute on function public.can_manage_match(uuid) to authenticated;

-- Olaylar: gözlemci de ekleyip silebilir.
drop policy if exists match_events_write on public.match_events;
create policy match_events_write on public.match_events
  for all to authenticated
  using (public.can_manage_match(match_id))
  with check (public.can_manage_match(match_id));

-- Kadro: gözlemci de düzenleyebilir.
drop policy if exists match_rosters_write on public.match_rosters;
create policy match_rosters_write on public.match_rosters
  for all to authenticated
  using (public.owns_league(league_id) or public.can_manage_match(match_id))
  with check (public.owns_league(league_id) or public.can_manage_match(match_id));

-- Maç satırı: gözlemci kendi maçını güncelleyebilir (skor, diziliş). Kimlik
-- alanlarını (takımlar, sezon, gözlemci...) yalnızca admin/turnuva sahibi
-- değiştirebilir; bunu aşağıdaki tetikleyici korur.
drop policy if exists matches_observer_update on public.matches;
create policy matches_observer_update on public.matches
  for update to authenticated
  using (observer_id = auth.uid())
  with check (observer_id = auth.uid());

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
     or new.week is distinct from old.week then
    raise exception 'Bu alanları yalnızca admin veya turnuva sahibi değiştirebilir.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists matches_guard_observer_edit on public.matches;
create trigger matches_guard_observer_edit
  before update on public.matches
  for each row execute function public.matches_guard_observer_edit();

-- 4) Akış fonksiyonu --------------------------------------------------------
-- p_action: start | end_first_half | start_second_half | finish | undo
-- undo yalnızca admin / turnuva sahibi içindir (yanlış basılan adımı geri alır).
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
  elapsed int;
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
    if m.status <> 'notStarted' then
      raise exception 'Maç zaten başlamış.';
    end if;
    update public.matches
       set status = 'live', kickoff_at = now(), second_half_at = null,
           is_completed = false
     where id = p_match_id;
    insert into public.match_events (match_id, season_id, event_type, minute, event_name)
    values (p_match_id, m.season_id, 'status', 0, 'Maç Başladı');

  elsif p_action = 'end_first_half' then
    if m.status <> 'live' or m.second_half_at is not null then
      raise exception 'İlk yarı oynanmıyor.';
    end if;
    elapsed := greatest(1, ceil(extract(epoch from now() - m.kickoff_at) / 60.0)::int);
    update public.matches set status = 'halftime' where id = p_match_id;
    insert into public.match_events (match_id, season_id, event_type, minute, event_name)
    values (p_match_id, m.season_id, 'status', least(elapsed, dur), 'İlk Yarı');

  elsif p_action = 'start_second_half' then
    if m.status <> 'halftime' then
      raise exception 'Maç devre arasında değil.';
    end if;
    update public.matches
       set status = 'live', second_half_at = now()
     where id = p_match_id;

  elsif p_action = 'finish' then
    if m.status <> 'live' or m.second_half_at is null then
      raise exception 'İkinci yarı oynanmıyor.';
    end if;
    update public.matches
       set status = 'finished', is_completed = true
     where id = p_match_id;
    delete from public.match_events
     where match_id = p_match_id and event_type = 'status'
       and event_name = 'Maç Sonucu';
    insert into public.match_events (match_id, season_id, event_type, minute, event_name)
    values (p_match_id, m.season_id, 'status', dur * 2, 'Maç Sonucu');

  elsif p_action = 'undo' then
    if not public.owns_match(p_match_id) then
      raise exception 'Geri alma yalnızca admin veya turnuva sahibine açık.'
        using errcode = '42501';
    end if;
    if m.status = 'finished' then
      update public.matches set status = 'live', is_completed = false
       where id = p_match_id;
      delete from public.match_events where match_id = p_match_id
         and event_type = 'status' and event_name = 'Maç Sonucu';
    elsif m.status = 'live' and m.second_half_at is not null then
      update public.matches set status = 'halftime', second_half_at = null
       where id = p_match_id;
    elsif m.status = 'halftime' then
      update public.matches set status = 'live' where id = p_match_id;
      delete from public.match_events where match_id = p_match_id
         and event_type = 'status' and event_name = 'İlk Yarı';
    elsif m.status = 'live' then
      update public.matches set status = 'notStarted', kickoff_at = null
       where id = p_match_id;
      delete from public.match_events where match_id = p_match_id
         and event_type = 'status' and event_name = 'Maç Başladı';
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

revoke all on function public.advance_match_phase(uuid, text) from public;
grant execute on function public.advance_match_phase(uuid, text) to authenticated;

commit;
