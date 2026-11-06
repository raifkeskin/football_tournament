-- Olay girişinin tek kuralı veritabanında (web masası, mobil Detay ve
-- diziliş, eski uygulamalar hepsi buradan geçer):
--   * İkinci sarı kart da oyuncuyu sahadan çıkarır (kırmızı gibi).
--   * Gol, kaçan penaltı, sarı ve kırmızı kart yalnız o dakikada sahada
--     olan oyuncuya girilir. Kırmızı kart / iki sarı gören ya da oyundan
--     çıkan oyuncuya yalnız puan olayları (Olay ekle) girilebilir.
-- Sahadakiler olayın dakikasına göre hesaplanır; böylece maç sonrası
-- geriye dönük girişler (ör. 60'ta çıkan oyuncunun 40'taki golü) çalışır.

create or replace function public.match_on_pitch_at(p_match_id uuid, p_team_id uuid, p_minute int)
returns uuid[]
language plpgsql
stable security definer
set search_path to ''
as $$
declare
  on_pitch uuid[];
  yellows jsonb := '{}'::jsonb;
  n int;
  e record;
begin
  select coalesce(array_agg(player_id), '{}') into on_pitch
    from public.match_rosters
   where match_id = p_match_id and team_id = p_team_id and is_starting;
  for e in
    select event_type, player_id, sub_in_player_id
      from public.match_events
     where match_id = p_match_id and team_id = p_team_id
       and event_type in ('substitution', 'red_card', 'yellow_card')
       and (p_minute is null or minute is null or minute <= p_minute)
     order by minute nulls last, created_at
  loop
    if e.event_type = 'yellow_card' then
      n := coalesce((yellows ->> e.player_id::text)::int, 0) + 1;
      yellows := yellows || jsonb_build_object(e.player_id::text, n);
      if n >= 2 then on_pitch := array_remove(on_pitch, e.player_id); end if;
    else
      on_pitch := array_remove(on_pitch, e.player_id);
      if e.event_type = 'substitution' and e.sub_in_player_id is not null then
        on_pitch := array_append(on_pitch, e.sub_in_player_id);
      end if;
    end if;
  end loop;
  return on_pitch;
end;
$$;
revoke all on function public.match_on_pitch_at(uuid, uuid, int) from public, anon;
grant execute on function public.match_on_pitch_at(uuid, uuid, int) to authenticated;

create or replace function public.match_on_pitch(p_match_id uuid, p_team_id uuid)
returns uuid[]
language sql
stable security definer
set search_path to ''
as $$ select public.match_on_pitch_at(p_match_id, p_team_id, null) $$;

create or replace function public.match_events_check_player()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.event_type not in ('goal', 'penalty_missed', 'yellow_card', 'red_card')
     or new.team_id is null or new.player_id is null then
    return new;
  end if;
  -- İlk 11'i işaretlenmemiş esamede kim sahada bilinmez: kontrol yok.
  if not exists (select 1 from public.match_rosters
                  where match_id = new.match_id and team_id = new.team_id
                    and is_starting) then
    return new;
  end if;
  if not (new.player_id = any (public.match_on_pitch_at(new.match_id, new.team_id, new.minute))) then
    raise exception 'Bu oyuncu o dakikada oyunda değil (kırmızı kart, iki sarı ya da oyundan çıktı). Yalnız puan olayı girilebilir.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists match_events_check_player on public.match_events;
create trigger match_events_check_player
  before insert on public.match_events
  for each row execute function public.match_events_check_player();
