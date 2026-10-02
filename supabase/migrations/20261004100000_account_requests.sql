-- Kayıt ve şifre sıfırlama: SMS yerine admin onayı + WhatsApp.
--
-- Akış:
--   1) Kullanıcı (giriş yapmadan) telefonunu yazar → request_account_password()
--      bekleyen bir talep açar. Numarada hesap varsa talep "reset" olur.
--   2) Admin "Şifre Talepleri" ekranında onaylar → approve_account_request()
--      geçici şifre üretir; hesap yoksa oluşturur, varsa şifresini değiştirir.
--      Şifre yalnızca bu çağrının cevabında döner, hiçbir tabloda saklanmaz.
--   3) Admin şifreyi kendi WhatsApp'ından gönderir; kullanıcı ilk girişte
--      yeni şifresini belirler (user_metadata.must_change_password).
--
-- Hesaplar "<telefon>@masterclass.com" e-postasıyla açılır (giriş ekranı bu
-- biçimi kullanıyor). auth.users.phone da doldurulur; auth_user_link_player
-- tetikleyicisi aynı telefonlu oyuncu kaydını hesaba bağlar.

create table if not exists public.account_requests (
  id uuid primary key default gen_random_uuid(),
  phone_raw10 text not null check (phone_raw10 ~ '^5[0-9]{9}$'),
  kind text not null check (kind in ('register', 'reset')),
  full_name text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  user_id uuid references auth.users (id) on delete set null,
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Numara başına tek bekleyen talep (tekrar isteyen aynı talebi günceller).
create unique index if not exists account_requests_one_pending_idx
  on public.account_requests (phone_raw10) where status = 'pending';
create index if not exists account_requests_status_created_idx
  on public.account_requests (status, created_at desc);

drop trigger if exists set_updated_at on public.account_requests;
create trigger set_updated_at before update on public.account_requests
  for each row execute function public.set_updated_at();

alter table public.account_requests enable row level security;

-- Yalnızca admin okur / reddeder. Talep açma ve onay fonksiyonlarla yapılır.
drop policy if exists account_requests_admin on public.account_requests;
create policy account_requests_admin on public.account_requests
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Admin listesi: talep + aynı telefonlu oyuncunun adı.
create or replace view public.account_requests_view
with (security_invoker = true) as
select r.id,
       r.phone_raw10,
       r.kind,
       r.full_name,
       r.status,
       r.created_at,
       r.reviewed_at,
       p.player_name
from public.account_requests r
left join lateral (
  select nullif(trim(concat_ws(' ', pl.name, pl.surname)), '') as player_name
  from public.players pl
  where public.phone_raw10(pl.phone) = r.phone_raw10
  limit 1
) p on true;

grant select on public.account_requests_view to authenticated;

-- ---------------------------------------------------------------------------
-- request_account_password(): giriş yapmadan çağrılır.
-- Dönen değerler:
--   'requested'        yeni hesap talebi alındı
--   'reset_requested'  numarada hesap var, yeni şifre talebi alındı
--   'already_pending'  bekleyen talep zaten var (bilgileri güncellendi)
--   'not_registered'   şifre sıfırlama istendi ama hesap yok
--   'invalid_phone'
-- ---------------------------------------------------------------------------
create or replace function public.request_account_password(
  p_phone text,
  p_full_name text default null,
  p_reset boolean default false
)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_raw text := public.phone_raw10(p_phone);
  v_name text := nullif(trim(coalesce(p_full_name, '')), '');
  v_has_account boolean;
  v_kind text;
begin
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    return 'invalid_phone';
  end if;

  select exists (
    select 1 from auth.users where email = v_raw || '@masterclass.com'
  ) into v_has_account;

  if p_reset and not v_has_account then
    return 'not_registered';
  end if;

  v_kind := case when v_has_account then 'reset' else 'register' end;

  update public.account_requests
  set kind = v_kind,
      full_name = coalesce(v_name, full_name)
  where phone_raw10 = v_raw and status = 'pending';
  if found then
    return 'already_pending';
  end if;

  insert into public.account_requests (phone_raw10, kind, full_name)
  values (v_raw, v_kind, left(v_name, 80));

  return case when v_has_account then 'reset_requested' else 'requested' end;
end;
$$;

revoke all on function public.request_account_password(text, text, boolean) from public;
grant execute on function public.request_account_password(text, text, boolean)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- approve_account_request(): yalnızca admin. Geçici şifre üretir, hesabı
-- açar ya da şifresini değiştirir. Onaylanmış talep tekrar onaylanırsa yeni
-- şifre üretilir ("tekrar gönder").
-- Dönen: {"phone": "5xxxxxxxxx", "password": "123456", "kind": "...",
--         "full_name": "..."}
-- ---------------------------------------------------------------------------
create or replace function public.approve_account_request(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  r public.account_requests%rowtype;
  v_email text;
  v_uid uuid;
  v_password text;
  v_phone text;
  v_name text;
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;

  select * into r from public.account_requests where id = p_id for update;
  if not found then
    raise exception 'Talep bulunamadı.';
  end if;
  if r.status = 'rejected' then
    raise exception 'Reddedilmiş talep onaylanamaz.';
  end if;

  v_email := r.phone_raw10 || '@masterclass.com';
  v_password := lpad(
    ((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint)
      % 1000000)::text,
    6, '0');

  select coalesce(
           r.full_name,
           (select nullif(trim(concat_ws(' ', pl.name, pl.surname)), '')
            from public.players pl
            where public.phone_raw10(pl.phone) = r.phone_raw10
            limit 1)
         )
  into v_name;

  select id into v_uid from auth.users where email = v_email;

  if v_uid is null then
    v_uid := gen_random_uuid();
    -- Telefon başka bir hesapta kayıtlıysa (users_phone_key) boş bırakılır.
    v_phone := '90' || r.phone_raw10;
    if exists (select 1 from auth.users where phone = v_phone) then
      v_phone := null;
    end if;

    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, phone, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, recovery_token,
      email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated',
      'authenticated', v_email,
      extensions.crypt(v_password, extensions.gen_salt('bf')),
      now(), v_phone,
      '{"provider": "email", "providers": ["email"]}'::jsonb,
      jsonb_strip_nulls(jsonb_build_object(
        'email_verified', true,
        'must_change_password', true,
        'name', v_name
      )),
      now(), now(), '', '', '', ''
    );

    insert into auth.identities (
      provider_id, user_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      v_uid::text, v_uid,
      jsonb_build_object(
        'sub', v_uid::text, 'email', v_email,
        'email_verified', false, 'phone_verified', false
      ),
      'email', now(), now(), now()
    );

    -- Oyuncu kaydı olmayanların adı profil ekranında görünsün.
    if v_name is not null then
      insert into public.app_users (phone, name, auth_uid, role)
      values (r.phone_raw10, v_name, v_uid::text, 'player')
      on conflict (phone) do update
        set auth_uid = excluded.auth_uid,
            name = coalesce(public.app_users.name, excluded.name);
    end if;
  else
    update auth.users
    set encrypted_password = extensions.crypt(v_password, extensions.gen_salt('bf')),
        raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
          || '{"must_change_password": true}'::jsonb,
        updated_at = now()
    where id = v_uid;

    -- Eski şifreyle açık oturumlar kapanır.
    delete from auth.sessions where user_id = v_uid;
  end if;

  update public.account_requests
  set status = 'approved',
      user_id = v_uid,
      reviewed_by = auth.uid(),
      reviewed_at = now()
  where id = r.id;

  return jsonb_build_object(
    'phone', r.phone_raw10,
    'password', v_password,
    'kind', r.kind,
    'full_name', v_name
  );
end;
$$;

revoke all on function public.approve_account_request(uuid) from public;
grant execute on function public.approve_account_request(uuid) to authenticated;
