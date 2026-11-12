-- Bildirim daveti: kullanıcı ana sayfa bandından bildirimleri açınca
-- notification_prefs.opted_in_at dolar; futbolcu/yönetici olmasa da
-- takip ettiği turnuva, takım ve oyuncuların bildirimleri gelir.

alter table public.notification_prefs
  add column if not exists opted_in_at timestamptz;

create or replace function public.notif_opt_in()
 returns void
 language sql
 security definer
 set search_path to ''
as $$
  insert into public.notification_prefs (user_id, opted_in_at, push_enabled)
  values (auth.uid(), now(), true)
  on conflict (user_id) do update
    set opted_in_at = coalesce(public.notification_prefs.opted_in_at, now()),
        push_enabled = true;
$$;
grant execute on function public.notif_opt_in() to authenticated;

-- Davet bandı gösterilsin mi: bildirimi zaten açmış, futbolcu ya da
-- yönetici olana gösterilmez.
create or replace function public.notif_invite_needed()
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $$
  select auth.uid() is not null
     and not exists (select 1 from public.notification_prefs np
                      where np.user_id = auth.uid() and np.opted_in_at is not null)
     and not exists (select 1 from public.season_team_players stp
                      join public.players p on p.id = stp.player_id
                     where stp.is_active and p.auth_uid = auth.uid())
     and not exists (select 1 from public.admins a where a.user_id = auth.uid())
     and not exists (select 1 from public.league_owners o where o.user_id = auth.uid())
     and not exists (select 1 from public.region_owners r where r.user_id = auth.uid())
     and not exists (select 1 from public.team_managers t where t.user_id = auth.uid());
$$;
grant execute on function public.notif_invite_needed() to authenticated;

create or replace function public.push_send(p_user_ids uuid[], p_title text, p_body text, p_url text DEFAULT '/'::text, p_tag text DEFAULT NULL::text, p_force boolean DEFAULT false)
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
  v_paused jsonb;
  v_match uuid;
  v_scorer uuid;
  v_follow boolean;
  v_players uuid[];
  v_league uuid;
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

  -- Geçici olarak telefona gönderilmeyen türler (uygulamadaki listede
  -- kalır). app_settings.push_paused_kinds; ilk yarı sonucu 'halftime'.
  if not p_force then
    select value into v_paused from public.app_settings
     where key = 'push_paused_kinds';
    if coalesce(v_paused, '[]'::jsonb) ? (case
         when v_kind = 'live' and p_title = 'İlk yarı sonucu' then 'halftime'
         else coalesce(v_kind, '')
       end) then
      return;
    end if;
  end if;

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

  -- Geçici kısıt: futbolcu/yönetici değilse yalnız Takip Listem'den.
  if not p_force and cardinality(v_push) > 0 and coalesce(
       (select value from public.app_settings where key = 'push_players_only'),
       'false'::jsonb) = 'true'::jsonb then
    if v_ref ~* '^[0-9a-f-]{36}$' then
      v_match := v_ref::uuid;
    end if;
    -- Takip Listem istisnası (takım sonucu / oyuncu golü); kapalıyken
    -- yalnız futbolcu ve yöneticiler.
    v_follow := coalesce(
      (select value from public.app_settings where key = 'push_follow_exceptions'),
      'false'::jsonb) = 'true'::jsonb;
    begin
      v_scorer := nullif(current_setting('push.scorer', true), '')::uuid;
    exception when others then
      v_scorer := null;
    end;
    -- Golün oyuncuları (atan + asist yapan), virgülle.
    begin
      v_players := string_to_array(
        nullif(current_setting('push.players', true), ''), ',')::uuid[];
    exception when others then
      v_players := null;
    end;
    if v_scorer is not null then
      v_players := array_append(coalesce(v_players, '{}'), v_scorer);
    end if;
    if v_match is not null then
      select league_id into v_league from public.matches where id = v_match;
    end if;
    select coalesce(array_agg(u), '{}') into v_push
      from unnest(v_push) u
     where exists (
             select 1 from public.season_team_players stp
               join public.players p on p.id = stp.player_id
              where stp.is_active and p.auth_uid = u)
        or exists (select 1 from public.admins a where a.user_id = u)
        or exists (select 1 from public.league_owners o where o.user_id = u)
        or exists (select 1 from public.region_owners r where r.user_id = u)
        or exists (select 1 from public.team_managers t where t.user_id = u)
        or (v_follow and v_kind = 'result' and v_match is not null and exists (
              select 1 from public.matches m
               where m.id = v_match
                 and (exists (select 1 from public.user_follows uf
                               where uf.user_id = u and uf.kind = 'team'
                                 and uf.target_id in (m.home_team_id, m.away_team_id))
                      or exists (select 1 from public.followed_teams f
                                  where f.user_id = u
                                    and f.team_id in (m.home_team_id, m.away_team_id)))))
        or (v_follow and v_kind = 'goal' and v_scorer is not null and exists (
              select 1 from public.user_follows uf
               where uf.user_id = u and uf.kind = 'player'
                 and uf.target_id = v_scorer))
        -- Bildirim davetiyle açanlar (notification_prefs.opted_in_at):
        -- takip ettiği turnuvanın maçları, takımının sonucu, oyuncusunun
        -- golü / asisti.
        or (exists (select 1 from public.notification_prefs np
                     where np.user_id = u and np.opted_in_at is not null)
            and (
              (v_league is not null
               and v_kind in ('schedule', 'live', 'goal', 'result')
               and exists (select 1 from public.followed_leagues fl
                            where fl.user_id = u and fl.league_id = v_league))
              or (v_kind = 'result' and v_match is not null and exists (
                    select 1 from public.matches m
                     where m.id = v_match
                       and (exists (select 1 from public.user_follows uf
                                     where uf.user_id = u and uf.kind = 'team'
                                       and uf.target_id in (m.home_team_id, m.away_team_id))
                            or exists (select 1 from public.followed_teams f
                                        where f.user_id = u
                                          and f.team_id in (m.home_team_id, m.away_team_id)))))
              or (v_kind = 'goal' and v_players is not null and exists (
                    select 1 from public.user_follows uf
                     where uf.user_id = u and uf.kind = 'player'
                       and uf.target_id = any (v_players)))
            ));
  end if;

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

