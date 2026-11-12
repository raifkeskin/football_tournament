-- Bildirimler yalnız futbolcu, takım/bölge sorumlusu, kurucu başkan ve
-- admine. Takip edenlere istisna app_settings.push_follow_exceptions ile
-- (şimdilik kapalı). Açmak: update app_settings set value='true'
--   where key='push_follow_exceptions';

insert into public.app_settings (key, value)
values ('push_follow_exceptions', 'false'::jsonb)
on conflict (key) do update set value = excluded.value;

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
                 and uf.target_id = v_scorer));
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

