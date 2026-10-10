-- Hata kaydına ekran, açık realtime kanalı sayısı ve çözülmüş (web) yığın izi.
--  * screen: son açık sayfalar / sekme ("Profil › TeamSquadScreen › Popup").
--  * channels: hata anında açık realtime kanalı sayısı.
--  * stack_decoded: web'de sıkıştırılmış iz, derlemenin kaynak haritasıyla
--    tool/decode_errors.dart tarafından gerçek dosya/satıra çevrilir.

alter table public.app_errors add column if not exists screen text;
alter table public.app_errors add column if not exists channels integer;
alter table public.app_errors add column if not exists stack_decoded text;

-- Eski 7 parametreli imza kaldırılır (aynı adlı iki fonksiyon PostgREST'te
-- belirsizlik yaratır); eski uygulamalar yeni imzayı varsayılanlarla çağırır.
drop function if exists public.log_client_error(text, text, text, text, text, text, text);

create or replace function public.log_client_error(
  p_fingerprint text,
  p_message text,
  p_stack text default null,
  p_context text default null,
  p_platform text default null,
  p_app_version text default null,
  p_role text default null,
  p_screen text default null,
  p_channels integer default null
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_fp text := left(coalesce(nullif(trim(p_fingerprint), ''), md5(coalesce(p_message, ''))), 64);
  v_uid uuid := auth.uid();
  v_new boolean;
begin
  if coalesce(trim(p_message), '') = '' then
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
$$;

revoke all on function public.log_client_error(text, text, text, text, text, text, text, text, integer) from public;
grant execute on function public.log_client_error(text, text, text, text, text, text, text, text, integer) to anon, authenticated;
