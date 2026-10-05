-- Diziliş (matches.home/away_formation) takım sorumlusu tarafından da
-- kaydedilebilsin: maç satırını doğrudan güncelleme yetkisi yalnız
-- yöneticilerde; sorumlu yalnızca kendi takımının dizilişini, esame
-- yetkisi (can_edit_match_roster) olduğu sürece bu fonksiyonla yazar.
create or replace function public.set_match_formation(
  p_match_id uuid,
  p_team_id uuid,
  p_formation text
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_home uuid;
  v_away uuid;
  v_formation text := nullif(trim(coalesce(p_formation, '')), '');
begin
  select home_team_id, away_team_id into v_home, v_away
  from public.matches where id = p_match_id;
  if v_home is null or p_team_id not in (v_home, v_away) then
    raise exception 'Takım bu maçta yok.';
  end if;
  if not public.can_edit_match_roster(p_match_id, p_team_id) then
    raise exception 'Bu takımın dizilişini değiştirme yetkiniz yok.'
      using errcode = '42501';
  end if;
  if v_formation is not null and v_formation !~ '^[0-9]{1,2}(-[0-9]{1,2}){1,5}$' then
    raise exception 'Geçersiz diziliş: %', v_formation;
  end if;

  if p_team_id = v_home then
    update public.matches set home_formation = v_formation where id = p_match_id;
  else
    update public.matches set away_formation = v_formation where id = p_match_id;
  end if;
end;
$$;

grant execute on function public.set_match_formation(uuid, uuid, text) to authenticated;
