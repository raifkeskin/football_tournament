-- Futbolcunun kendi profil bilgisi değişiklikleri (onaylı).
--
-- Futbolcu (players.auth_uid = kendisi) fotoğraf, boy, kilo, mevki ve doğum
-- tarihini değiştirmek ister → talep açılır. Oynadığı turnuvalardan
-- herhangi birinin sahibi (veya admin) onaylar / reddeder; ilk karar geçerli
-- olur ve talep diğer sahiplerin listesinden de düşer. Futbolcu bekleyen
-- talebini geri çekebilir. Talepler silinmez: eski/yeni değerler, kararı
-- veren ve zamanı geçmiş olarak kalır.
--
-- Bekleyen bir talepteki alanlar için ikinci talep açılamaz; diğer alanlar
-- ayrı talep olarak gönderilebilir.
--
-- Yeni fotoğraf `media/profile_requests/<auth.uid()>/` altına yüklenir;
-- onaylanınca players.photo_url bu dosyayı gösterir.

create table if not exists public.profile_change_requests (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players (id) on delete cascade,
  requested_by uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  -- Yeni değerler: photo_url, height, weight, main_position, sub_position,
  -- birth_date anahtarlarından gönderilenler.
  changes jsonb not null,
  -- Değiştirilen alanların eski değerleri (onayda o anki değerle yenilenir).
  previous jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'withdrawn')),
  review_note text,
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists profile_change_requests_player_idx
  on public.profile_change_requests (player_id, created_at desc);
create index if not exists profile_change_requests_pending_idx
  on public.profile_change_requests (status, created_at desc)
  where status = 'pending';

drop trigger if exists set_updated_at on public.profile_change_requests;
create trigger set_updated_at before update on public.profile_change_requests
  for each row execute function public.set_updated_at();

alter table public.profile_change_requests enable row level security;

-- Okuma: talebi açan futbolcu ve oyuncunun turnuva sahipleri / admin.
-- Yazma yalnızca aşağıdaki fonksiyonlarla.
drop policy if exists profile_change_requests_read on public.profile_change_requests;
create policy profile_change_requests_read on public.profile_change_requests
  for select to authenticated
  using (requested_by = auth.uid() or public.owns_player(player_id));

-- ---------------------------------------------------------------------------
-- Fotoğraf: futbolcu yalnızca kendi klasörüne yükleyebilir.
-- ---------------------------------------------------------------------------
drop policy if exists "media insert own profile request" on storage.objects;
create policy "media insert own profile request" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'media'
    and (storage.foldername(name))[1] = 'profile_requests'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- Yardımcı: alan değerini karşılaştırma ve kayıt için metne çevirir.
