-- 1) Maç yönetimi uyarıları ("Maçın yönetimi boşta", "… devraldı") bildirim
--    türü ayarından bağımsız her zaman gider. push_send'e p_force eklendi:
--    tür anahtarları atlanır, yalnız ana "telefon bildirimi" anahtarı geçerli.
-- 2) Demo filtresi etiketsiz Instagram onayı (approval-ig<news id>) ve yayın
--    linki uyuşmazlığı (yt-conflict-<id>) etiketlerini de çözer.

drop function if exists public.push_send(uuid[], text, text, text, text);

create function public.push_send(
  p_user_ids uuid[],
  p_title text,
  p_body text,
  p_url text default '/',
  p_tag text default null,
  p_force boolean default false
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
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

  -- Zorunlu bildirimde tür anahtarı atlanır; ana anahtar kapalıysa gitmez.
  select coalesce(array_agg(distinct u), '{}') into v_push
    from unnest(p_user_ids) u
   where u is not null
     and case
       when p_force then coalesce(
         (select np.push_enabled from public.notification_prefs np where np.user_id = u),
         true)
       else public.notif_wants(u, coalesce(v_kind, ''))
     end;
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

revoke all on function public.push_send(uuid[], text, text, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.push_send(uuid[], text, text, text, text, boolean)
  to service_role;

create or replace function public.push_ref_is_demo(p_kind text, p_ref text)
returns boolean
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_id uuid;
  v_league uuid;
begin
  -- Etiketsiz Instagram gönderisi: approval-ig<news id>.
  if p_kind = 'approval' and p_ref ~* '^ig[0-9a-f-]{36}$' then
    select s.league_id into v_league
      from public.news n join public.seasons s on s.id = n.season_id
     where n.id = substr(p_ref, 3)::uuid;
    return public.is_demo_league(v_league);
  end if;
  -- Yayın linki uyuşmazlığı: yt-conflict-<id>.
  if p_kind = 'yt' and p_ref ~* '^conflict-[0-9a-f-]{36}$' then
    select c.league_id into v_league
      from public.youtube_link_conflicts c
     where c.id = substr(p_ref, 10)::uuid;
    return public.is_demo_league(v_league);
  end if;

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
$function$;

create or replace function public.match_control_changed()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op = 'UPDATE' then
    -- Yöneten yeniden göründü ya da el değişti: kopma bildirimi sıfırlanır.
    if new.seen_at is distinct from old.seen_at or new.user_id is distinct from old.user_id then
      new.offline_notified_at := null;
    end if;
    -- Onaysız devralma: önceki yönetene bilgi (onaylayan zaten biliyor).
    -- "Canlı" bildirimleri kapalı olsa da gider.
    if new.user_id is distinct from old.user_id
       and coalesce(current_setting('app.ctl_approved', true), '') <> 'on' then
      perform public.push_send(
        array[old.user_id],
        'Maç yönetimi',
        coalesce(public.match_label(new.match_id), 'Maç') || ': maçın yönetimini '
          || public.person_display_name(new.user_id) || ' devraldı.',
        '/',
        'live-' || new.match_id,
        true
      );
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.match_control_watch()
returns void
language plpgsql
security definer
set search_path to ''
as $function$
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
      -- "Canlı" bildirimleri kapalı olsa da gider.
      perform public.push_send(
        v_uids,
        'Maçın yönetimi boşta',
        coalesce(public.match_label(r.match_id), 'Maç') || ': '
          || public.person_display_name(r.user_id)
          || ' 2 dakikadır bağlı değil. Devralmak için dokunun.',
        '/',
        'live-' || r.match_id,
        true
      );
    end if;
    update public.match_control set offline_notified_at = now() where match_id = r.match_id;
  end loop;
end;
$function$;
