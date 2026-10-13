-- "Video Linki" (Instagram / YouTube röportaj) de fotoğraf sınırına sayılmaz.
create or replace function public.enforce_match_photo_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
$$;
