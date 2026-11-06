-- Oyuncu kartında kalem: kimliği doğrulanmamış futbolcunun ad, soyad ve
-- doğum tarihi. Admin, futbolcunun turnuvasının kurucu başkanı ve bölge
-- sorumlusu düzenleyebilir; kimlik onaylıysa düzenlenemez.
create or replace function public.can_edit_player_basic(p_player uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $$
  select auth.uid() is not null
     and not exists (select 1 from public.player_verifications v where v.player_id = p_player)
     and (
       public.is_admin()
       or exists (
         select 1 from public.season_team_players stp
           join public.seasons s on s.id = stp.season_id
          where stp.player_id = p_player
            and (public.owns_league(s.league_id)
                 or exists (select 1 from public.region_owners ro
                              join public.season_regions sr on sr.id = ro.region_id
                             where sr.season_id = s.id and ro.user_id = auth.uid())))
     )
$$;
revoke all on function public.can_edit_player_basic(uuid) from public, anon;
grant execute on function public.can_edit_player_basic(uuid) to authenticated;

create or replace function public.player_edit_basic(
  p_player uuid, p_name text, p_surname text, p_birth date
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not public.can_edit_player_basic(p_player) then
    raise exception 'Bu futbolcunun bilgilerini düzenleme yetkiniz yok (kimliği doğrulanmış olabilir).'
      using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_name, ''))) < 2 or length(btrim(coalesce(p_surname, ''))) < 2 then
    raise exception 'Ad ve soyad en az 2 harf olmalı.';
  end if;
  if p_birth is not null and (p_birth > current_date - interval '5 years' or p_birth < date '1930-01-01') then
    raise exception 'Doğum tarihi geçersiz.';
  end if;
  update public.players
     set name = btrim(p_name), surname = btrim(p_surname), birth_date = p_birth
   where id = p_player;
end;
$$;
revoke all on function public.player_edit_basic(uuid, text, text, date) from public, anon;
grant execute on function public.player_edit_basic(uuid, text, text, date) to authenticated;
