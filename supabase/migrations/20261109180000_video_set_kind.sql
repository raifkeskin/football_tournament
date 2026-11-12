-- Maç röportajının türünü (maç öncesi / maç anı / maç sonrası) değiştirir.
create or replace function public.video_set_kind(p_id uuid, p_kind text)
 returns void language plpgsql security definer set search_path to ''
as $function$
declare
  v_season uuid;
  v_match uuid;
begin
  if p_kind not in ('pre', 'live', 'post') then
    raise exception 'Geçersiz tür.';
  end if;
  select season_id, match_id into v_season, v_match from public.videos where id = p_id;
  if v_season is null or v_match is null
     or not public.can_manage_season_media(v_season) then
    raise exception 'Yetkiniz yok.';
  end if;
  update public.videos set kind = p_kind where id = p_id;
end;
$function$;
grant execute on function public.video_set_kind(uuid, text) to authenticated;
