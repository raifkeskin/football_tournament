-- Menüdeki "Sorun Bildir / Öneri Gönder": kullanıcı mesaj yazar, kayıt
-- app_feedback'e düşer ve yöneticilere Telegram'dan bildirilir.
--
-- * Misafir de gönderebilir; giriş yapmışsa ad ve telefon sunucuda
--   hesaptan eklenir (istemciden alınmaz).
-- * Kötüye kullanım sınırı: kişi başı saatte 5, misafirler toplam saatte 30.

create table if not exists public.app_feedback (
  id           bigint generated always as identity primary key,
  user_id      uuid,
  message      text not null check (char_length(message) between 3 and 2000),
  platform     text,
  app_version  text,
  role         text,
  league_name  text,
  created_at   timestamptz not null default now()
);
create index if not exists app_feedback_created_idx
  on public.app_feedback (created_at desc);

alter table public.app_feedback enable row level security;
-- Politika yok: yalnız send_feedback (security definer) yazar.

create or replace function public.send_feedback(
  p_message text,
  p_platform text default null,
  p_app_version text default null,
  p_role text default null,
  p_league_name text default null
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_msg text := btrim(coalesce(p_message, ''));
  v_name text;
  v_phone text;
begin
  if char_length(v_msg) < 3 then
    raise exception 'Mesaj çok kısa';
  end if;
  v_msg := left(v_msg, 2000);

  if v_uid is not null then
    if (select count(*) from public.app_feedback
         where user_id = v_uid and created_at > now() - interval '1 hour') >= 5 then
      raise exception 'Çok fazla mesaj gönderdiniz, biraz sonra tekrar deneyin';
    end if;
  elsif (select count(*) from public.app_feedback
          where user_id is null and created_at > now() - interval '1 hour') >= 30 then
    raise exception 'Çok fazla mesaj gönderildi, biraz sonra tekrar deneyin';
  end if;

  insert into public.app_feedback (user_id, message, platform, app_version, role, league_name)
  values (v_uid, v_msg, left(p_platform, 40), left(p_app_version, 60),
          left(p_role, 40), left(p_league_name, 120));

  if v_uid is not null then
    select nullif(btrim(u.name), ''), nullif(btrim(u.phone), '')
      into v_name, v_phone
      from public.app_users u where u.auth_uid = v_uid limit 1;
    if v_name is null then
      select nullif(btrim(concat_ws(' ', p.name, p.surname)), '')
        into v_name
        from public.players p where p.auth_uid = v_uid limit 1;
    end if;
    if v_phone is null then
      select nullif(a.phone, '') into v_phone from auth.users a where a.id = v_uid;
    end if;
  end if;

  begin
    perform public.telegram_notify(
      array(select user_id from public.admins where user_id is not null),
      '💬 Yeni geri bildirim'
        || E'\n' || coalesce(v_name, case when v_uid is null then 'Misafir' else 'Adsız hesap' end)
        || coalesce(' · ' || v_phone, '')
        || E'\n' || coalesce(left(p_platform, 40), '?')
        || ' · ' || coalesce(left(p_app_version, 60), '?')
        || ' · ' || coalesce(left(p_role, 40), 'misafir')
        || coalesce(E'\nTurnuva: ' || nullif(left(p_league_name, 120), ''), '')
        || E'\n\n' || left(v_msg, 3000)
    );
  exception when others then
    raise warning 'send_feedback telegram: %', sqlerrm;
  end;
end;
$$;

revoke all on function public.send_feedback(text, text, text, text, text) from public;
grant execute on function public.send_feedback(text, text, text, text, text) to anon, authenticated;
