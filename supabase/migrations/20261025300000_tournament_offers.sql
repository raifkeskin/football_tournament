-- Turnuva teklifi (A yolu): admin talepten teklif hazırlar; her kayıt bir
-- sürümdür (ilk teklif + revizeler). Teklif uygulamada gösterilmez; kişiye
-- WhatsApp'tan ligmasasi.com/teklif?t=<anahtar> bağlantısı gider. Sayfa son
-- sürümü ve ödeme bilgisini (IBAN) gösterir.

alter table public.tournament_requests
  add column if not exists offer_token text unique,
  add column if not exists offer_viewed_at timestamptz;

create table if not exists public.tournament_offers (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.tournament_requests (id) on delete cascade,
  version int not null,
  list_price numeric(10, 2) not null,
  discount_pct numeric(5, 2) not null default 0,
  per_match_price numeric(10, 2) not null,
  match_count int not null check (match_count > 0),
  team_count int,
  total numeric(12, 2) not null,
  note text,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  viewed_at timestamptz,
  unique (request_id, version)
);

alter table public.tournament_offers enable row level security;
drop policy if exists tournament_offers_admin on public.tournament_offers;
create policy tournament_offers_admin on public.tournament_offers
  for select using (public.is_admin());
revoke all on public.tournament_offers from anon;
grant select on public.tournament_offers to authenticated;

-- Teklif ayarları (IBAN vb.) app_private_settings'te; yalnız admin okur/yazar.
insert into public.app_private_settings (key, value) values
  ('offer_list_price', '1000'),
  ('offer_first_discount_pct', '20'),
  ('offer_iban', ''),
  ('offer_account_name', ''),
  ('offer_bank', '')
on conflict (key) do nothing;

create or replace function public.offer_settings_get()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  return (
    select jsonb_object_agg(key, value) from public.app_private_settings
     where key in ('offer_list_price', 'offer_first_discount_pct', 'offer_iban',
                   'offer_account_name', 'offer_bank')
  );
end;
$function$;

create or replace function public.offer_settings_set(p_values jsonb)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  k text;
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  for k in select jsonb_object_keys(p_values) loop
    if k not in ('offer_list_price', 'offer_first_discount_pct', 'offer_iban',
                 'offer_account_name', 'offer_bank') then
      raise exception 'Geçersiz ayar: %', k;
    end if;
    insert into public.app_private_settings (key, value)
    values (k, left(btrim(coalesce(p_values ->> k, '')), 120))
    on conflict (key) do update set value = excluded.value;
  end loop;
end;
$function$;

