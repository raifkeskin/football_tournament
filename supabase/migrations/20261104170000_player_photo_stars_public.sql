-- Kariyerim › Fotoğraflarım: yıldızlanan maç fotoğrafları, futbolcunun
-- fotoğraf izni varsa (player_photo_hold'da kaydı yoksa) herkese açık;
-- izin yoksa yalnız kendisi (ve yöneticiler) görür.

create or replace function public.player_photos_public(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.player_photo_hold h where h.player_id = p_player_id
  );
$$;

revoke all on function public.player_photos_public(uuid) from public;
grant execute on function public.player_photos_public(uuid)
  to anon, authenticated;

drop policy if exists player_photo_stars_select on public.player_photo_stars;
create policy player_photo_stars_select on public.player_photo_stars
  for select to anon, authenticated
  using (
    public.player_photos_public(player_id)
    or player_id in (select p.id from public.players p
                     where p.auth_uid = auth.uid())
    or public.is_admin()
    or public.is_any_league_owner()
    or public.is_any_region_owner()
  );

grant select on public.player_photo_stars to anon;
