-- Turnuva talebi (1. aşama): "Turnuvanı Kur" formu. Talep kodla (LM-0001)
-- kaydedilir, adminlere Telegram'dan bildirilir. Admin "Turnuva Talepleri"
-- ekranından durumunu yönetir. Uygulamada fiyat / ödeme yok (mağaza kuralı);
-- teklif telefon / WhatsApp ile verilir.
-- Görünürlük: app_settings.tournament_requests_enabled (admin her zaman görür).

insert into public.app_settings (key, value)
values ('tournament_requests_enabled', 'false'::jsonb)
on conflict (key) do nothing;

create sequence if not exists public.tournament_request_code_seq;

create table if not exists public.tournament_requests (
  id uuid primary key default gen_random_uuid(),
  code text not null unique
    default 'LM-' || lpad(nextval('public.tournament_request_code_seq')::text, 4, '0'),
  user_id uuid references auth.users (id) on delete set null,
  info_only boolean not null default false,
  name text,
  city text,
  start_hint text,
  kind text,
  team_count int check (team_count between 2 and 256),
  group_count int check (group_count between 1 and 32),
  double_round boolean not null default false,
  knockout boolean not null default false,
  players_format text,
  est_matches int,
  extras text[] not null default '{}',
  contact_name text not null,
  phone text not null,
  phone_raw10 text,
  organization text,
  note text,
  platform text,
  app_version text,
  status text not null default 'new'
    check (status in ('new', 'contacted', 'offered', 'won', 'lost', 'cancelled')),
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists tournament_requests_created_idx
  on public.tournament_requests (created_at desc);
create index if not exists tournament_requests_user_idx
  on public.tournament_requests (user_id);

-- Telefon içerir: yalnız talep sahibi ve admin okur; yazma RPC / admin.
alter table public.tournament_requests enable row level security;

drop policy if exists tournament_requests_read on public.tournament_requests;
create policy tournament_requests_read on public.tournament_requests
  for select using (user_id = auth.uid() or public.is_admin());

drop policy if exists tournament_requests_admin_update on public.tournament_requests;
create policy tournament_requests_admin_update on public.tournament_requests
  for update using (public.is_admin()) with check (public.is_admin());

revoke all on public.tournament_requests from anon;
grant select, update on public.tournament_requests to authenticated;

create or replace function public.tournament_requests_touch()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;

drop trigger if exists tournament_requests_touch on public.tournament_requests;
create trigger tournament_requests_touch
  before update on public.tournament_requests
  for each row execute function public.tournament_requests_touch();

-- Talep gönder: misafir (oturumsuz) da gönderebilir; telefon zorunlu.
create or replace function public.submit_tournament_request(
  p_info_only boolean,
  p_name text,
  p_city text,
  p_start_hint text,
  p_kind text,
  p_team_count int,
  p_group_count int,
  p_double_round boolean,
  p_knockout boolean,
  p_players_format text,
  p_est_matches int,
  p_extras text[],
  p_contact_name text,
  p_phone text,
  p_organization text,
  p_note text,
  p_platform text default null,
  p_app_version text default null
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_raw text := right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 10);
  v_name text := left(btrim(coalesce(p_contact_name, '')), 80);
  v_id uuid;
  v_code text;
  v_kind text;
begin
  if not public.is_admin() and coalesce((
    select (value)::text = 'true' from public.app_settings
     where key = 'tournament_requests_enabled'
  ), false) is not true then
    raise exception 'Turnuva talebi şu an kapalı.';
  end if;
  if char_length(v_name) < 3 then
    raise exception 'Ad soyad gerekli.';
  end if;
  if v_raw !~ '^5\d{9}$' then
    raise exception 'Geçerli bir cep telefonu girin.';
  end if;
  if (select count(*) from public.tournament_requests
       where phone_raw10 = v_raw and created_at > now() - interval '1 day') >= 3
     or (select count(*) from public.tournament_requests
          where created_at > now() - interval '1 hour') >= 30 then
    raise exception 'Çok fazla talep gönderildi, biraz sonra tekrar deneyin.';
  end if;

  insert into public.tournament_requests (
    user_id, info_only, name, city, start_hint, kind, team_count, group_count,
    double_round, knockout, players_format, est_matches, extras,
    contact_name, phone, phone_raw10, organization, note, platform, app_version
  ) values (
    v_uid, coalesce(p_info_only, false),
    nullif(left(btrim(p_name), 120), ''),
    nullif(left(btrim(p_city), 80), ''),
    nullif(left(btrim(p_start_hint), 60), ''),
    nullif(left(btrim(p_kind), 30), ''),
    p_team_count, p_group_count,
    coalesce(p_double_round, false), coalesce(p_knockout, false),
    nullif(left(btrim(p_players_format), 10), ''),
    p_est_matches,
    coalesce((select array_agg(left(e, 30)) from unnest(p_extras) e
               where e is not null), '{}'),
    v_name, public.format_phone_raw10(v_raw), v_raw,
    nullif(left(btrim(p_organization), 120), ''),
    nullif(left(btrim(p_note), 2000), ''),
    left(p_platform, 40), left(p_app_version, 60)
  )
  returning id, code into v_id, v_code;

  v_kind := case p_kind
    when 'halisaha' then 'Halı saha' when 'okul' then 'Okul'
    when 'sirket' then 'Şirket' when 'dernek' then 'Dernek'
    when 'master' then 'Master' when 'diger' then 'Diğer' else null end;

  begin
    perform public.telegram_notify(
      array(select user_id from public.admins where user_id is not null),
      '🏆 Yeni turnuva talebi · ' || v_code
        || case when p_info_only then ' (bilgi almak istiyor)' else '' end
        || E'\n' || v_name || ' · ' || public.format_phone_raw10(v_raw)
        || coalesce(' · ' || nullif(btrim(p_organization), ''), '')
        || coalesce(E'\n' || nullif(btrim(p_name), ''), '')
        || coalesce(' · ' || nullif(btrim(p_city), ''), '')
        || E'\n' || concat_ws(' · ',
             v_kind,
             p_team_count || ' takım',
             case when coalesce(p_group_count, 1) > 1 then p_group_count || ' grup' else 'tek lig' end,
             case when p_double_round then 'çift devre' else 'tek devre' end,
             case when p_knockout then 'eleme var' end,
             nullif(btrim(p_players_format), ''),
             case when p_est_matches is not null then '~' || p_est_matches || ' maç' end)
        || coalesce(E'\nBaşlangıç: ' || nullif(btrim(p_start_hint), ''), '')
        || case when cardinality(p_extras) > 0
             then E'\nEk: ' || array_to_string(p_extras, ', ') else '' end
        || coalesce(E'\n\n' || left(nullif(btrim(p_note), ''), 1500), ''),
      null,
      null
    );
  exception when others then
    raise warning 'submit_tournament_request telegram: %', sqlerrm;
  end;
  return v_code;
end;
$function$;

revoke all on function public.submit_tournament_request(
  boolean, text, text, text, text, int, int, boolean, boolean, text, int,
  text[], text, text, text, text, text, text) from public;
grant execute on function public.submit_tournament_request(
  boolean, text, text, text, text, int, int, boolean, boolean, text, int,
  text[], text, text, text, text, text, text) to anon, authenticated;
