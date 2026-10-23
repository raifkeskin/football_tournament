-- Teklif sayfasından cevap: kişi son teklif sürümünü Kabul Et / Revize İste /
-- Reddet ile cevaplar. Cevap sürüme yazılır; talepte özet tutulur (liste
-- rozeti). Yeni revize gönderilene kadar cevap değiştirilebilir. IBAN artık
-- yalnız kabul edilen teklifte görünür.

alter table public.tournament_offers
  add column if not exists response text
    check (response in ('accepted', 'revision', 'rejected')),
  add column if not exists response_reason text,
  add column if not exists response_note text,
  add column if not exists responded_at timestamptz,
  add column if not exists terms_accepted_at timestamptz;

alter table public.tournament_requests
  add column if not exists offer_response text
    check (offer_response in ('accepted', 'revision', 'rejected')),
  add column if not exists offer_responded_at timestamptz;

-- Yeni sürüm kaydedilince talepteki cevap özeti sıfırlanır.
create or replace function public.tournament_offers_reset_response()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  update public.tournament_requests
     set offer_response = null, offer_responded_at = null
   where id = new.request_id;
  return new;
end;
$function$;

drop trigger if exists tournament_offers_reset_response on public.tournament_offers;
create trigger tournament_offers_reset_response
  after insert on public.tournament_offers
  for each row execute function public.tournament_offers_reset_response();

create or replace function public.tournament_offer_respond(
  p_token text,
  p_version int,
  p_response text,
  p_reason text,
  p_note text,
  p_terms boolean
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
  if p_response = 'accepted' and p_terms is not true then
    raise exception 'Kabul için koşulları onaylamanız gerekiyor.';
  end if;
  if p_response = 'revision' and v_note is null then
    raise exception 'Revize isteğinizi yazın.';
  end if;
  -- Aynı cevabı tekrar göndermek bildirim üretmez.
  if o.response is not distinct from p_response
     and o.response_note is not distinct from v_note
     and o.response_reason is not distinct from v_reason then
    return jsonb_build_object('response', o.response, 'responded_at', o.responded_at);
  end if;

  update public.tournament_offers
     set response = p_response,
         response_reason = v_reason,
         response_note = v_note,
         responded_at = now(),
         terms_accepted_at = case when p_response = 'accepted' then now() else null end
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

-- Teklif sayfası: cevap bilgisi eklendi; IBAN yalnız kabulde.
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

  if o.response = 'accepted' then
    select jsonb_object_agg(key, value) into v_set
      from public.app_private_settings
     where key in ('offer_iban', 'offer_account_name', 'offer_bank');
  end if;

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
    'payment', jsonb_build_object(
      'iban', nullif(v_set ->> 'offer_iban', ''),
      'account_name', nullif(v_set ->> 'offer_account_name', ''),
      'bank', nullif(v_set ->> 'offer_bank', '')
    )
  );
end;
$function$;

revoke all on function public.tournament_offers_reset_response() from public;
revoke all on function public.tournament_offer_respond(text, int, text, text, text, boolean) from public;
grant execute on function public.tournament_offer_respond(text, int, text, text, text, boolean) to anon, authenticated;