create or replace function public.match_events_goal_push()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_m record;
  v_home int;
  v_away int;
  v_scorer text;
  v_assist text;
  v_body text;
  v_to uuid[];
begin
  if new.event_type <> 'goal' then
    return new;
  end if;
  select id, status, home_team_id, away_team_id into v_m
    from public.matches where id = new.match_id;
  if v_m.id is null or v_m.status not in ('live', 'halftime') then
    return new;
  end if;

  select
    count(*) filter (where (e.team_id = v_m.home_team_id and not coalesce(e.is_own_goal, false))
                        or (e.team_id = v_m.away_team_id and coalesce(e.is_own_goal, false))),
    count(*) filter (where (e.team_id = v_m.away_team_id and not coalesce(e.is_own_goal, false))
                        or (e.team_id = v_m.home_team_id and coalesce(e.is_own_goal, false)))
    into v_home, v_away
    from public.match_events e
   where e.match_id = new.match_id and e.event_type = 'goal';

  select trim(coalesce(name, '') || ' ' || coalesce(surname, '')) into v_scorer
    from public.players where id = new.player_id;
  select trim(coalesce(name, '') || ' ' || coalesce(surname, '')) into v_assist
    from public.players where id = new.assist_player_id;

  v_body := public.match_score_text(new.match_id, v_home, v_away)
    || E'\n'
    || coalesce(public.minute_label(new.minute, new.added_minute) || ' ', '')
    || coalesce(nullif(v_scorer, ''), 'Gol')
    || case when coalesce(new.is_own_goal, false) then ' (K.K.)'
            when coalesce(new.is_penalty, false) then ' (P)' else '' end
    || case when nullif(v_assist, '') is not null
            then ' (Asist: ' || v_assist || ')' else '' end;

  v_to := public.match_audience(new.match_id, false);
  if new.player_id is not null and not coalesce(new.is_own_goal, false) then
    v_to := v_to || coalesce((
      select array_agg(uf.user_id) from public.user_follows uf
       where uf.kind = 'player'
         and uf.target_id in (new.player_id, new.assist_player_id)), '{}');
    perform set_config('push.scorer', new.player_id::text, true);
    perform set_config('push.players',
      concat_ws(',', new.player_id::text, new.assist_player_id::text), true);
  end if;

  perform public.push_send(v_to, 'GOL!', v_body, '/', 'goal-' || new.match_id);
  perform set_config('push.scorer', '', true);
  perform set_config('push.players', '', true);
  return new;
end;
$function$;
