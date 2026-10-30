-- Uygulama kurulumları: her cihaz (rastgele kimlik) açılışta platformunu,
-- sürümünü ve varsa hesabını bildirir. Admin İstatistikler ekranı sürüm
-- dağılımını ve kayıt sayılarını buradan okur. Tabloyu yalnız fonksiyonlar
-- yazar/okur.
create table if not exists public.app_clients (
  client_id uuid primary key,
  user_id uuid references auth.users (id) on delete set null,
  platform text not null,
  app_version text,
  first_seen timestamptz not null default now(),
  last_seen timestamptz not null default now()
);
create index if not exists app_clients_last_seen on public.app_clients (last_seen);
alter table public.app_clients enable row level security;
revoke all on public.app_clients from anon, authenticated;

create or replace function public.client_ping(
  p_client_id uuid, p_platform text, p_version text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if p_client_id is null or coalesce(p_platform, '') = ''
     or length(p_platform) > 20 or length(coalesce(p_version, '')) > 40 then
    return;
  end if;
  insert into public.app_clients (client_id, user_id, platform, app_version)
  values (p_client_id, auth.uid(), p_platform, nullif(p_version, ''))
  on conflict (client_id) do update
     set user_id = coalesce(auth.uid(), public.app_clients.user_id),
         platform = excluded.platform,
         app_version = coalesce(excluded.app_version,
                                public.app_clients.app_version),
         last_seen = now();
end;
$$;
revoke all on function public.client_ping(uuid, text, text) from public;
grant execute on function public.client_ping(uuid, text, text)
  to anon, authenticated;

-- Admin İstatistikler: kullanıcı / futbolcu sayıları, etkin cihazlar ve
-- son 30 günde açılan cihazların sürüm dağılımı.
create or replace function public.admin_app_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Yalnız admin.';
  end if;
  return jsonb_build_object(
    'users', (select count(*) from auth.users),
    'users_24h', (select count(*) from auth.users
                   where last_sign_in_at > now() - interval '1 day'),
    'users_7d', (select count(*) from auth.users
                  where last_sign_in_at > now() - interval '7 days'),
    'users_new_7d', (select count(*) from auth.users
                      where created_at > now() - interval '7 days'),
    'players', (select count(*) from public.players),
    'players_linked', (select count(*) from public.players
                        where auth_uid is not null),
    'push_devices', (select count(distinct user_id)
                       from public.push_subscriptions),
    'clients_1d', (select count(*) from public.app_clients
                    where last_seen > now() - interval '1 day'),
    'clients_7d', (select count(*) from public.app_clients
                    where last_seen > now() - interval '7 days'),
    'clients_30d', (select count(*) from public.app_clients
                     where last_seen > now() - interval '30 days'),
    'tracking_since', (select min(first_seen) from public.app_clients),
    'versions', coalesce((
      select jsonb_agg(jsonb_build_object(
               'platform', platform, 'version', app_version,
               'devices', n, 'users', u)
             order by platform, n desc)
        from (select platform, coalesce(app_version, '?') as app_version,
                     count(*) as n, count(distinct user_id) as u
                from public.app_clients
               where last_seen > now() - interval '30 days'
               group by 1, 2) v), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.admin_app_stats() from public, anon;
grant execute on function public.admin_app_stats() to authenticated;
