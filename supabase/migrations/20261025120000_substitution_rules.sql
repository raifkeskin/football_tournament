-- Oyuncu değişikliği kuralı (uygulama ve Yönetim Masası için ortak):
-- çıkan oyuncu o an sahada, giren oyuncu o an kenarda olmalı. Saha: ilk 11,
-- sonra değişiklikler sırayla uygulanır (çıkan iner, giren çıkar); kırmızı
-- kart gören sahadan iner. Çıkmış oyuncu yeniden girebilir (halısahada
-- dönüşümlü değişiklik). Maçın esamesi yoksa kontrol yapılmaz.

create or replace function public.match_on_pitch(p_match_id uuid, p_team_id uuid)
returns uuid[]
language plpgsql
stable security definer
set search_path to ''
as $$
declare
  on_pitch uuid[];
  e record;
begin
  select coalesce(array_agg(player_id), '{}') into on_pitch
    from public.match_rosters
   where match_id = p_match_id and team_id = p_team_id and is_starting;
  for e in
    select event_type, player_id, sub_in_player_id
      from public.match_events
     where match_id = p_match_id and team_id = p_team_id
       and event_type in ('substitution', 'red_card')
     order by minute nulls last, created_at
  loop
    on_pitch := array_remove(on_pitch, e.player_id);
    if e.event_type = 'substitution' and e.sub_in_player_id is not null then
      on_pitch := array_append(on_pitch, e.sub_in_player_id);
    end if;
  end loop;
  return on_pitch;
end;
$$;
revoke all on function public.match_on_pitch(uuid, uuid) from public, anon;
grant execute on function public.match_on_pitch(uuid, uuid) to authenticated;

create or replace function public.match_events_check_substitution()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  on_pitch uuid[];
begin
  if new.event_type <> 'substitution' or new.team_id is null then
    return new;
  end if;
  if not exists (select 1 from public.match_rosters
                  where match_id = new.match_id and team_id = new.team_id) then
    return new;
  end if;
  on_pitch := public.match_on_pitch(new.match_id, new.team_id);
  if new.player_id is null or not (new.player_id = any(on_pitch)) then
    raise exception 'Çıkan oyuncu şu an sahada değil.' using errcode = '23514';
  end if;
  if new.sub_in_player_id is null
     or new.sub_in_player_id = any(on_pitch)
     or not exists (select 1 from public.match_rosters
                     where match_id = new.match_id and team_id = new.team_id
                       and player_id = new.sub_in_player_id) then
    raise exception 'Giren oyuncu kenardaki oyunculardan (yedeklerden) olmalı.' using errcode = '23514';
  end if;
  if exists (select 1 from public.match_events
              where match_id = new.match_id and event_type = 'red_card'
                and player_id = new.sub_in_player_id) then
    raise exception 'Kırmızı kart gören oyuncu oyuna giremez.' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists match_events_check_substitution on public.match_events;
create trigger match_events_check_substitution
  before insert on public.match_events
  for each row execute function public.match_events_check_substitution();
