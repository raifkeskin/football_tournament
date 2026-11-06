-- "Son adımı geri al": önce son girilen olayı (gol, kart, değişiklik…)
-- siler; saat ve maç durumu değişmez. Son aşamadan sonra olay yoksa aşama
-- geri alınır (eskisi gibi). Aşama zamanı matches.phase_at'te tutulur.
-- match_undo_preview: ekranlarda onay metni için ne geri alınacağını söyler.

alter table public.matches add column if not exists phase_at timestamptz;

create or replace function public.matches_phase_at()
returns trigger
language plpgsql
set search_path to ''
as $$
begin
  if new.status is distinct from old.status
     or new.kickoff_at is distinct from old.kickoff_at
     or new.second_half_at is distinct from old.second_half_at
     or new.extra_time_at is distinct from old.extra_time_at
     or new.shootout is distinct from old.shootout then
    new.phase_at := now();
  end if;
  return new;
end;
$$;
drop trigger if exists matches_phase_at on public.matches;
create trigger matches_phase_at before update on public.matches
  for each row execute function public.matches_phase_at();

CREATE OR REPLACE FUNCTION public.advance_match_phase(p_match_id uuid, p_action text)
 RETURNS matches
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  m public.matches;
  dur int;
  v_ev uuid;
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
    -- Son aşamadan sonra girilen olay varsa önce o geri alınır; saat ve
    -- maç durumu değişmez.
    select e.id into v_ev from public.match_events e
     where e.match_id = p_match_id and e.event_type <> 'status'
       and e.created_at > coalesce(m.phase_at, m.kickoff_at, '-infinity'::timestamptz)
     order by e.created_at desc limit 1;
    if v_ev is not null then
      perform public.desk_delete_event(v_ev);
      select * into m from public.matches where id = p_match_id;
      return m;
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
$function$;


create or replace function public.match_undo_preview(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $$
declare
  m public.matches;
  e record;
begin
  if not public.can_manage_match(p_match_id) then
    raise exception 'Bu maçı yönetme yetkiniz yok.' using errcode = '42501';
  end if;
  select * into m from public.matches where id = p_match_id;
  select ev.event_type, ev.minute, ev.added_minute, ev.is_own_goal, ev.is_penalty,
         trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, '')) as player
    into e
    from public.match_events ev
    left join public.players p on p.id = ev.player_id
   where ev.match_id = p_match_id and ev.event_type <> 'status'
     and ev.created_at > coalesce(m.phase_at, m.kickoff_at, '-infinity'::timestamptz)
   order by ev.created_at desc limit 1;
  if found then
    return jsonb_build_object(
      'kind', 'event',
      'resets_clock', false,
      'label', concat_ws(' · ',
        case when e.minute is not null then e.minute ||
          case when e.added_minute is not null then '+' || e.added_minute else '' end || '''' end,
        case e.event_type
          when 'goal' then case when e.is_own_goal then 'Kendi kalesine gol'
                                when e.is_penalty then 'Penaltı golü' else 'Gol' end
          when 'yellow_card' then 'Sarı kart'
          when 'red_card' then 'Kırmızı kart'
          when 'substitution' then 'Değişiklik'
          when 'penalty_missed' then 'Kaçan penaltı'
          when 'man_of_the_match' then 'Maçın adamı'
          else e.event_type end,
        nullif(e.player, ''))
    );
  end if;
  return jsonb_build_object(
    'kind', 'phase',
    'resets_clock', m.status = 'live' and m.second_half_at is null
                    and m.extra_time_at is null and m.shootout is null,
    'label', case
      when m.status = 'finished' then 'Maç bitişi geri alınır; maç canlıya döner'
      when m.status = 'live' and m.shootout is not null then 'Penaltı atışları geri alınır'
      when m.status = 'live' and m.extra_time_at is not null then 'Uzatma geri alınır'
      when m.status = 'live' and m.second_half_at is not null then 'İkinci yarı başlangıcı geri alınır; devre arasına dönülür'
      when m.status = 'halftime' then 'Devre arası geri alınır; ilk yarı devam eder'
      when m.status = 'live' then 'Başlama düdüğü geri alınır: maç "Başlamadı" olur ve maç saati sıfırlanır'
      else 'Geri alınacak adım yok' end
  );
end;
$$;
revoke all on function public.match_undo_preview(uuid) from public, anon;
grant execute on function public.match_undo_preview(uuid) to authenticated;
