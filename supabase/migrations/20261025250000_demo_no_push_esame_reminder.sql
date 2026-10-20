-- 1) Demo turnuvalardan bildirim gitmez (uygulama artık mağazada, gerçek
--    kullanıcılar demo ligleri takip edebiliyor). Kontrol tek yerde:
--    push_send, etiketteki türden (maç/haber/ceza/onay) turnuvayı bulur;
--    demo ise ne bildirim kaydı ne push yapılır. Silinen ceza satırı
--    çözülemediği için player_penalties_removed_push ayrıca bakar.
-- 2) Esame hatırlatması: maçtan 45 dk önce ilk oyuncu sayısı (sezonun
--    starting_player_count) dolmamış takımın sorumlularına bir kez push.

create or replace function public.is_demo_league(p_league_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce((select l.is_demo from public.leagues l where l.id = p_league_id), false)
$$;

create or replace function public.push_ref_is_demo(p_kind text, p_ref text)
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_id uuid;
  v_league uuid;
begin
  if p_ref is null or p_ref !~* '^[0-9a-f-]{36}$' then
    return false;
  end if;
  v_id := p_ref::uuid;
  if p_kind in ('reminder', 'schedule', 'live', 'goal', 'result', 'attend', 'esame') then
    select coalesce(m.league_id, s.league_id) into v_league
      from public.matches m left join public.seasons s on s.id = m.season_id
     where m.id = v_id;
  elsif p_kind = 'news' then
    select s.league_id into v_league
      from public.news n join public.seasons s on s.id = n.season_id
     where n.id = v_id;
  elsif p_kind in ('penalty', 'penaltyok') then
    select coalesce(m.league_id, s.league_id) into v_league
      from public.player_penalties pp
      left join public.matches m on m.id = pp.match_id
      left join public.seasons s on s.id = pp.season_id
     where pp.id = v_id;
  elsif p_kind in ('approval', 'roster') then
    select coalesce(pa.league_id, s.league_id) into v_league
      from public.pending_actions pa left join public.seasons s on s.id = pa.season_id
     where pa.id = v_id;
  end if;
  return public.is_demo_league(v_league);
exception when others then
  return false;
end;
$$;

CREATE OR REPLACE FUNCTION public.push_send(p_user_ids uuid[], p_title text, p_body text, p_url text DEFAULT '/'::text, p_tag text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_secret text;
  v_kind text := nullif(split_part(coalesce(p_tag, ''), '-', 1), '');
  v_ref text := nullif(substr(coalesce(p_tag, ''), length(coalesce(v_kind, '')) + 2), '');
  v_push uuid[];
  v_url text;
begin
  if p_user_ids is null then
    return;
  end if;
  -- Demo turnuvalardan hiçbir kullanıcıya bildirim gitmez.
  if public.push_ref_is_demo(v_kind, v_ref) then
    return;
  end if;

  begin
    insert into public.notifications (user_id, title, body, kind, ref_id)
    select distinct u, p_title, p_body, v_kind,
           case when v_ref ~* '^[0-9a-f-]{36}$' then v_ref::uuid end
      from unnest(p_user_ids) u
     where u is not null
       and exists (select 1 from auth.users au where au.id = u);
  exception when others then
    raise warning 'push_send notifications: %', sqlerrm;
  end;

  select coalesce(array_agg(distinct u), '{}') into v_push
    from unnest(p_user_ids) u
   where u is not null and public.notif_wants(u, coalesce(v_kind, ''));
  if cardinality(v_push) = 0 or not exists (
    select 1 from public.push_subscriptions where user_id = any (v_push)
  ) then
    return;
  end if;
  select value into v_secret from public.app_private_settings where key = 'push_secret';
  if coalesce(v_secret, '') = '' then
    return;
  end if;
  -- Bildirime basınca ilgili ekran açılsın.
  v_url := case
    when p_tag is not null and coalesce(p_url, '/') = '/' then '/?n=' || p_tag
    else coalesce(p_url, '/')
  end;
  perform net.http_post(
    url := 'https://qxdjebzszikeslobrozf.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'user_ids', to_jsonb(v_push),
      'title', p_title,
      'body', p_body,
      'url', v_url,
      'tag', p_tag
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    )
  );
exception when others then
  raise warning 'push_send: %', sqlerrm;
end;
$function$;

CREATE OR REPLACE FUNCTION public.player_penalties_removed_push()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_type text;
  v_minute int;
  v_league uuid;
  v_name text;
  v_title text;
  v_ids uuid[];
begin
  if old.kind not in ('red_card', 'second_yellow') or old.status = 'rejected' then
    return old;
  end if;

  select event_type, minute into v_type, v_minute
    from public.match_events where id = old.source_event_id;
  v_title := case
    when v_type = 'red_card_cancelled' then 'VAR: Kart iptali'
    when v_type is null then 'Kart iptal edildi'
    else 'Ceza kaldırıldı'
  end;

  select league_id into v_league from public.matches where id = old.match_id;
  if public.is_demo_league(v_league) then
    return old;
  end if;
  select trim(coalesce(name, '') || ' ' || coalesce(surname, ''))
    into v_name from public.players where id = old.player_id;

  -- "Onay bekleyen ceza"yı alanlar + (onaylıysa) oyuncu ve takım sorumluları.
  select array_agg(distinct uid) into v_ids from (
    select user_id as uid from public.league_owners where league_id = v_league
    union
    select ro.user_id from public.matches m
    join public.groups g on g.id = m.group_id
    join public.region_owners ro on ro.region_id = g.region_id
    where m.id = old.match_id
    union
    select p.auth_uid from public.players p
    where old.status = 'approved' and p.id = old.player_id
    union
    select tm.user_id from public.team_managers tm
    join public.season_team_players stp
      on stp.season_id = tm.season_id and stp.team_id = tm.team_id
    where old.status = 'approved'
      and stp.season_id = old.season_id and stp.player_id = old.player_id
  ) x where uid is not null;

  perform public.push_send(
    v_ids,
    v_title,
    coalesce(nullif(v_name, ''), 'Oyuncu') || ' · '
      || case when v_minute is not null then v_minute::text || '''' || ' ' else '' end
      || case old.kind when 'red_card' then 'Kırmızı kart' else 'İkinci sarı kart' end
      || ' · ceza kaldırıldı',
    '/',
    'penalty-' || old.id
  );
  return old;
exception when others then
  raise warning 'penalty removed push: %', sqlerrm;
  return old;
end;
$function$;

-- Esame hatırlatması --------------------------------------------------------

create table if not exists public.esame_reminders (
  match_id uuid not null references public.matches(id) on delete cascade,
  team_id  uuid not null,
  sent_at  timestamptz not null default now(),
  primary key (match_id, team_id)
);
alter table public.esame_reminders enable row level security;
-- Politika yok: yalnız push_esame_reminders yazar.

create or replace function public.push_esame_reminders()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  r record;
  v_ids uuid[];
begin
  for r in
    with due as (
      select m.id, m.season_id, m.match_time, m.home_team_id, m.away_team_id,
             coalesce(s.starting_player_count, 11) as need
        from public.matches m
        join public.seasons s on s.id = m.season_id
       where m.status = 'notStarted'
         and m.deleted_at is null
         and m.match_date between current_date - 1 and current_date + 1
         and m.match_time ~ '^\d{1,2}:\d{2}'
         and ((m.match_date + left(m.match_time, 5)::time)
                at time zone 'Europe/Istanbul')
             between now() and now() + interval '45 minutes'
         -- Esame henüz açılmadıysa (açılış maç saati) hatırlatma anlamsız.
         and now() >= public.match_roster_open_at(m.id)
    ),
    sides as (
      select d.id, d.season_id, d.match_time, d.need, d.home_team_id as team_id from due d
      union all
      select d.id, d.season_id, d.match_time, d.need, d.away_team_id from due d
    )
    select sd.*,
           (select count(*) from public.match_rosters mr
             where mr.match_id = sd.id and mr.team_id = sd.team_id
               and mr.is_starting) as starters
      from sides sd
     where sd.team_id is not null
       and not exists (select 1 from public.esame_reminders er
                        where er.match_id = sd.id and er.team_id = sd.team_id)
  loop
    insert into public.esame_reminders (match_id, team_id)
    values (r.id, r.team_id) on conflict do nothing;
    if r.starters >= r.need then
      continue;
    end if;

    select array_agg(distinct uid) into v_ids from (
      select tm.user_id as uid from public.team_managers tm
       where tm.season_id = r.season_id and tm.team_id = r.team_id
      union
      select p.auth_uid from public.teams t
        join public.players p on p.id = t.manager_id
       where t.id = r.team_id
    ) x where uid is not null;

    perform public.push_send(
      v_ids,
      'Esame girişini tamamlayın',
      public.match_title(r.id) || ' · ' || left(r.match_time, 5)
        || ' · İlk ' || r.need || ': ' || r.starters || ' / ' || r.need,
      '/',
      'esame-' || r.id
    );
  end loop;
end;
$$;

revoke all on function public.push_esame_reminders() from public, anon, authenticated;

select cron.unschedule('push-esame-reminders')
 where exists (select 1 from cron.job where jobname = 'push-esame-reminders');
select cron.schedule('push-esame-reminders', '*/5 * * * *',
                     'select public.push_esame_reminders()');
