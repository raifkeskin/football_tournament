-- Uygulama hata kaydı: istemcide yakalanan hatalar (çizim/yerleşim, build,
-- yakalanmamış async). Aynı hata (parmak izi) tek satırda sayılır; yeni bir
-- hata türü ilk kez görülünce adminlere Telegram'dan kısa haber gider.

create table if not exists public.app_errors (
  id uuid primary key default gen_random_uuid(),
  fingerprint text not null unique,
  message text not null,
  stack text,
  context text,
  platform text,
  app_version text,
  last_user_id uuid references auth.users(id) on delete set null,
  last_role text,
  count integer not null default 1,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now()
);

create index if not exists app_errors_last_seen_idx on public.app_errors (last_seen desc);

alter table public.app_errors enable row level security;

drop policy if exists app_errors_admin_read on public.app_errors;
create policy app_errors_admin_read on public.app_errors
  for select to authenticated using (public.is_admin());

-- Yazma yalnızca aşağıdaki fonksiyonla (misafir de yazabilir).
create or replace function public.log_client_error(
  p_fingerprint text,
  p_message text,
  p_stack text default null,
  p_context text default null,
  p_platform text default null,
  p_app_version text default null,
  p_role text default null
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
         app_version = coalesce(left(p_app_version, 40), app_version)
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
      last_user_id, last_role
    ) values (
      v_fp, left(p_message, 2000), left(p_stack, 8000), left(p_context, 300),
      left(p_platform, 40), left(p_app_version, 40), v_uid, left(p_role, 40)
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
          || case when coalesce(p_context, '') <> '' then E'\n' || left(p_context, 120) else '' end
          || E'\n' || left(p_message, 400)
      );
    exception when others then
      raise warning 'log_client_error telegram: %', sqlerrm;
    end;
  end if;
end;
$$;

revoke all on function public.log_client_error(text, text, text, text, text, text, text) from public;
grant execute on function public.log_client_error(text, text, text, text, text, text, text) to anon, authenticated;
