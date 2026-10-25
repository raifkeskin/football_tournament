-- Gol kesitleri: sorumlu videodaki maç / 2. yarı başlangıcını kaydeder
-- (set_highlight_starts), "Uygula" ile onay bekleyen kesitler gol
-- dakikasından yeniden konur (apply_highlight_starts):
--   1. yarı: başlangıç + dakika·60 (+ uzatma·60), 15 sn
--   2. yarı: 2. yarı başlangıcı + (dakika − devre süresi)·60 (+ uzatma·60)
-- Yapay zekâ yeniden çalışmaz; ince ayar ±5 sn ile yapılır.
create or replace function public.set_highlight_starts(
  p_match_id uuid,
  p_kickoff_sec integer default null,
  p_second_half_sec integer default null
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not public.owns_match(p_match_id) then
    raise exception 'Bu maç için yetkiniz yok.';
  end if;
  if coalesce(p_kickoff_sec, 0) < 0 or coalesce(p_second_half_sec, 0) < 0 then
    raise exception 'Süre negatif olamaz.';
  end if;
  update public.match_highlight_jobs
     set kickoff_sec = coalesce(p_kickoff_sec, kickoff_sec),
         second_half_sec = coalesce(p_second_half_sec, second_half_sec)
   where match_id = p_match_id;
end;
$function$;

create or replace function public.apply_highlight_starts(p_match_id uuid)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
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
         end_sec = greatest(0, c.s) + 15
    from c
   where c.id = h.id and c.s is not null;
  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

revoke all on function public.set_highlight_starts(uuid, integer, integer) from public, anon;
revoke all on function public.apply_highlight_starts(uuid) from public, anon;
grant execute on function public.set_highlight_starts(uuid, integer, integer) to authenticated;
grant execute on function public.apply_highlight_starts(uuid) to authenticated;
