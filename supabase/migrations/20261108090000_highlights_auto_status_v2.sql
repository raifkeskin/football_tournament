-- Gol kesitleri durumu (yeni sürümler): eski highlights_auto_status her
-- boş olmayan değeri "taranıyor" gösterir; bu sürüm hatayı ayırır.
--   running: tarama şu an sürüyor
--   pending: henüz taranmadı, otomatik tarama sırada
--   retry:   tarama hata aldı, otomatik olarak yeniden denenecek
--   failed:  tarama hata aldı, otomatik deneme kalmadı
--   null:    gösterilecek durum yok (bitti ya da tarama yok)
create or replace function public.highlights_auto_status_v2(p_match_id uuid)
 returns text
 language sql
 stable security definer
 set search_path to ''
as $function$
  select case
    when j.status = 'running' then 'running'
    when j.match_id is null
         and coalesce(a.tries, 0) < 24
         and public.highlights_auto_eligible(p_match_id) then 'pending'
    when j.status = 'error'
         and j.requested_by is null
         and coalesce(a.tries, 0) < 24
         and public.highlights_auto_eligible(p_match_id) then 'retry'
    when j.status = 'error' then 'failed'
  end
  from (select p_match_id as id) x
  left join public.match_highlight_jobs j on j.match_id = x.id
  left join public.highlights_auto_attempts a on a.match_id = x.id
$function$;

grant execute on function public.highlights_auto_status_v2(uuid) to anon, authenticated;
