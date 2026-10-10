-- Yönetim Paneli › Canlı Kuralar: kuraları listeleme, iptal ve geri alma.
--
-- * list_live_draws(): adminin tüm kuraları, kurucu başkanın kendi
--   turnuvalarının kuraları; turnuva / sezon / grup adlarıyla. Süresi dolmuş
--   ama henüz yazılmamış kuralar önce yazılır (durum doğru görünsün).
-- * cancel_live_draw(): planlı ya da süren (henüz bitmemiş) kurayı iptal
--   eder; maçlar kura bitince yazıldığı için silinecek maç yoktur.
-- * revert_live_draw(): tamamlanmış kurayı geri alır: kuranın yazdığı maçlar
--   (created_at = finalized_at) silinir, haber yayından kalkar, grup yeniden
--   kuraya açılır. Bu maçlardan biri başlamış ya da esame / olay girilmişse
--   engellenir.

create or replace function public.list_live_draws()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  for v_id in
    select d.id from public.live_draws d
    where d.status = 'scheduled' and now() >= d.end_at
      and public.owns_league(d.league_id)
  loop
    perform public.finalize_live_draw(v_id);
  end loop;

  return coalesce((
    select jsonb_agg(x order by x->>'start_at' desc)
    from (
      select jsonb_build_object(
        'id', d.id,
        'title', d.title,
        'league_name', l.name,
        'season_name', s.name,
        'group_name', g.name,
        'region_name', r.name,
        'start_at', d.start_at,
        'end_at', d.end_at,
        'status', case
          when d.status = 'scheduled' and now() < d.start_at then 'scheduled'
          when d.status = 'scheduled' then 'running'
          else d.status
        end,
        'team_count', coalesce(array_length(d.team_ids, 1), 0),
        'total_matches', d.total_matches,
        'draw_matches', (
          select count(*) from public.matches m
          where d.status = 'done' and m.group_id = d.group_id
            and m.created_at = d.finalized_at),
        'started_matches', (
          select count(*) from public.matches m
          where d.status = 'done' and m.group_id = d.group_id
            and m.created_at = d.finalized_at
            and (m.status <> 'notStarted'
                 or exists (select 1 from public.match_events e
                            where e.match_id = m.id)
                 or exists (select 1 from public.match_rosters mr
                            where mr.match_id = m.id)))
      ) as x
      from public.live_draws d
      join public.leagues l on l.id = d.league_id
      left join public.seasons s on s.id = d.season_id
      left join public.groups g on g.id = d.group_id
      left join public.season_regions r on r.id = g.region_id
      where public.owns_league(d.league_id)
    ) t
  ), '[]'::jsonb);
end;
$$;

-- Planlı ya da süren kurayı iptal (bitmiş kura için revert_live_draw).
create or replace function public.cancel_live_draw(p_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  d public.live_draws;
begin
  select * into d from public.live_draws where id = p_id for update;
  if d.id is null then
    return;
  end if;
  if not (public.owns_league(d.league_id) or public.owns_season(d.season_id)) then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  if d.status <> 'scheduled' then
    raise exception 'Bu kura zaten tamamlanmış ya da iptal edilmiş.';
  end if;
  if now() >= d.end_at then
    raise exception 'Kura tamamlandı; iptal yerine "Kurayı geri al" kullanın.';
  end if;
  update public.live_draws set status = 'cancelled' where id = p_id;
  update public.news set is_published = false where live_draw_id = p_id;
end;
$$;

create or replace function public.revert_live_draw(p_id uuid)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare
  d public.live_draws;
  v_deleted integer;
begin
  select * into d from public.live_draws where id = p_id for update;
  if d.id is null then
    raise exception 'Kura bulunamadı.';
  end if;
  if not public.owns_league(d.league_id) then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  if d.status <> 'done' then
    raise exception 'Yalnızca tamamlanmış kura geri alınabilir.';
  end if;
  if exists (
    select 1 from public.matches m
    where m.group_id = d.group_id and m.created_at = d.finalized_at
      and (m.status <> 'notStarted'
           or exists (select 1 from public.match_events e where e.match_id = m.id)
           or exists (select 1 from public.match_rosters mr where mr.match_id = m.id)
           or exists (select 1 from public.player_penalties pp where pp.match_id = m.id))
  ) then
    raise exception 'Kuranın maçlarından biri başlamış ya da esamesi girilmiş; kura geri alınamaz.';
  end if;

  delete from public.matches m
  where m.group_id = d.group_id and m.created_at = d.finalized_at;
  get diagnostics v_deleted = row_count;

  update public.live_draws set status = 'cancelled' where id = p_id;
  update public.news set is_published = false where live_draw_id = p_id;
  return v_deleted;
end;
$$;

revoke all on function public.list_live_draws() from public, anon;
revoke all on function public.revert_live_draw(uuid) from public, anon;
grant execute on function public.list_live_draws() to authenticated;
grant execute on function public.cancel_live_draw(uuid) to authenticated;
grant execute on function public.revert_live_draw(uuid) to authenticated;
