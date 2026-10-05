-- Forma numarası: kurucu/bölge sorumlusu ve takım sorumlusu (yalnız kendi
-- takımı) değiştirebilir. Sorumlunun kadro tablosuna genel yazma yetkisi
-- yok; yalnız bu fonksiyonla numara alanı güncellenir.
create or replace function public.set_jersey_number(
  p_season_id uuid,
  p_team_id uuid,
  p_player_id uuid,
  p_number int
) returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not (public.owns_season_team(p_season_id, p_team_id)
          or public.manages_team(p_season_id, p_team_id)) then
    raise exception 'Bu takımın forma numaralarını değiştirme yetkiniz yok.'
      using errcode = '42501';
  end if;
  if p_number is null or p_number < 1 or p_number > 999 then
    raise exception 'Forma numarası 1 ile 999 arasında olmalı.';
  end if;
  if exists (
    select 1 from public.season_team_players
    where season_id = p_season_id and team_id = p_team_id
      and jersey_number = p_number and is_active
      and player_id <> p_player_id
  ) then
    raise exception 'Bu forma numarası bu takımda zaten kullanılıyor.';
  end if;
  update public.season_team_players
     set jersey_number = p_number
   where season_id = p_season_id and team_id = p_team_id
     and player_id = p_player_id and is_active;
  if not found then
    raise exception 'Futbolcu bu takımın kadrosunda bulunamadı.';
  end if;
end;
$$;

revoke all on function public.set_jersey_number(uuid, uuid, uuid, int) from public, anon;
grant execute on function public.set_jersey_number(uuid, uuid, uuid, int) to authenticated;
