-- Admin'e anlık bildirim (ntfy.sh): yeni kayıt / şifre talebi ve yeni
-- profil değişiklik talebi açıldığında telefona push gelir.
--
-- Kanal (topic) adı tahmin edilemez olmalı; git'e girmemesi için burada
-- değil, app_private_settings tablosunda tutulur:
--   insert into public.app_private_settings (key, value)
--   values ('ntfy_topic', '<kanal>') on conflict (key) do update set value = excluded.value;
-- Ayar yoksa bildirim gönderilmez. Bildirim hatası talebi asla engellemez.
--
-- ntfy.sh hesapsız gönderimde kotayı IP'ye göre sayar; Supabase'in çıkış
-- IP'si ortak olduğundan kota çabuk dolar. Bu yüzden ücretsiz bir ntfy
-- hesabının erişim anahtarı da saklanır ('ntfy_token', tk_...).

create extension if not exists pg_net;

create table if not exists public.app_private_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

-- İstemciden erişilemez (politika yok); yalnızca security definer
-- fonksiyonlar okur.
alter table public.app_private_settings enable row level security;
revoke all on public.app_private_settings from anon, authenticated;

create or replace function public.notify_admin(p_title text, p_message text, p_tags text default null)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_topic text;
  v_token text;
begin
  select value into v_topic from public.app_private_settings where key = 'ntfy_topic';
  select value into v_token from public.app_private_settings where key = 'ntfy_token';
  if coalesce(v_topic, '') = '' then
    return;
  end if;
  perform net.http_post(
    url := 'https://ntfy.sh',
    body := jsonb_strip_nulls(jsonb_build_object(
      'topic', v_topic,
      'title', p_title,
      'message', p_message,
      'tags', case when p_tags is null then null else jsonb_build_array(p_tags) end,
      'click', 'https://masterfutbol.web.app'
    )),
    headers := jsonb_strip_nulls(jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', case when coalesce(v_token, '') = '' then null
                            else 'Bearer ' || v_token end
    ))
  );
exception when others then
  -- Bildirim gönderilemedi diye talep kaydı bozulmasın.
  raise warning 'notify_admin: %', sqlerrm;
end;
$$;

revoke all on function public.notify_admin(text, text, text) from public;

-- Yeni kayıt / şifre talebi.
create or replace function public.account_requests_notify()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  perform public.notify_admin(
    case when new.kind = 'reset' then 'Yeni şifre talebi' else 'Yeni kayıt talebi' end,
    concat_ws(' · ',
      coalesce(new.full_name,
        (select nullif(trim(concat_ws(' ', p.name, p.surname)), '')
         from public.players p
         where public.phone_raw10(p.phone) = new.phone_raw10 limit 1)),
      '0 (' || substr(new.phone_raw10, 1, 3) || ') ' || substr(new.phone_raw10, 4, 3)
        || ' ' || substr(new.phone_raw10, 7, 2) || ' ' || substr(new.phone_raw10, 9, 2))
      || E'\nAdmin Paneli › Şifre Talepleri',
    'key'
  );
  return new;
end;
$$;

drop trigger if exists account_requests_notify on public.account_requests;
create trigger account_requests_notify after insert on public.account_requests
  for each row execute function public.account_requests_notify();

-- Yeni profil değişiklik talebi.
create or replace function public.profile_change_requests_notify()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_name text;
  v_fields text;
begin
  select nullif(trim(concat_ws(' ', p.name, p.surname)), '') into v_name
  from public.players p where p.id = new.player_id;

  select string_agg(distinct case k
      when 'photo_url' then 'Fotoğraf'
      when 'height' then 'Boy'
      when 'weight' then 'Kilo'
      when 'main_position' then 'Mevki'
      when 'sub_position' then 'Mevki'
      when 'birth_date' then 'Doğum tarihi'
      else k end, ', ')
  into v_fields
  from jsonb_object_keys(new.changes) k;

  perform public.notify_admin(
    'Yeni profil talebi',
    coalesce(v_name, 'Futbolcu') || ': ' || coalesce(v_fields, '-')
      || E'\nAdmin Paneli › Bekleyen Onaylar',
    'bust_in_silhouette'
  );
  return new;
end;
$$;

drop trigger if exists profile_change_requests_notify on public.profile_change_requests;
create trigger profile_change_requests_notify after insert on public.profile_change_requests
  for each row execute function public.profile_change_requests_notify();
