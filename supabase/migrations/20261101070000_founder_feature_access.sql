-- Hakemler ve maç içgörüleri: anahtar kapalıyken admin + kurucu başkan.
-- Talimatname ve maç afişi tasarımları herkese açılır.
create or replace function public.referees_feature_on()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select public.is_admin() or public.is_any_league_owner() or coalesce((
    select value = 'true'::jsonb from public.app_settings
     where key = 'referees_enabled'), false)
$function$;

update public.app_settings set value = 'true'::jsonb
 where key in ('regulations_enabled', 'match_poster_designs_enabled');