-- Yeni sürüm kaydeder; bağlantı anahtarı ilk teklifte üretilir, revizelerde
-- aynı kalır (kişi aynı linkten güncel teklifi görür).
create or replace function public.tournament_offer_save(
  p_request_id uuid,
  p_list_price numeric,
  p_discount_pct numeric,
  p_match_count int,
  p_note text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r public.tournament_requests;
  v_version int;
  v_per numeric(10, 2);
  v_total numeric(12, 2);
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  select * into r from public.tournament_requests where id = p_request_id for update;
  if not found then
    raise exception 'Talep bulunamadı.';
  end if;
  if coalesce(p_list_price, 0) <= 0 or coalesce(p_match_count, 0) <= 0 then
    raise exception 'Fiyat ve maç sayısı gerekli.';
  end if;
  if coalesce(p_discount_pct, 0) < 0 or p_discount_pct >= 100 then
    raise exception 'İndirim 0–99 arasında olmalı.';
  end if;

  v_per := round(p_list_price * (1 - coalesce(p_discount_pct, 0) / 100), 2);
  v_total := v_per * p_match_count;
  select coalesce(max(version), 0) + 1 into v_version
    from public.tournament_offers where request_id = r.id;

  insert into public.tournament_offers (
    request_id, version, list_price, discount_pct, per_match_price,
    match_count, team_count, total, note, created_by
  ) values (
    r.id, v_version, p_list_price, coalesce(p_discount_pct, 0), v_per,
    p_match_count, r.team_count, v_total,
    nullif(left(btrim(p_note), 1500), ''), auth.uid()
  );

  update public.tournament_requests
     set offer_token = coalesce(offer_token,
           replace(gen_random_uuid()::text, '-', '')),
         status = case when status in ('new', 'contacted') then 'offered' else status end
   where id = r.id
  returning * into r;

  return jsonb_build_object(
    'version', v_version,
    'token', r.offer_token,
    'per_match_price', v_per,
    'total', v_total
  );
end;
$function$;

-- Herkese açık teklif sayfası (anahtarla). İlk görüntülemede adminlere
-- Telegram bildirimi.
create or replace function public.tournament_offer_view(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r public.tournament_requests;
  o public.tournament_offers;
  v_prev jsonb;
  v_set jsonb;
begin
  if coalesce(p_token, '') !~ '^[0-9a-f]{32}$' then
    return null;
  end if;
  select * into r from public.tournament_requests where offer_token = p_token;
  if not found then
    return null;
  end if;
  select * into o from public.tournament_offers
   where request_id = r.id order by version desc limit 1;
  if not found then
    return null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'version', x.version, 'per_match_price', x.per_match_price,
           'total', x.total, 'created_at', x.created_at)
           order by x.version desc), '[]')
    into v_prev
    from public.tournament_offers x
   where x.request_id = r.id and x.version < o.version;

  select jsonb_object_agg(key, value) into v_set
    from public.app_private_settings
   where key in ('offer_iban', 'offer_account_name', 'offer_bank');

  if o.viewed_at is null then
    update public.tournament_offers set viewed_at = now() where id = o.id;
    update public.tournament_requests set offer_viewed_at = now() where id = r.id;
    begin
      perform public.telegram_notify(
        array(select user_id from public.admins where user_id is not null),
        '👀 Teklif görüntülendi · ' || r.code
          || case when o.version > 1 then ' (revize ' || (o.version - 1) || ')' else '' end
          || E'\n' || r.contact_name || ' · ' || r.phone
      );
    exception when others then
      raise warning 'tournament_offer_view telegram: %', sqlerrm;
    end;
  end if;

  return jsonb_build_object(
    'code', r.code,
    'contact_name', r.contact_name,
    'organization', r.organization,
    'name', r.name,
    'city', r.city,
    'kind', r.kind,
    'team_count', r.team_count,
    'group_count', r.group_count,
    'double_round', r.double_round,
    'knockout', r.knockout,
    'players_format', r.players_format,
    'extras', to_jsonb(r.extras),
    'offer', jsonb_build_object(
      'version', o.version,
      'list_price', o.list_price,
      'discount_pct', o.discount_pct,
      'per_match_price', o.per_match_price,
      'match_count', o.match_count,
      'team_count', o.team_count,
      'total', o.total,
      'note', o.note,
      'created_at', o.created_at
    ),
    'previous', v_prev,
    'payment', jsonb_build_object(
      'iban', nullif(v_set ->> 'offer_iban', ''),
      'account_name', nullif(v_set ->> 'offer_account_name', ''),
      'bank', nullif(v_set ->> 'offer_bank', '')
    )
  );
end;
$function$;

revoke all on function public.offer_settings_get() from public;
revoke all on function public.offer_settings_set(jsonb) from public;
revoke all on function public.tournament_offer_save(uuid, numeric, numeric, int, text) from public;
revoke all on function public.tournament_offer_view(text) from public;
grant execute on function public.offer_settings_get() to authenticated;
grant execute on function public.offer_settings_set(jsonb) to authenticated;
grant execute on function public.tournament_offer_save(uuid, numeric, numeric, int, text) to authenticated;
grant execute on function public.tournament_offer_view(text) to anon, authenticated;
