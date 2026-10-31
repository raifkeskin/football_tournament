-- Hata kaydı: galeriye çift dokunuş hataları yazılmaz (Telegram'a düşmez).

CREATE OR REPLACE FUNCTION public.log_client_error(p_fingerprint text, p_message text, p_stack text DEFAULT NULL::text, p_context text DEFAULT NULL::text, p_platform text DEFAULT NULL::text, p_app_version text DEFAULT NULL::text, p_role text DEFAULT NULL::text, p_screen text DEFAULT NULL::text, p_channels integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_fp text := left(coalesce(nullif(trim(p_fingerprint), ''), md5(coalesce(p_message, ''))), 64);
  v_uid uuid := auth.uid();
  v_new boolean;
begin
  if coalesce(trim(p_message), '') = '' then
    return;
  end if;
  -- Galeri açılırken ikinci dokunuş (Android already_active, iOS
  -- multiple_request): kullanıcıya etkisi yok; eski sürümler de gönderir.
  if p_message like 'PlatformException(already\_active,%'
     or p_message like 'PlatformException(multiple\_request,%' then
    return;
  end if;

  update public.app_errors
     set count = count + 1,
         last_seen = now(),
         last_user_id = coalesce(v_uid, last_user_id),
         last_role = coalesce(left(p_role, 40), last_role),
         platform = coalesce(left(p_platform, 40), platform),
         app_version = coalesce(left(p_app_version, 40), app_version),
         screen = coalesce(left(nullif(p_screen, ''), 300), screen),
         channels = coalesce(p_channels, channels)
   where fingerprint = v_fp;
  v_new := not found;

  if v_new then
    -- Kötüye kullanım sınırı: saatte en fazla 200 yeni hata türü.
    if (select count(*) from public.app_errors
         where first_seen > now() - interval '1 hour') >= 200 then
      return;
    end if;
    insert into public.app_errors (
      fingerprint, message, stack, context, platform, app_version,
      last_user_id, last_role, screen, channels
    ) values (
      v_fp, left(p_message, 2000), left(p_stack, 8000), left(p_context, 300),
      left(p_platform, 40), left(p_app_version, 40), v_uid, left(p_role, 40),
      left(nullif(p_screen, ''), 300), p_channels
    )
    on conflict (fingerprint) do update
      set count = public.app_errors.count + 1, last_seen = now();

    begin
      perform public.telegram_notify(
        array(select user_id from public.admins where user_id is not null),
        '⚠️ Yeni uygulama hatası'
          || E'\n' || coalesce(left(p_platform, 40), '?')
          || ' · ' || coalesce(left(p_app_version, 40), '?')
          || ' · ' || coalesce(left(p_role, 40), 'misafir')
          || case when coalesce(p_screen, '') <> '' then E'\nEkran: ' || left(p_screen, 200) else '' end
          || case when p_channels is not null then E'\nAçık kanal: ' || p_channels else '' end
          || case when coalesce(p_context, '') <> '' then E'\n' || left(p_context, 120) else '' end
          || E'\n' || left(p_message, 400)
      );
    exception when others then
      raise warning 'log_client_error telegram: %', sqlerrm;
    end;
  end if;
end;
$function$;
