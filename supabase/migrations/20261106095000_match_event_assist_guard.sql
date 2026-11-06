-- Asist de aynı kurala tabi: golü atanla aynı takımdan, golcünün kendisi
-- değil ve o dakikada sahada.
create or replace function public.match_events_check_player()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  on_pitch uuid[];
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
  on_pitch := public.match_on_pitch_at(new.match_id, new.team_id, new.minute);
  if not (new.player_id = any (on_pitch)) then
    raise exception 'Bu oyuncu o dakikada oyunda değil (kırmızı kart, iki sarı ya da oyundan çıktı). Yalnız puan olayı girilebilir.'
      using errcode = '23514';
  end if;
  if new.event_type = 'goal' and new.assist_player_id is not null
     and not coalesce(new.is_own_goal, false) then
    if new.assist_player_id = new.player_id
       or not (new.assist_player_id = any (on_pitch)) then
      raise exception 'Asist yapan oyuncu o dakikada sahada olmalı (aynı takımdan, golcü dışında).'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
