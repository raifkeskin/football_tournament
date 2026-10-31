-- Oturum kendiliğinden kapandı (yenileme reddedildi): uygulama bildirir,
-- kayda geçer ve adminlere Telegram'dan haber verilir. O anda oturum
-- düşmüş olabileceği için misafir de çağırabilir; saatte en çok 30 bildirim.

create table if not exists public.session_drops (
  id bigint generated always as identity primary key,
  user_id uuid,
  reason text,
  recovered boolean not null default false,
  platform text,
  app_version text,
  created_at timestamptz not null default now()
);
alter table public.session_drops enable row level security;
revoke all on public.session_drops from anon, authenticated;

create or replace function public.report_session_drop(
  p_user_id uuid, p_reason text, p_recovered boolean,
  p_platform text, p_app_version text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_name text;
begin
  if (select count(*) from public.session_drops
       where created_at > now() - interval '1 hour') >= 30 then
    return;
  end if;
  insert into public.session_drops (user_id, reason, recovered, platform, app_version)
  values (p_user_id, left(p_reason, 60), coalesce(p_recovered, false),
          left(p_platform, 20), left(p_app_version, 30));

  select btrim(p.name || ' ' || p.surname) into v_name
    from public.players p where p.auth_uid = p_user_id limit 1;
  if v_name is null then
    select coalesce(nullif(u.raw_user_meta_data ->> 'full_name', ''),
                    case when split_part(u.email, '@', 1) ~ '^5[0-9]{9}$'
                         then public.format_phone_raw10(split_part(u.email, '@', 1))
                         else u.email end)
      into v_name from auth.users u where u.id = p_user_id;
  end if;

  perform public.telegram_notify(
    array(select user_id from public.admins where user_id is not null),
    '🔌 Oturum düştü · ' || coalesce(v_name, 'bilinmeyen kullanıcı')
      || E'\n' || coalesce(p_platform, '?') || ' · ' || coalesce(p_app_version, '?')
      || E'\nSebep: ' || coalesce(p_reason, '?')
      || E'\n' || case when p_recovered then '✅ Sessizce yeniden girildi'
                       else '⚠️ Tekrar giriş istendi' end
  );
end;
$$;
revoke all on function public.report_session_drop(uuid, text, boolean, text, text) from public;
grant execute on function public.report_session_drop(uuid, text, boolean, text, text) to anon, authenticated;
