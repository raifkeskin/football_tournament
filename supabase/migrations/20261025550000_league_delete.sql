-- Turnuvayı kalıcı silme (yalnız admin). Yalnız boş turnuva silinir: hiç
-- maçı yoksa ve silinmemiş (görünen) sezonu yoksa. Daha önce gizlenen
-- (deleted_at) maçsız sezonlar grupları ve kayıtlarıyla birlikte silinir;
-- turnuvaya bağlı diğer kayıtlar (sahipler, sponsorlar, takipçiler vb.)
-- yabancı anahtarlarla (on delete cascade) gider.

create or replace function public.league_delete_check(p_league_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_seasons int;
  v_matches int;
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  select count(*) into v_seasons from public.seasons
   where league_id = p_league_id and deleted_at is null;
  select count(*) into v_matches from public.matches m
   where m.league_id = p_league_id
      or m.season_id in (select id from public.seasons where league_id = p_league_id);
  return jsonb_build_object(
    'seasons', v_seasons,
    'matches', v_matches,
    'can_delete', v_seasons = 0 and v_matches = 0
  );
end;
$function$;

create or replace function public.league_delete(p_league_id uuid)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_name text;
  v_check jsonb;
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  select name into v_name from public.leagues where id = p_league_id for update;
  if not found then
    raise exception 'Turnuva bulunamadı.';
  end if;
  v_check := public.league_delete_check(p_league_id);
  if (v_check ->> 'seasons')::int > 0 then
    raise exception 'Turnuvanın sezonu var; önce sezonları silin.';
  end if;
  if (v_check ->> 'matches')::int > 0 then
    raise exception 'Turnuvanın maç kaydı var; silinemez (pasife alabilirsiniz).';
  end if;
  delete from public.seasons where league_id = p_league_id;
  delete from public.leagues where id = p_league_id;
  return v_name;
end;
$function$;

revoke all on function public.league_delete_check(uuid) from public;
revoke all on function public.league_delete(uuid) from public;
grant execute on function public.league_delete_check(uuid) to authenticated;
grant execute on function public.league_delete(uuid) to authenticated;
