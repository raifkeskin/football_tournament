-- Maç başına fotoğraf sınırı 0 = sınırsız.

CREATE OR REPLACE FUNCTION public.enforce_match_photo_limit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_limit int;
  v_count int;
begin
  if new.media_type in ('Maç Yayın Linki', 'Fotoğraf Albümü', 'Video Linki') then
    return new;
  end if;

  select coalesce((value #>> '{}')::int, 20) into v_limit
  from public.app_settings where key = 'match_photo_limit';
  v_limit := coalesce(v_limit, 20);
  if v_limit <= 0 then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtext('match_photo_limit:' || new.match_id::text));

  select count(*) into v_count
  from public.match_media
  where match_id = new.match_id
    and media_type not in ('Maç Yayın Linki', 'Fotoğraf Albümü', 'Video Linki');

  if v_count >= v_limit then
    raise exception 'Bu maç için fotoğraf sınırına ulaşıldı (%).', v_limit
      using errcode = 'check_violation';
  end if;
  return new;
end;
$function$;
