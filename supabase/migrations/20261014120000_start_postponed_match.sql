-- Ertelenen (postponed) maç da başlatılabilir.

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

  elsif p_action = 'finish' then
    if m.status <> 'live' or m.second_half_at is null then
      raise exception 'İkinci yarı oynanmıyor.';
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
