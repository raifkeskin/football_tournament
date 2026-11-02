-- Dekupe üretilemeyen (yüz yok / kalabalık) fotoğrafı admin kaldırır;
-- hesabı olan oyuncuya yeni fotoğraf yüklemesi için bildirim gider.
create or replace function public.admin_remove_player_photo(p_player_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_uid uuid;
begin
  if not public.is_admin() then
    raise exception 'yetki yok';
  end if;
  select photo_url, auth_uid into v_url, v_uid from players where id = p_player_id;
  update players set photo_url = null where id = p_player_id;
  delete from player_photo_cutout_skips where photo_url = v_url;
  if v_uid is not null then
    perform public.push_send(
      array[v_uid],
      'Profil fotoğrafın kaldırıldı',
      'Fotoğrafında yüzün net görünmüyordu. Yüzünün ve omuzlarının göründüğü, '
        || 'yalnız senin olduğun yeni bir fotoğraf yükleyebilirsin.',
      '/',
      'photo-removed-' || p_player_id
    );
  end if;
end;
$$;

revoke all on function public.admin_remove_player_photo(uuid) from public, anon;
grant execute on function public.admin_remove_player_photo(uuid) to authenticated;
