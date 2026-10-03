-- Telegram'dan onay / red.
--
-- telegram_links: hangi Telegram sohbeti hangi kullanıcıya bağlı (admin,
-- ileride turnuva sorumluları). Bildirimler bu bağlantılara gider; butona
-- basıldığında karar, sohbetin bağlı olduğu kullanıcının yetkisiyle verilir.
--
-- Akış: tetikleyici → telegram_notify (Onayla / Reddet butonlu mesaj) →
-- butona basılınca Telegram, `telegram-webhook` Edge Function'ını çağırır →
-- fonksiyon telegram_act() ile kararı işler ve mesajı günceller.

create table if not exists public.telegram_links (
  chat_id bigint primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists telegram_links_user_idx on public.telegram_links (user_id);

-- İstemciden erişilmez; yalnızca security definer fonksiyonlar kullanır.
alter table public.telegram_links enable row level security;
revoke all on public.telegram_links from anon, authenticated;

-- Mevcut tek sohbet (admin) bağlantıya taşınır.
insert into public.telegram_links (chat_id, user_id)
select s.value::bigint, a.user_id
from public.app_private_settings s
cross join lateral (
  select user_id from public.admins
  where user_id is not null
  order by created_at
  limit 1
) a
where s.key = 'telegram_chat_id'
on conflict (chat_id) do nothing;

-- ---------------------------------------------------------------------------
-- telegram_notify(): verilen kullanıcıların bağlı sohbetlerine mesaj atar.
-- p_photo verilirse fotoğraflı mesaj (metin açıklama olur).
-- ---------------------------------------------------------------------------
create or replace function public.telegram_notify(
  p_user_ids uuid[],
  p_text text,
  p_buttons jsonb default null,
  p_photo text default null
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_token text;
  v_chat bigint;
  v_markup jsonb;
begin
  select value into v_token from public.app_private_settings where key = 'telegram_bot_token';
  if coalesce(v_token, '') = '' then
    return;
  end if;

  v_markup := jsonb_build_object(
    'inline_keyboard',
    coalesce(p_buttons, '[]'::jsonb) || jsonb_build_array(jsonb_build_array(
      jsonb_build_object('text', 'Siteyi Aç', 'url', 'https://masterfutbol.web.app')
    ))
  );

  for v_chat in
    select distinct chat_id from public.telegram_links where user_id = any (p_user_ids)
  loop
    if coalesce(p_photo, '') <> '' then
      perform net.http_post(
        url := 'https://api.telegram.org/bot' || v_token || '/sendPhoto',
        body := jsonb_build_object('chat_id', v_chat, 'photo', p_photo,
                                   'caption', p_text, 'reply_markup', v_markup),
        headers := '{"Content-Type": "application/json"}'::jsonb
      );
    else
      perform net.http_post(
        url := 'https://api.telegram.org/bot' || v_token || '/sendMessage',
        body := jsonb_build_object('chat_id', v_chat, 'text', p_text,
                                   'reply_markup', v_markup),
        headers := '{"Content-Type": "application/json"}'::jsonb
      );
    end if;
  end loop;
exception when others then
  raise warning 'telegram_notify: %', sqlerrm;
end;
$$;

revoke all on function public.telegram_notify(uuid[], text, jsonb, text) from public;

create or replace function public.format_phone_raw10(p text)
returns text
language sql
immutable
set search_path to ''
as $$
  select '0 (' || substr(p, 1, 3) || ') ' || substr(p, 4, 3) || ' '
    || substr(p, 7, 2) || ' ' || substr(p, 9, 2)
$$;

-- Yeni kayıt / şifre talebi → adminler.
create or replace function public.account_requests_notify()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_player text;
begin
  select nullif(trim(concat_ws(' ', p.name, p.surname)), '') into v_player
  from public.players p
  where public.phone_raw10(p.phone) = new.phone_raw10
  limit 1;

  perform public.telegram_notify(
    array(select user_id from public.admins where user_id is not null),
    case when new.kind = 'reset' then '🔑 Yeni şifre talebi' else '🔑 Yeni kayıt talebi' end
      || E'\n' || coalesce(v_player, new.full_name, 'Oyuncu kaydı yok')
      || E'\n' || public.format_phone_raw10(new.phone_raw10),
    jsonb_build_array(jsonb_build_array(
      jsonb_build_object('text', '✅ Onayla', 'callback_data', 'acc_ok:' || new.id),
      jsonb_build_object('text', '❌ Reddet', 'callback_data', 'acc_no:' || new.id)
    ))
  );
  return new;
end;
$$;

-- Profil değişikliği alan / değer yazımı (bildirim metni için).
create or replace function public.profile_change_lines(p_changes jsonb, p_previous jsonb)
returns text
language sql
immutable
set search_path to ''
as $$
  select string_agg(
    case k
      when 'height' then 'Boy: ' || coalesce(p_previous ->> k, '-') || ' → ' || (p_changes ->> k) || ' cm'
      when 'weight' then 'Kilo: ' || coalesce(p_previous ->> k, '-') || ' → ' || (p_changes ->> k) || ' kg'
      when 'main_position' then 'Mevki: ' || coalesce(p_previous ->> k, '-') || ' → ' || (p_changes ->> k)
      when 'sub_position' then 'Alt mevki: ' || coalesce(p_previous ->> k, '-') || ' → ' || (p_changes ->> k)
      when 'birth_date' then 'Doğum tarihi: '
        || coalesce(to_char((p_previous ->> k)::date, 'DD.MM.YYYY'), '-') || ' → '
        || to_char((p_changes ->> k)::date, 'DD.MM.YYYY')
      when 'photo_url' then 'Fotoğraf: yeni fotoğraf'
      else k end,
    E'\n' order by k)
  from jsonb_object_keys(p_changes) k
$$;

-- Yeni profil talebi → adminler + oyuncunun turnuva sorumluları.
create or replace function public.profile_change_requests_notify()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_name text;
  v_team text;
begin
  select nullif(trim(concat_ws(' ', p.name, p.surname)), '') into v_name
  from public.players p where p.id = new.player_id;

  select tm.name into v_team
  from public.season_team_players stp
  join public.teams tm on tm.id = stp.team_id
  join public.seasons s on s.id = stp.season_id
  where stp.player_id = new.player_id and stp.is_active
  order by s.start_date desc nulls last
  limit 1;

  perform public.telegram_notify(
    array(
      select user_id from public.admins where user_id is not null
      union
      select o.user_id
      from public.season_team_players stp
      join public.seasons s on s.id = stp.season_id
      join public.league_owners o on o.league_id = s.league_id
      where stp.player_id = new.player_id
    ),
    '👤 Yeni profil talebi' || E'\n' || coalesce(v_name, 'Futbolcu')
      || coalesce(' · ' || v_team, '') || E'\n\n'
      || public.profile_change_lines(new.changes, new.previous),
    jsonb_build_array(jsonb_build_array(
      jsonb_build_object('text', '✅ Onayla', 'callback_data', 'prof_ok:' || new.id),
      jsonb_build_object('text', '❌ Reddet', 'callback_data', 'prof_no:' || new.id)
    )),
    new.changes ->> 'photo_url'
  );
  return new;
end;
$$;

-- Eski tek-sohbetli bildirim fonksiyonu artık kullanılmıyor.
drop function if exists public.notify_admin(text, text, text);
delete from public.app_private_settings where key = 'telegram_chat_id';

-- ---------------------------------------------------------------------------
-- telegram_act(): Telegram butonundan gelen kararı işler. Yalnızca Edge
-- Function (service_role) çağırır. Karar, sohbete bağlı kullanıcının
-- yetkisiyle verilir (auth.uid() o kullanıcı olur; mevcut yetki kontrolleri
-- aynen çalışır).
-- Dönen: {"status": "approved"|"rejected", "phone", "password",
--         "delete_photo": "<storage linki>"}
-- ---------------------------------------------------------------------------
create or replace function public.telegram_act(p_chat_id bigint, p_action text, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_user uuid;
  v_status text;
  v_grant jsonb;
  r public.profile_change_requests%rowtype;
begin
  select user_id into v_user from public.telegram_links where chat_id = p_chat_id;
  if v_user is null then
    raise exception 'Bu Telegram hesabı bir kullanıcıya bağlı değil.';
  end if;
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_user, 'role', 'authenticated')::text,
    true
  );

  if p_action in ('acc_ok', 'acc_no') then
    if not public.is_admin() then
      raise exception 'Bu talebi inceleme yetkiniz yok.';
    end if;
    select status into v_status from public.account_requests where id = p_id for update;
    if v_status is null then
      raise exception 'Talep bulunamadı.';
    end if;
    if v_status <> 'pending' then
      raise exception 'Talep zaten sonuçlanmış.';
    end if;
    if p_action = 'acc_ok' then
      v_grant := public.approve_account_request(p_id);
      return v_grant || jsonb_build_object('status', 'approved');
    end if;
    update public.account_requests
    set status = 'rejected', reviewed_by = v_user, reviewed_at = now()
    where id = p_id;
    return jsonb_build_object('status', 'rejected');
  end if;

  if p_action in ('prof_ok', 'prof_no') then
    perform public.review_profile_change(p_id, p_action = 'prof_ok', null);
    select * into r from public.profile_change_requests where id = p_id;
    return jsonb_build_object(
      'status', r.status,
      'delete_photo', case
        when r.status = 'rejected' then r.changes ->> 'photo_url'
        when r.status = 'approved' and r.changes ? 'photo_url'
             and (r.previous ->> 'photo_url') like '%/media/profile_requests/%'
          then r.previous ->> 'photo_url'
      end
    );
  end if;

  raise exception 'Bilinmeyen işlem.';
end;
$$;

revoke all on function public.telegram_act(bigint, text, uuid) from public, anon, authenticated;
grant execute on function public.telegram_act(bigint, text, uuid) to service_role;
