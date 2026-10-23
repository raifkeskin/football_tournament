-- Teklif kabulünde üç ayrı onay (ön bilgilendirme + mesafeli satış,
-- kullanım koşulları + KVKK beyanı, aydınlatma metni). Onaylar belge
-- sürümü, zaman, IP ve tarayıcı bilgisiyle teklif sürümüne yazılır.
-- Satıcı bilgileri (unvan, adres, vergi no, e-posta) Teklif Ayarları'ndan
-- girilir ve sözleşme metinlerine dolar.

alter table public.tournament_offers
  add column if not exists consents jsonb;

insert into public.app_private_settings (key, value) values
  ('offer_seller_name', ''),
  ('offer_seller_address', ''),
  ('offer_seller_tax_no', ''),
  ('offer_seller_email', '')
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
                   'offer_account_name', 'offer_bank', 'offer_seller_name',
                   'offer_seller_address', 'offer_seller_tax_no',
                   'offer_seller_email')
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
                 'offer_account_name', 'offer_bank', 'offer_seller_name',
                 'offer_seller_address', 'offer_seller_tax_no',
                 'offer_seller_email') then
      raise exception 'Geçersiz ayar: %', k;
    end if;
    insert into public.app_private_settings (key, value)
    values (k, left(btrim(coalesce(p_values ->> k, '')), 300))
    on conflict (key) do update set value = excluded.value;
  end loop;
end;
$function$;

drop function if exists public.tournament_offer_respond(text, int, text, text, text, boolean);

create or replace function public.tournament_offer_respond(
  p_token text,
  p_version int,
  p_response text,
  p_reason text,
  p_note text,
  p_consents jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r public.tournament_requests;
  o public.tournament_offers;
  v_note text := nullif(left(btrim(coalesce(p_note, '')), 1000), '');
  v_reason text := nullif(left(btrim(coalesce(p_reason, '')), 60), '');
  v_label text;
  v_headers json;
  v_consents jsonb;
begin
  if coalesce(p_token, '') !~ '^[0-9a-f]{32}$' then
    raise exception 'Bağlantı geçersiz.';
  end if;
  if p_response not in ('accepted', 'revision', 'rejected') then
    raise exception 'Geçersiz cevap.';
  end if;
  select * into r from public.tournament_requests
   where offer_token = p_token for update;
  if not found then
    raise exception 'Teklif bulunamadı.';
  end if;
  if r.league_id is not null or r.status = 'cancelled' then
    raise exception 'Bu teklif kapandı; sorularınız için WhatsApp''tan yazın.';
  end if;
  select * into o from public.tournament_offers
   where request_id = r.id order by version desc limit 1;
  if not found or o.version <> p_version then
    raise exception 'Teklif güncellendi; sayfayı yenileyip son teklifi görün.';
  end if;
  -- Kabulde üç ayrı onay zorunlu: ön bilgilendirme + mesafeli satış,
  -- kullanım koşulları + KVKK beyanı, aydınlatma metni.
  if p_response = 'accepted' and not (
       coalesce((p_consents ->> 'pre_info')::boolean, false)
       and coalesce((p_consents ->> 'terms')::boolean, false)
       and coalesce((p_consents ->> 'privacy')::boolean, false)) then
    raise exception 'Kabul için üç onay kutusunu da işaretlemeniz gerekiyor.';
  end if;
  if p_response = 'accepted' then
    begin
      v_headers := current_setting('request.headers', true)::json;
    exception when others then
      v_headers := null;
    end;
    v_consents := jsonb_build_object(
      'pre_info', true, 'terms', true, 'privacy', true,
      'doc_version', left(coalesce(p_consents ->> 'doc_version', ''), 40),
      'at', now(),
      'ip', split_part(coalesce(v_headers ->> 'x-forwarded-for', ''), ',', 1),
      'user_agent', left(coalesce(v_headers ->> 'user-agent', ''), 300)
    );
  end if;
  if p_response = 'revision' and v_note is null then
    raise exception 'Revize isteğinizi yazın.';
  end if;
  -- Aynı cevabı tekrar göndermek bildirim üretmez.
  if p_response <> 'accepted'
     and o.response is not distinct from p_response
     and o.response_note is not distinct from v_note
     and o.response_reason is not distinct from v_reason then
    return jsonb_build_object('response', o.response, 'responded_at', o.responded_at);
  end if;

  update public.tournament_offers
     set response = p_response,
         response_reason = v_reason,
         response_note = v_note,
         responded_at = now(),
         terms_accepted_at = case when p_response = 'accepted' then now() else null end,
         consents = v_consents
   where id = o.id
  returning * into o;

  update public.tournament_requests
     set offer_response = p_response,
         offer_responded_at = now(),
         status = case p_response
                    when 'accepted' then 'won'
                    when 'rejected' then 'lost'
                    else 'offered'
                  end
   where id = r.id;

  v_label := case p_response
               when 'accepted' then '✅ Teklif kabul edildi'
               when 'revision' then '✏️ Revize istendi'
               else '❌ Teklif reddedildi'
             end;
  begin
    perform public.telegram_notify(
      array(select user_id from public.admins where user_id is not null),
      v_label || ' · ' || r.code
        || case when o.version > 1 then ' (revize ' || (o.version - 1) || ')' else '' end
        || E'\n' || r.contact_name || ' · ' || r.phone
        || coalesce(E'\nSebep: ' || v_reason, '')
        || coalesce(E'\nNot: ' || v_note, '')
    );
  exception when others then
    raise warning 'tournament_offer_respond telegram: %', sqlerrm;
  end;

  return jsonb_build_object('response', o.response, 'responded_at', o.responded_at);
end;
$function$;


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

  -- Satıcı bilgisi sözleşme metinleri için herkese; IBAN yalnız kabulde.
  select jsonb_object_agg(key, value) into v_set
    from public.app_private_settings
   where key in ('offer_seller_name', 'offer_seller_address',
                 'offer_seller_tax_no', 'offer_seller_email')
      or (o.response = 'accepted'
          and key in ('offer_iban', 'offer_account_name', 'offer_bank'));

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
    'closed', r.league_id is not null or r.status = 'cancelled',
    'offer', jsonb_build_object(
      'version', o.version,
      'list_price', o.list_price,
      'discount_pct', o.discount_pct,
      'per_match_price', o.per_match_price,
      'match_count', o.match_count,
      'team_count', o.team_count,
      'total', o.total,
      'note', o.note,
      'created_at', o.created_at,
      'response', o.response,
      'response_reason', o.response_reason,
      'response_note', o.response_note,
      'responded_at', o.responded_at
    ),
    'previous', v_prev,
    'seller', jsonb_build_object(
      'name', nullif(v_set ->> 'offer_seller_name', ''),
      'address', nullif(v_set ->> 'offer_seller_address', ''),
      'tax_no', nullif(v_set ->> 'offer_seller_tax_no', ''),
      'email', nullif(v_set ->> 'offer_seller_email', '')
    ),
    'payment', jsonb_build_object(
      'iban', nullif(v_set ->> 'offer_iban', ''),
      'account_name', nullif(v_set ->> 'offer_account_name', ''),
      'bank', nullif(v_set ->> 'offer_bank', '')
    )
  );
end;
$function$;


revoke all on function public.tournament_offer_respond(text, int, text, text, text, jsonb) from public;
grant execute on function public.tournament_offer_respond(text, int, text, text, text, jsonb) to anon, authenticated;
