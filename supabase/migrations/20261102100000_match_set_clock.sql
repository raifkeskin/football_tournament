-- Canlı maç sayacını elle düzeltme (admin + kurucu başkan): girilen dakika
-- şu an olacak şekilde başlama düdüğü (1. yarı) ya da 2. yarı başlangıcı
-- geriye/ileriye alınır. Uzatma devresi ve penaltılarda kullanılmaz.
create or replace function public.match_set_clock(p_match_id uuid, p_minute int)
returns public.matches
language plpgsql
security definer
set search_path to ''
as $$
declare
  m public.matches;
  dur int;
begin
  select * into m from public.matches where id = p_match_id for update;
  if not found then
    raise exception 'Maç bulunamadı.';
  end if;
  if not public.owns_league(m.league_id) then
    raise exception 'Sayacı yalnız admin ve kurucu başkan düzeltebilir.'
      using errcode = '42501';
  end if;
  if m.status <> 'live' or m.kickoff_at is null then
    raise exception 'Sayaç yalnız oynanan maçta düzeltilir.';
  end if;
  if m.extra_time_at is not null or m.shootout is not null then
    raise exception 'Uzatma ve penaltılarda sayaç düzeltilemez.';
  end if;

  select coalesce(nullif(s.match_period_duration, 0), 30) into dur
  from public.seasons s where s.id = m.season_id;
  dur := coalesce(dur, 30);

  if m.second_half_at is null then
    if p_minute < 1 or p_minute > dur + 30 then
      raise exception '1. yarıda dakika 1 ile % arasında olmalı.', dur + 30;
    end if;
    update public.matches
       set kickoff_at = now() - make_interval(mins => p_minute - 1)
     where id = p_match_id
     returning * into m;
  else
    if p_minute <= dur or p_minute > dur * 2 + 30 then
      raise exception '2. yarıda dakika % ile % arasında olmalı.',
        dur + 1, dur * 2 + 30;
    end if;
    update public.matches
       set second_half_at = now() - make_interval(mins => p_minute - dur - 1)
     where id = p_match_id
     returning * into m;
  end if;
  return m;
end;
$$;

revoke all on function public.match_set_clock(uuid, int) from public, anon;
grant execute on function public.match_set_clock(uuid, int) to authenticated;
