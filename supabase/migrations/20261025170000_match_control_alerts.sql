-- Maç yönetimi bildirimleri:
-- 1) Yöneten kişi canlı maçta 2 dakikadır görünmüyorsa (bağlantı koptu)
--    maçı yönetebilen diğer sorumlulara bir kez bildirim gider; dokununca
--    maç açılır, "Devral" onaysız çalışır. Kişi geri gelir ya da biri
--    devralırsa sayaç sıfırlanır (bir sonraki kopuşta yine bildirilir).
-- 2) Biri yönetimi devralınca (onay vermeden) önceki yöneten haberdar edilir.
-- Etiket live-<maç>: eski uygulama sürümlerinde de maç ekranını açar.

alter table public.match_control add column if not exists offline_notified_at timestamptz;

-- Maçı yönetebilen sorumlular (bildirim için): turnuva sahipleri, maçın
-- grubunun bölge sorumluları ve gözlemci.
create or replace function public.match_managers(p_match_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(array_agg(distinct u), '{}') from (
    select o.user_id as u
      from public.matches m
      left join public.seasons s on s.id = m.season_id
      join public.league_owners o on o.league_id = coalesce(m.league_id, s.league_id)
     where m.id = p_match_id
    union
    select ro.user_id
      from public.matches m
      join public.groups g on g.id = m.group_id
      join public.region_owners ro on ro.region_id = g.region_id
     where m.id = p_match_id
    union
    select m.observer_id from public.matches m
     where m.id = p_match_id and m.observer_id is not null
  ) x
$$;
revoke all on function public.match_managers(uuid) from public, anon, authenticated;

create or replace function public.match_label(p_match_id uuid)
returns text
language sql
stable
security definer
set search_path to ''
as $$
  select ht.name || ' – ' || at.name
    from public.matches m
    join public.teams ht on ht.id = m.home_team_id
    join public.teams at on at.id = m.away_team_id
   where m.id = p_match_id
$$;
revoke all on function public.match_label(uuid) from public, anon, authenticated;

create or replace function public.match_control_changed()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if tg_op = 'UPDATE' then
    -- Yöneten yeniden göründü ya da el değişti: kopma bildirimi sıfırlanır.
    if new.seen_at is distinct from old.seen_at or new.user_id is distinct from old.user_id then
      new.offline_notified_at := null;
    end if;
    -- Onaysız devralma: önceki yönetene bilgi (onaylayan zaten biliyor).
    if new.user_id is distinct from old.user_id
       and coalesce(current_setting('app.ctl_approved', true), '') <> 'on' then
      perform public.push_send(
        array[old.user_id],
        'Maç yönetimi',
        coalesce(public.match_label(new.match_id), 'Maç') || ': maçın yönetimini '
          || public.person_display_name(new.user_id) || ' devraldı.',
        '/',
        'live-' || new.match_id
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists match_control_changed on public.match_control;
create trigger match_control_changed
  before update on public.match_control
  for each row execute function public.match_control_changed();

-- Onayla devir: tetikleyici önceki yönetene bildirim göndermesin.
create or replace function public.match_control_answer(p_match_id uuid, p_approve boolean)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  c public.match_control;
begin
  select * into c from public.match_control where match_id = p_match_id for update;
  if c.match_id is null or c.user_id <> auth.uid() then
    raise exception 'Maçı siz yönetmiyorsunuz.';
  end if;
  if p_approve and c.req_user is not null then
    perform set_config('app.ctl_approved', 'on', true);
    update public.match_control
       set user_id = c.req_user, since = now(), seen_at = now(), req_user = null, req_at = null
     where match_id = p_match_id;
    perform set_config('app.ctl_approved', '', true);
  else
    update public.match_control set req_user = null, req_at = null where match_id = p_match_id;
  end if;
  return public.match_control_state(p_match_id);
end;
$$;

-- Dakikada bir (cron): bağlantısı kopan yöneticiyi diğer sorumlulara bildir.
create or replace function public.match_control_watch()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  r record;
  v_uids uuid[];
begin
  for r in
    select c.match_id, c.user_id
      from public.match_control c
      join public.matches m on m.id = c.match_id
     where c.seen_at < now() - interval '2 minutes'
       and c.offline_notified_at is null
       and m.status in ('live', 'halftime')
       and m.deleted_at is null
  loop
    v_uids := array(
      select u from unnest(public.match_managers(r.match_id)) u where u <> r.user_id
    );
    if cardinality(v_uids) > 0 then
      perform public.push_send(
        v_uids,
        'Maçın yönetimi boşta',
        coalesce(public.match_label(r.match_id), 'Maç') || ': '
          || public.person_display_name(r.user_id)
          || ' 2 dakikadır bağlı değil. Devralmak için dokunun.',
        '/',
        'live-' || r.match_id
      );
    end if;
    update public.match_control set offline_notified_at = now() where match_id = r.match_id;
  end loop;
end;
$$;
revoke all on function public.match_control_watch() from public, anon, authenticated;

select cron.unschedule('match-control-watch')
 where exists (select 1 from cron.job where jobname = 'match-control-watch');
select cron.schedule('match-control-watch', '* * * * *', 'select public.match_control_watch()');
