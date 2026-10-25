-- Gol kesitleri: sorumlu videodaki maç başlangıcını (ya da 2. yarı
-- başlangıcını) düzeltince o devredeki bütün kesitler aradaki fark kadar
-- kayar; uzunluk korunur. Eski başlangıç bilinmiyorsa kesit gol
-- dakikasından yeniden konur (başlangıç + dakika·60 − 11 sn).
create or replace function public.shift_match_highlights(
  p_match_id uuid,
  p_kickoff_sec integer default null,
  p_second_half_sec integer default null
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_job public.match_highlight_jobs%rowtype;
  v_period int;
  v_n int := 0;
  v_k int;
  v_h int;
begin
  if not public.owns_match(p_match_id) then
    raise exception 'Bu maç için yetkiniz yok.';
  end if;
  if coalesce(p_kickoff_sec, 0) < 0 or coalesce(p_second_half_sec, 0) < 0 then
    raise exception 'Süre negatif olamaz.';
  end if;
  select * into v_job from public.match_highlight_jobs where match_id = p_match_id;
  select coalesce(s.match_period_duration, 45) into v_period
    from public.matches m join public.seasons s on s.id = m.season_id
   where m.id = p_match_id;

  v_k := coalesce(p_kickoff_sec, v_job.kickoff_sec);
  -- 2. yarı verilmediyse 1. yarıdaki kayma 2. yarıya da uygulanır.
  v_h := coalesce(
    p_second_half_sec,
    v_job.second_half_sec + coalesce(p_kickoff_sec - v_job.kickoff_sec, 0)
  );

  with c as (
    select h.id, h.end_sec - h.start_sec as len,
           case
             when coalesce(h.minute, 0) > v_period
                  or (h.minute is null and v_job.second_half_sec is not null
                      and h.start_sec >= v_job.second_half_sec)
             then case
               when v_job.second_half_sec is not null and v_h is not null
                 then h.start_sec + (v_h - v_job.second_half_sec)
               when v_h is not null and h.minute is not null
                 then v_h + (h.minute - v_period) * 60 - 11
             end
             else case
               when v_job.kickoff_sec is not null and v_k is not null
                 then h.start_sec + (v_k - v_job.kickoff_sec)
               when v_k is not null and h.minute is not null
                 then v_k + h.minute * 60 - 11
             end
           end as new_start
      from public.match_highlights h
     where h.match_id = p_match_id
  )
  update public.match_highlights h
     set start_sec = greatest(0, c.new_start),
         end_sec = greatest(0, c.new_start) + c.len
    from c
   where c.id = h.id and c.new_start is not null
     and c.new_start <> h.start_sec;
  get diagnostics v_n = row_count;

  update public.match_highlight_jobs
     set kickoff_sec = v_k, second_half_sec = v_h
   where match_id = p_match_id;
  return v_n;
end;
$function$;

revoke all on function public.shift_match_highlights(uuid, integer, integer) from public, anon;
grant execute on function public.shift_match_highlights(uuid, integer, integer) to authenticated;
