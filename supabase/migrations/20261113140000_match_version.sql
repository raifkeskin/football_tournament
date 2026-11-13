-- Hız Faz 2B (devam): maça özel veri sürümü.
--
-- Bitmiş maçın detayı cihazda saklanır (bkz. match_detail_bundle); saklanan
-- kopyanın geçerli olup olmadığı 'match:<id>' sürümüyle anlaşılır. Maçın
-- kendisi, olayları, esamesi, medyası ya da gol kesitleri değişince sürüm
-- artar. Sezon sürümü ('season:<id>') bunun için fazla geniş: sezondaki her
-- gol, o sezonun bütün saklanan maçlarını geçersiz kılardı.
--
-- TG_ARGV[0]: 'self' (matches: satırın id'si) ya da boş (satırın match_id'si).
create or replace function public.bump_match_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[] := '{}';
begin
  if coalesce(tg_argv[0], '') = 'self' then
    if tg_op = 'DELETE' then
      v_ids := array[old.id];
    else
      v_ids := array[new.id];
    end if;
  else
    if tg_op <> 'INSERT' then
      v_ids := v_ids || old.match_id;
    end if;
    if tg_op <> 'DELETE' then
      v_ids := v_ids || new.match_id;
    end if;
  end if;
  insert into public.data_versions (scope)
  select distinct 'match:' || x from unnest(v_ids) x where x is not null
  on conflict (scope) do update
    set version = public.data_versions.version + 1, updated_at = now();
  return null;
end;
$$;

revoke all on function public.bump_match_version() from public, anon, authenticated;

-- Her biri ayrı işlem (psql, işlem bloğu dışında): tablo kilidi kısa sürer.
drop trigger if exists data_version_match on public.matches;
create trigger data_version_match
  after insert or update or delete on public.matches
  for each row execute function public.bump_match_version('self');

drop trigger if exists data_version_match on public.match_events;
create trigger data_version_match
  after insert or update or delete on public.match_events
  for each row execute function public.bump_match_version();

drop trigger if exists data_version_match on public.match_rosters;
create trigger data_version_match
  after insert or update or delete on public.match_rosters
  for each row execute function public.bump_match_version();

drop trigger if exists data_version_match on public.match_media;
create trigger data_version_match
  after insert or update or delete on public.match_media
  for each row execute function public.bump_match_version();

drop trigger if exists data_version_match on public.match_highlights;
create trigger data_version_match
  after insert or update or delete on public.match_highlights
  for each row execute function public.bump_match_version();