-- ---------------------------------------------------------------------------
create or replace function public.player_profile_values(p_player_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select jsonb_build_object(
    'photo_url', p.photo_url,
    'height', p.height,
    'weight', p.weight,
    'main_position', p.main_position,
    'sub_position', p.sub_position,
    'birth_date', p.birth_date
  )
  from public.players p
  where p.id = p_player_id
$$;

revoke all on function public.player_profile_values(uuid) from public;

-- ---------------------------------------------------------------------------
-- submit_profile_change(changes): giriş yapmış futbolcu için talep açar.
-- Değişmeyen alanlar atılır. Dönen: talep id'si.
-- ---------------------------------------------------------------------------
create or replace function public.submit_profile_change(p_changes jsonb)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_player uuid;
  v_current jsonb;
  v_clean jsonb := '{}'::jsonb;
  v_prev jsonb := '{}'::jsonb;
  v_key text;
  v_val jsonb;
  v_locked text[];
  v_photo_prefix text;
  v_id uuid;
  v_int int;
  v_date date;
begin
  if v_uid is null then
    raise exception 'Giriş yapmalısınız.';
  end if;
  if p_changes is null or jsonb_typeof(p_changes) <> 'object' then
    raise exception 'Geçersiz talep.';
  end if;

  select id into v_player from public.players where auth_uid = v_uid limit 1;
  if v_player is null then
    raise exception 'Hesabınıza bağlı oyuncu kaydı yok.';
  end if;

  v_current := public.player_profile_values(v_player);
  v_photo_prefix := '/storage/v1/object/public/media/profile_requests/'
    || v_uid::text || '/';

  for v_key, v_val in select * from jsonb_each(p_changes) loop
    if v_key not in ('photo_url', 'height', 'weight', 'main_position',
                     'sub_position', 'birth_date') then
      raise exception 'Bu alan değiştirilemez: %', v_key;
    end if;

    if jsonb_typeof(v_val) = 'null' then
      raise exception 'Alan boş bırakılamaz: %', v_key;
    end if;

    case v_key
      when 'photo_url' then
        if position(v_photo_prefix in (v_val #>> '{}')) = 0 then
          raise exception 'Fotoğraf geçersiz.';
        end if;
      when 'height' then
        v_int := (v_val #>> '{}')::int;
        if v_int < 120 or v_int > 230 then
          raise exception 'Boy 120-230 cm arasında olmalı.';
        end if;
        v_val := to_jsonb(v_int);
      when 'weight' then
        v_int := (v_val #>> '{}')::int;
        if v_int < 35 or v_int > 200 then
          raise exception 'Kilo 35-200 kg arasında olmalı.';
        end if;
        v_val := to_jsonb(v_int);
      when 'main_position' then
        if (v_val #>> '{}') not in ('Kaleci', 'Defans', 'Orta Saha', 'Forvet') then
          raise exception 'Mevki geçersiz.';
        end if;
      when 'sub_position' then
        if (v_val #>> '{}') not in ('Kaleci', 'Stoper', 'Bek', 'Defansif',
            'Merkez', 'Ofansif', 'Kanat', 'Santrfor', 'Kanat Forvet') then
          raise exception 'Alt mevki geçersiz.';
        end if;
      when 'birth_date' then
        v_date := (v_val #>> '{}')::date;
        if v_date < date '1940-01-01'
           or v_date > (current_date - interval '10 years')::date then
          raise exception 'Doğum tarihi geçersiz.';
        end if;
        v_val := to_jsonb(v_date);
    end case;

    -- Değişmeyen alan talebe girmez.
    if (v_current -> v_key) is distinct from v_val then
      v_clean := v_clean || jsonb_build_object(v_key, v_val);
      v_prev := v_prev || jsonb_build_object(v_key, v_current -> v_key);
    end if;
  end loop;

  if v_clean = '{}'::jsonb then
    raise exception 'Değişiklik yok.';
  end if;

  -- Onay bekleyen alanlar kilitli.
  select array_agg(distinct k) into v_locked
  from public.profile_change_requests r,
       lateral jsonb_object_keys(r.changes) k
  where r.player_id = v_player
    and r.status = 'pending'
    and v_clean ? k;
  if v_locked is not null then
    raise exception 'Onay bekleyen alanlar tekrar gönderilemez: %',
      array_to_string(v_locked, ', ');
  end if;

  insert into public.profile_change_requests (player_id, requested_by, changes, previous)
  values (v_player, v_uid, v_clean, v_prev)
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.submit_profile_change(jsonb) from public;
grant execute on function public.submit_profile_change(jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- withdraw_profile_change(id): futbolcu kendi bekleyen talebini geri çeker.
-- Dönen: talepteki yeni fotoğraf linki (istemci dosyayı siler) ya da null.
-- ---------------------------------------------------------------------------
create or replace function public.withdraw_profile_change(p_id uuid)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  r public.profile_change_requests%rowtype;
begin
  select * into r from public.profile_change_requests where id = p_id for update;
  if not found or r.requested_by is distinct from auth.uid() then
    raise exception 'Talep bulunamadı.';
  end if;
  if r.status <> 'pending' then
    raise exception 'Talep zaten sonuçlanmış.';
  end if;

  update public.profile_change_requests
  set status = 'withdrawn', reviewed_at = now()
  where id = r.id;

  return r.changes ->> 'photo_url';
end;
$$;

revoke all on function public.withdraw_profile_change(uuid) from public;
grant execute on function public.withdraw_profile_change(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- review_profile_change(id, approve, note): oyuncunun turnuva sahibi / admin.
-- İlk karar geçerli; sonuçlanmış talep tekrar karara bağlanamaz.
-- ---------------------------------------------------------------------------
create or replace function public.review_profile_change(
  p_id uuid,
  p_approve boolean,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  r public.profile_change_requests%rowtype;
  c jsonb;
begin
  select * into r from public.profile_change_requests where id = p_id for update;
  if not found then
    raise exception 'Talep bulunamadı.';
  end if;
  if not public.owns_player(r.player_id) then
    raise exception 'Bu talebi inceleme yetkiniz yok.';
  end if;
  if r.status <> 'pending' then
    raise exception 'Talep zaten sonuçlanmış.';
  end if;

  c := r.changes;
  if p_approve then
    update public.profile_change_requests
    set previous = (
      select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)
      from jsonb_each(public.player_profile_values(r.player_id)) as e(k, v)
      where c ? k
    )
    where id = r.id;

    update public.players
    set photo_url = case when c ? 'photo_url' then c ->> 'photo_url' else photo_url end,
        height = case when c ? 'height' then (c ->> 'height')::int else height end,
        weight = case when c ? 'weight' then (c ->> 'weight')::int else weight end,
        main_position = case when c ? 'main_position' then c ->> 'main_position' else main_position end,
        sub_position = case when c ? 'sub_position' then c ->> 'sub_position' else sub_position end,
        birth_date = case when c ? 'birth_date' then (c ->> 'birth_date')::date else birth_date end
    where id = r.player_id;
  end if;

  update public.profile_change_requests
  set status = case when p_approve then 'approved' else 'rejected' end,
      review_note = nullif(trim(coalesce(p_note, '')), ''),
      reviewed_by = auth.uid(),
      reviewed_at = now()
  where id = r.id;
end;
$$;

revoke all on function public.review_profile_change(uuid, boolean, text) from public;
grant execute on function public.review_profile_change(uuid, boolean, text) to authenticated;

-- Kararı veren admin mi (listede ad yoksa "Admin" yazılır).
create or replace function public.is_admin_user(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select exists (select 1 from public.admins where user_id = p_user)
$$;

revoke all on function public.is_admin_user(uuid) from public;

-- ---------------------------------------------------------------------------
-- list_profile_change_requests(): görülebilen talepler + oyuncu / takım /
-- kararı veren adı. p_only_pending true ise yalnızca bekleyenler.
-- p_player_id verilirse o oyuncunun talepleri (futbolcunun geçmişi).
-- ---------------------------------------------------------------------------
create or replace function public.list_profile_change_requests(
  p_only_pending boolean default true,
  p_player_id uuid default null
)
returns table (
  id uuid,
  player_id uuid,
  player_name text,
  team_name text,
  current_photo_url text,
  changes jsonb,
  previous jsonb,
  status text,
  review_note text,
  reviewer_name text,
  reviewed_at timestamptz,
  created_at timestamptz,
  is_mine boolean
)
language sql
stable
security definer
set search_path to ''
as $$
  select r.id,
         r.player_id,
         nullif(trim(concat_ws(' ', p.name, p.surname)), ''),
         t.team_name,
         p.photo_url,
         r.changes,
         r.previous,
         r.status,
         r.review_note,
         coalesce(
           (select nullif(trim(concat_ws(' ', rp.name, rp.surname)), '')
            from public.players rp where rp.auth_uid = r.reviewed_by limit 1),
           (select nullif(trim(au.name), '')
            from public.app_users au where au.auth_uid = r.reviewed_by::text limit 1),
           (select case when public.is_admin_user(r.reviewed_by) then 'Admin' end)
         ),
         r.reviewed_at,
         r.created_at,
         r.requested_by = auth.uid()
  from public.profile_change_requests r
  join public.players p on p.id = r.player_id
  left join lateral (
    select tm.name as team_name
    from public.season_team_players stp
    join public.teams tm on tm.id = stp.team_id
    join public.seasons s on s.id = stp.season_id
    where stp.player_id = r.player_id and stp.is_active
    order by s.start_date desc nulls last, stp.created_at desc
    limit 1
  ) t on true
  where (r.requested_by = auth.uid() or public.owns_player(r.player_id))
    and (not p_only_pending or r.status = 'pending')
    and (p_player_id is null or r.player_id = p_player_id)
  order by r.created_at desc
  limit 200
$$;

revoke all on function public.list_profile_change_requests(boolean, uuid) from public;
grant execute on function public.list_profile_change_requests(boolean, uuid) to authenticated;
