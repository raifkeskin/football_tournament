-- Gol kesiti süresi 15 sn → 20 sn (yeni kesitler; eskiler olduğu gibi kalır).
CREATE OR REPLACE FUNCTION public.apply_highlight_starts(p_match_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_job public.match_highlight_jobs%rowtype;
  v_period int;
  v_n int;
begin
  if not public.owns_match(p_match_id) then
    raise exception 'Bu maç için yetkiniz yok.';
  end if;
  select * into v_job from public.match_highlight_jobs where match_id = p_match_id;
  if v_job.kickoff_sec is null then
    raise exception 'Önce maç başlangıcını girin.';
  end if;
  select coalesce(s.match_period_duration, 45) into v_period
    from public.matches m join public.seasons s on s.id = m.season_id
   where m.id = p_match_id;

  with c as (
    select h.id,
           case
             when h.minute > v_period then
               v_job.second_half_sec + (h.minute - v_period) * 60
             else v_job.kickoff_sec + h.minute * 60
           end + coalesce(h.added_minute, 0) * 60 as s
      from public.match_highlights h
     where h.match_id = p_match_id
       and h.status = 'pending'
       and h.minute is not null
  )
  update public.match_highlights h
     set start_sec = greatest(0, c.s),
         end_sec = greatest(0, c.s) + 20
    from c
   where c.id = h.id and c.s is not null;
  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;
