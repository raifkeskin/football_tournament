-- Sezon ve grup silme = gizleme (veri kalır, geri alınabilir) ve sonucu
-- girilmemiş maçlar listesi.
--
-- Silinen sezon/grup hiçbir listede görünmez (admin dahil): okuma
-- politikaları deleted_at dolu satırı göstermez. Sezona bağlı tüm veriler
-- (takımlar, kadrolar, istatistik, haberler) can_view_season üzerinden,
-- maçlar ve olayları matches.deleted_at üzerinden gizlenir. Maçlardaki alan
-- okuma sorgusunu ucuz tutmak içindir; sezon/grup silinince birlikte dolar.
--
-- Geri alma (yalnızca veritabanından):
--   update matches set deleted_at = null where season_id = '<id>';
--   update seasons set deleted_at = null, deleted_by = null where id = '<id>';
-- (grup için aynısı group_id / groups ile).

alter table public.seasons
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid;
alter table public.groups
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid;
alter table public.matches
  add column if not exists deleted_at timestamptz;

-- Okuma politikaları
drop policy if exists seasons_read on public.seasons;
create policy seasons_read on public.seasons for select
  using (deleted_at is null and public.can_view_league(league_id));

drop policy if exists groups_read on public.groups;
create policy groups_read on public.groups for select
  using (deleted_at is null and public.can_view_season(season_id));

drop policy if exists matches_read on public.matches;
create policy matches_read on public.matches for select
  using (
    deleted_at is null
    and public.can_view_league(coalesce(league_id, (
      select s.league_id from public.seasons s where s.id = matches.season_id
    )))
  );

create or replace function public.can_view_season(p_season_id uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $$
  select case
    when exists (
      select 1 from public.seasons
      where id = p_season_id and deleted_at is not null
    ) then false
    else public.can_view_league(
      (select league_id from public.seasons where id = p_season_id)
    )
  end;
$$;

create or replace function public.can_view_match(p_match_id uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $$
  select case
    when exists (
      select 1 from public.matches
      where id = p_match_id and deleted_at is not null
    ) then false
    else public.can_view_league((
      select coalesce(m.league_id, s.league_id)
      from public.matches m
      left join public.seasons s on s.id = m.season_id
      where m.id = p_match_id
    ))
  end;
$$;

-- Silme (gizleme): admin ve turnuva sahibi; grup için bölge sorumlusu da.
create or replace function public.soft_delete_season(p_season_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not public.owns_season(p_season_id) then
    raise exception 'Bu sezonu silme yetkiniz yok.' using errcode = '42501';
  end if;
  update public.matches set deleted_at = now()
    where season_id = p_season_id and deleted_at is null;
  update public.seasons
    set deleted_at = now(), deleted_by = auth.uid(), is_default = false
    where id = p_season_id and deleted_at is null;
end;
$$;

create or replace function public.soft_delete_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  g record;
begin
  select season_id, region_id into g from public.groups where id = p_group_id;
  if not found then
    return;
  end if;
  if not (public.owns_season(g.season_id)
          or (g.region_id is not null and public.owns_region(g.region_id))) then
    raise exception 'Bu grubu silme yetkiniz yok.' using errcode = '42501';
  end if;
  update public.matches set deleted_at = now()
    where group_id = p_group_id and deleted_at is null;
  update public.groups set deleted_at = now(), deleted_by = auth.uid()
    where id = p_group_id and deleted_at is null;
end;
$$;

revoke all on function public.soft_delete_season(uuid) from public, anon;
revoke all on function public.soft_delete_group(uuid) from public, anon;
grant execute on function public.soft_delete_season(uuid) to authenticated;
grant execute on function public.soft_delete_group(uuid) to authenticated;

-- Gizlenen maça hatırlatma bildirimi gitmez.
create or replace function public.push_match_reminders()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  r record;
begin
  for r in
    select m.id, m.match_date, m.match_time
    from public.matches m
    where m.status = 'notStarted'
      and m.deleted_at is null
      and m.reminder_sent_at is null
      and m.match_date between current_date - 1 and current_date + 1
      and m.match_time ~ '^\d{1,2}:\d{2}'
      and ((m.match_date + left(m.match_time, 5)::time)
             at time zone 'Europe/Istanbul')
          between now() and now() + interval '2 hours'
  loop
    update public.matches set reminder_sent_at = now() where id = r.id;
    perform public.push_send(
      public.match_audience(r.id, false),
      'Maçın yaklaşıyor',
      public.match_title(r.id) || ' · Bugün ' || left(r.match_time, 5),
      '/',
      'reminder-' || r.id
    );
  end loop;
end;
$$;

-- Sonucu girilmemiş maçlar: maç saatinden 2 saat geçmiş, bitmemiş,
-- ertelenmemiş/iptal edilmemiş (son 60 gün). Yalnızca çağıranın yönettiği
-- maçlar: admin, turnuva sahibi, maçın grubunun bölge sorumlusu.
create or replace function public.overdue_result_matches()
returns table (
  id uuid,
  league_id uuid,
  season_id uuid,
  home_team_id uuid,
  away_team_id uuid,
  match_date date,
  match_time text
)
language sql
stable security definer
set search_path to ''
as $$
  select m.id, coalesce(m.league_id, s.league_id), m.season_id,
         m.home_team_id, m.away_team_id, m.match_date, m.match_time::text
  from public.matches m
  join public.seasons s on s.id = m.season_id and s.deleted_at is null
  left join public.groups g on g.id = m.group_id
  where auth.uid() is not null
    and m.deleted_at is null
    and m.status in ('notStarted', 'live', 'halftime')
    and m.match_date between current_date - 60 and current_date
    and m.match_time ~ '^\d{1,2}:\d{2}'
    and ((m.match_date + left(m.match_time, 5)::time)
           at time zone 'Europe/Istanbul') < now() - interval '2 hours'
    and (
      public.owns_league(coalesce(m.league_id, s.league_id))
      or (g.region_id is not null and exists (
        select 1 from public.region_owners ro
        where ro.region_id = g.region_id and ro.user_id = auth.uid()
      ))
    )
  order by m.match_date, m.match_time;
$$;

revoke all on function public.overdue_result_matches() from public, anon;
grant execute on function public.overdue_result_matches() to authenticated;
