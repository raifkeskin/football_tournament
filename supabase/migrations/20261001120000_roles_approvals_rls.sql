-- ============================================================================
-- Roller, onay sistemi ve satır bazlı güvenlik (RLS)
--
-- A1  league_owners      : turnuva sahipliği (sadece admin atar)
-- A2  team_managers      : sezon + takım bazında takım sorumlusu
-- A3  players.auth_uid   : oyuncu <-> kullanıcı eşleşmesi (telefonla, otomatik)
-- A4  yetki fonksiyonları: is_admin, owns_league, owns_season, owns_match,
--                          manages_team
-- A5  pending_actions    : takım sorumlusu talepleri
-- A6  review_pending_action(): onay/red, sunucuda ve tek adımda
-- A7  RLS                : okuma herkese açık, yazma role göre
-- A8  players_public     : hassas alanlar olmadan oyuncu görünümü
--
-- psql --single-transaction ile çalıştırılır; bir adım hata verirse hiçbiri
-- uygulanmaz.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0) admins tablosunu auth kullanıcısına bağla
-- ----------------------------------------------------------------------------
alter table public.admins
  add column if not exists user_id uuid unique
    references auth.users (id) on delete cascade;

update public.admins a
set user_id = u.id
from auth.users u
where a.user_id is null
  and a.email is not null
  and lower(u.email) = lower(a.email);

-- Düz metin şifreler: giriş Supabase Auth ile yapılıyor, bu alanlar
-- kullanılmıyor ve RLS açılana kadar herkese okunabilir durumdaydı.
update public.admins set password = null, backdoor_password = null;

-- ----------------------------------------------------------------------------
-- A1) Turnuva sahipliği
-- ----------------------------------------------------------------------------
create table if not exists public.league_owners (
  league_id  uuid not null references public.leagues (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (league_id, user_id)
);
create index if not exists league_owners_user_idx on public.league_owners (user_id);

-- ----------------------------------------------------------------------------
-- A2) Takım sorumluları (sezon + takım bazında)
-- ----------------------------------------------------------------------------
create table if not exists public.team_managers (
  season_id  uuid not null references public.seasons (id) on delete cascade,
  team_id    uuid not null references public.teams (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (season_id, team_id, user_id)
);
create index if not exists team_managers_user_idx on public.team_managers (user_id);

-- ----------------------------------------------------------------------------
-- A3) Oyuncu <-> kullanıcı eşleşmesi
--
-- Telefonu olmayan oyuncu (null ya da uygulamanın yazdığı "no_phone_..."
-- anahtarı) "eşleşme bekleyen" sayılır. Telefon eklendiğinde ve o numarayla
-- kayıtlı bir kullanıcı varsa oyuncu kullanıcıya bağlanır; kullanıcı sonradan
-- kayıt olursa da aynı eşleşme onun tarafından yapılır.
-- ----------------------------------------------------------------------------
alter table public.players
  add column if not exists auth_uid uuid unique
    references auth.users (id) on delete set null;

-- 10 haneli yerel biçim: 905xxxxxxxxx, +90 5xx..., 05xx... -> 5xxxxxxxxx
create or replace function public.phone_raw10(p text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p is null or p like 'no_phone_%' then null
    else nullif(right(regexp_replace(p, '\D', '', 'g'), 10), '')
  end
$$;

create or replace function public.players_link_auth()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.auth_uid is null and public.phone_raw10(new.phone) is not null then
    select u.id into new.auth_uid
    from auth.users u
    where public.phone_raw10(u.phone) = public.phone_raw10(new.phone)
      and not exists (select 1 from public.players p where p.auth_uid = u.id)
    limit 1;
  end if;
  return new;
end;
$$;

drop trigger if exists players_link_auth on public.players;
create trigger players_link_auth
  before insert or update of phone on public.players
  for each row execute function public.players_link_auth();

create or replace function public.auth_user_link_player()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if public.phone_raw10(new.phone) is not null then
    update public.players p
    set auth_uid = new.id
    where p.auth_uid is null
      and public.phone_raw10(p.phone) = public.phone_raw10(new.phone)
      and not exists (select 1 from public.players x where x.auth_uid = new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists auth_user_link_player on auth.users;
create trigger auth_user_link_player
  after insert or update of phone on auth.users
  for each row execute function public.auth_user_link_player();

-- ----------------------------------------------------------------------------
-- A4) Yetki fonksiyonları
--
-- security definer: kural içinde okunan tabloların kendi RLS'ine takılmaz.
-- ----------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.admins where user_id = auth.uid()
  )
$$;

create or replace function public.owns_league(p_league_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1 from public.league_owners
    where league_id = p_league_id and user_id = auth.uid()
  )
$$;

create or replace function public.owns_season(p_season_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1
    from public.seasons s
    join public.league_owners o on o.league_id = s.league_id
    where s.id = p_season_id and o.user_id = auth.uid()
  )
$$;

create or replace function public.owns_match(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1
    from public.matches m
    left join public.seasons s on s.id = m.season_id
    join public.league_owners o
      on o.league_id = coalesce(m.league_id, s.league_id)
    where m.id = p_match_id and o.user_id = auth.uid()
  )
$$;

create or replace function public.manages_team(p_season_id uuid, p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.team_managers
    where season_id = p_season_id
      and team_id = p_team_id
      and user_id = auth.uid()
  )
$$;

-- Oyuncunun kayıtlı olduğu sezonlardan birinin turnuva sahibi mi?
create or replace function public.owns_player(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1
    from public.season_team_players stp
    join public.seasons s on s.id = stp.season_id
    join public.league_owners o on o.league_id = s.league_id
    where stp.player_id = p_player_id and o.user_id = auth.uid()
  )
$$;

-- Oyuncu, kullanıcının sorumlu olduğu bir takımın kadrosunda mı?
create or replace function public.manages_player(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.season_team_players stp
    join public.team_managers tm
      on tm.season_id = stp.season_id and tm.team_id = stp.team_id
    where stp.player_id = p_player_id and tm.user_id = auth.uid()
  )
$$;

create or replace function public.is_any_league_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.league_owners where user_id = auth.uid())
$$;

-- ----------------------------------------------------------------------------
-- A5) Onay bekleyen işlemler
-- ----------------------------------------------------------------------------
create table if not exists public.pending_actions (
  id           uuid primary key default gen_random_uuid(),
  action_type  text not null
    check (action_type in ('roster_add', 'roster_remove', 'jersey_change')),
  status       text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  league_id    uuid not null references public.leagues (id) on delete cascade,
  season_id    uuid not null references public.seasons (id) on delete cascade,
  team_id      uuid not null references public.teams (id) on delete cascade,
  submitted_by uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  payload      jsonb not null default '{}'::jsonb,
  review_note  text,
  reviewed_by  uuid references auth.users (id) on delete set null,
  reviewed_at  timestamptz,
  created_at   timestamptz not null default now()
);
create index if not exists pending_actions_league_status_idx
  on public.pending_actions (league_id, status);
create index if not exists pending_actions_submitted_by_idx
  on public.pending_actions (submitted_by);

-- Talep açılırken sunucu tarafı alanları istemciye bırakılmaz.
create or replace function public.pending_actions_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.submitted_by := auth.uid();
  new.status := 'pending';
  new.review_note := null;
  new.reviewed_by := null;
  new.reviewed_at := null;
  new.created_at := now();
  select s.league_id into new.league_id
  from public.seasons s where s.id = new.season_id;
  if new.league_id is null then
    raise exception 'Sezon bulunamadı.';
  end if;
  if not exists (
    select 1 from public.season_teams st
    where st.season_id = new.season_id and st.team_id = new.team_id
  ) then
    raise exception 'Takım bu sezona kayıtlı değil.';
  end if;
  return new;
end;
$$;

drop trigger if exists pending_actions_before_insert on public.pending_actions;
create trigger pending_actions_before_insert
  before insert on public.pending_actions
  for each row execute function public.pending_actions_before_insert();

-- ----------------------------------------------------------------------------
-- A6) Onay / red
--
-- Sadece admin veya talebin turnuvasının sahibi çağırabilir. Onayda
-- değişiklik uygulanır ve talep aynı transaction içinde kapatılır.
--
-- payload biçimleri:
--   roster_add   : {"player_id": uuid, "jersey_number": int?}
--                  veya yeni oyuncu için
--                  {"player": {"name","surname","birth_date",
--                              "phone"?, "main_position"?, "preferred_foot"?},
--                   "jersey_number": int?}
--   roster_remove: {"player_id": uuid}
--   jersey_change: {"player_id": uuid, "jersey_number": int | null}
-- ----------------------------------------------------------------------------
create or replace function public.review_pending_action(
  p_action_id uuid,
  p_approve   boolean,
  p_note      text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  a         public.pending_actions;
  v_player  uuid;
  v_jersey  smallint;
  v_p       jsonb;
  v_current public.season_team_players;
begin
  select * into a from public.pending_actions
  where id = p_action_id
  for update;

  if not found then
    raise exception 'Talep bulunamadı.';
  end if;
  if not public.owns_league(a.league_id) then
    raise exception 'Bu talebi inceleme yetkiniz yok.';
  end if;
  if a.status <> 'pending' then
    raise exception 'Talep zaten sonuçlanmış (%).', a.status;
  end if;

  if p_approve then
    v_player := nullif(a.payload ->> 'player_id', '')::uuid;
    v_jersey := nullif(a.payload ->> 'jersey_number', '')::smallint;

    if a.action_type = 'roster_add' then
      if v_player is null then
        v_p := a.payload -> 'player';
        if v_p is null
           or coalesce(trim(v_p ->> 'name'), '') = ''
           or coalesce(trim(v_p ->> 'surname'), '') = ''
           or nullif(v_p ->> 'birth_date', '') is null then
          raise exception 'Yeni oyuncu için ad, soyad ve doğum tarihi gerekli.';
        end if;
        insert into public.players (
          name, surname, birth_date, phone, main_position, preferred_foot
        ) values (
          trim(v_p ->> 'name'),
          trim(v_p ->> 'surname'),
          (v_p ->> 'birth_date')::date,
          public.phone_raw10(v_p ->> 'phone'),
          nullif(trim(v_p ->> 'main_position'), ''),
          nullif(trim(v_p ->> 'preferred_foot'), '')
        )
        returning id into v_player;
      end if;

      select * into v_current from public.season_team_players
      where season_id = a.season_id and player_id = v_player;

      if found and v_current.is_active and v_current.team_id <> a.team_id then
        raise exception 'Oyuncu bu sezon başka bir takımda kayıtlı.';
      end if;

      if found then
        update public.season_team_players
        set team_id = a.team_id,
            is_active = true,
            jersey_number = coalesce(v_jersey, jersey_number)
        where id = v_current.id;
      else
        insert into public.season_team_players (
          season_id, team_id, player_id, jersey_number, is_active
        ) values (a.season_id, a.team_id, v_player, v_jersey, true);
      end if;

    elsif a.action_type = 'roster_remove' then
      update public.season_team_players
      set is_active = false
      where season_id = a.season_id
        and team_id = a.team_id
        and player_id = v_player;
      if not found then
        raise exception 'Oyuncu bu takımın kadrosunda değil.';
      end if;

    elsif a.action_type = 'jersey_change' then
      if v_jersey is not null and exists (
        select 1 from public.season_team_players
        where season_id = a.season_id and team_id = a.team_id
          and jersey_number = v_jersey and is_active
          and player_id <> v_player
      ) then
        raise exception 'Bu forma numarası takımda kullanılıyor.';
      end if;
      update public.season_team_players
      set jersey_number = v_jersey
      where season_id = a.season_id
        and team_id = a.team_id
        and player_id = v_player
        and is_active;
      if not found then
        raise exception 'Oyuncu bu takımın aktif kadrosunda değil.';
      end if;
    end if;
  end if;

  update public.pending_actions
  set status = case when p_approve then 'approved' else 'rejected' end,
      review_note = p_note,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      payload = case
        when p_approve and a.action_type = 'roster_add' and v_player is not null
          then payload || jsonb_build_object('player_id', v_player)
        else payload
      end
  where id = a.id;
end;
$$;

revoke all on function public.review_pending_action(uuid, boolean, text) from public, anon;
grant execute on function public.review_pending_action(uuid, boolean, text) to authenticated;

-- ----------------------------------------------------------------------------
-- A7) RLS
--
-- Önce eski (hiç devrede olmamış, "herkes her şeyi" yapabilen) kurallar
-- silinir, sonra her tablo için yeni kurallar tanımlanır.
-- ----------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
  loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

-- RLS, TRUNCATE'i kapsamaz; istemci rollerinden bu yetkiler tamamen alınır.
revoke truncate, references, trigger on all tables in schema public from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke truncate, references, trigger on tables from anon, authenticated;

-- Herkese açık okunan, yazması role bağlı tablolar -------------------------

-- leagues: sadece admin açar/siler; sahibi kendi turnuvasını düzenler.
alter table public.leagues enable row level security;
create policy leagues_read on public.leagues for select using (true);
create policy leagues_insert on public.leagues for insert to authenticated
  with check (public.is_admin());
create policy leagues_update on public.leagues for update to authenticated
  using (public.owns_league(id)) with check (public.owns_league(id));
create policy leagues_delete on public.leagues for delete to authenticated
  using (public.is_admin());

alter table public.seasons enable row level security;
create policy seasons_read on public.seasons for select using (true);
create policy seasons_write on public.seasons for all to authenticated
  using (public.owns_league(league_id)) with check (public.owns_league(league_id));

alter table public.groups enable row level security;
create policy groups_read on public.groups for select using (true);
create policy groups_write on public.groups for all to authenticated
  using (public.owns_season(season_id)) with check (public.owns_season(season_id));

alter table public.season_teams enable row level security;
create policy season_teams_read on public.season_teams for select using (true);
create policy season_teams_write on public.season_teams for all to authenticated
  using (public.owns_season(season_id)) with check (public.owns_season(season_id));

alter table public.season_registrations enable row level security;
create policy season_registrations_read on public.season_registrations for select using (true);
create policy season_registrations_write on public.season_registrations for all to authenticated
  using (public.owns_season(season_id)) with check (public.owns_season(season_id));

alter table public.season_team_players enable row level security;
create policy season_team_players_read on public.season_team_players for select using (true);
create policy season_team_players_write on public.season_team_players for all to authenticated
  using (public.owns_season(season_id)) with check (public.owns_season(season_id));

alter table public.matches enable row level security;
create policy matches_read on public.matches for select using (true);
create policy matches_write on public.matches for all to authenticated
  using (public.owns_league(coalesce(league_id,
          (select s.league_id from public.seasons s where s.id = season_id))))
  with check (public.owns_league(coalesce(league_id,
          (select s.league_id from public.seasons s where s.id = season_id))));

alter table public.match_events enable row level security;
create policy match_events_read on public.match_events for select using (true);
create policy match_events_write on public.match_events for all to authenticated
  using (public.owns_match(match_id)) with check (public.owns_match(match_id));

alter table public.match_media enable row level security;
create policy match_media_read on public.match_media for select using (true);
create policy match_media_write on public.match_media for all to authenticated
  using (public.owns_match(match_id)) with check (public.owns_match(match_id));

alter table public.match_rosters enable row level security;
create policy match_rosters_read on public.match_rosters for select using (true);
create policy match_rosters_write on public.match_rosters for all to authenticated
  using (public.owns_league(league_id)) with check (public.owns_league(league_id));

alter table public.player_penalties enable row level security;
create policy player_penalties_read on public.player_penalties for select using (true);
create policy player_penalties_write on public.player_penalties for all to authenticated
  using (public.owns_season(season_id)) with check (public.owns_season(season_id));

alter table public.player_season_stats enable row level security;
create policy player_season_stats_read on public.player_season_stats for select using (true);
create policy player_season_stats_write on public.player_season_stats for all to authenticated
  using (public.owns_season(season_id)) with check (public.owns_season(season_id));

-- Genel (turnuvadan bağımsız) tablolar: sadece admin yazar.
alter table public.teams enable row level security;
create policy teams_read on public.teams for select using (true);
create policy teams_write on public.teams for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

alter table public.pitches enable row level security;
create policy pitches_read on public.pitches for select using (true);
create policy pitches_write on public.pitches for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

alter table public.sponsors enable row level security;
create policy sponsors_read on public.sponsors for select using (true);
create policy sponsors_write on public.sponsors for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Rol tabloları -------------------------------------------------------------

alter table public.admins enable row level security;
create policy admins_read on public.admins for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy admins_write on public.admins for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

alter table public.league_owners enable row level security;
create policy league_owners_read on public.league_owners for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy league_owners_write on public.league_owners for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

alter table public.team_managers enable row level security;
create policy team_managers_read on public.team_managers for select to authenticated
  using (user_id = auth.uid() or public.owns_season(season_id));
create policy team_managers_write on public.team_managers for all to authenticated
  using (public.owns_season(season_id)) with check (public.owns_season(season_id));

-- Onay talepleri: sorumlu kendi takımı için açar ve kendi talebini görür;
-- sonuçlandırma sadece review_pending_action() ile yapılır.
alter table public.pending_actions enable row level security;
create policy pending_actions_read on public.pending_actions for select to authenticated
  using (submitted_by = auth.uid() or public.owns_league(league_id));
create policy pending_actions_insert on public.pending_actions for insert to authenticated
  with check (public.manages_team(season_id, team_id) or public.owns_season(season_id));
create policy pending_actions_cancel on public.pending_actions for update to authenticated
  using (submitted_by = auth.uid() and status = 'pending')
  with check (submitted_by = auth.uid() and status = 'cancelled');
-- İptalde sadece durum değişebilir; talebin içeriği değiştirilemez.
revoke update on public.pending_actions from anon, authenticated;
grant update (status) on public.pending_actions to authenticated;

-- Giriş akışının eski tablosu: login yeniden tasarlanana kadar sadece kendi
-- satırı ve admin.
alter table public.app_users enable row level security;
create policy app_users_own on public.app_users for select to authenticated
  using (auth_uid = auth.uid()::text or public.is_admin());
create policy app_users_admin on public.app_users for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Oyuncular -----------------------------------------------------------------
--
-- Yazma: admin; turnuva sahibi yeni oyuncu ekleyebilir ve kendi
-- turnuvalarındaki oyuncuları düzenler; silme sadece admin.
alter table public.players enable row level security;
create policy players_insert on public.players for insert to authenticated
  with check (public.is_admin() or public.is_any_league_owner());
create policy players_update on public.players for update to authenticated
  using (public.owns_player(id)) with check (public.owns_player(id));
create policy players_delete on public.players for delete to authenticated
  using (public.is_admin());

-- GEÇİCİ: uygulama oyuncuları henüz doğrudan bu tablodan okuyor. Uygulama
-- players_public görünümüne geçince bu kural players_read_private ile
-- değiştirilecek (A8'in ikinci yarısı).
create policy players_read_temp on public.players for select using (true);

-- ----------------------------------------------------------------------------
-- A8) Hassas alanlar olmadan oyuncu görünümü
--
-- Herkes: ad, soyad, fotoğraf, mevki, ayak, boy/kilo, doğum yılı.
-- Telefon, TC ve tam doğum tarihi bu görünümde yok; onlar players
-- tablosundan sadece yetkililere açılacak.
-- ----------------------------------------------------------------------------
create or replace view public.players_public
with (security_invoker = false) as
select
  p.id,
  p.name,
  p.surname,
  p.photo_url,
  p.main_position,
  p.sub_position,
  p.preferred_foot,
  p.height,
  p.weight,
  p.role,
  extract(year from p.birth_date)::int as birth_year,
  (public.phone_raw10(p.phone) is null) as pending_match,
  p.created_at,
  p.updated_at
from public.players p;

revoke all on public.players_public from public;
grant select on public.players_public to anon, authenticated;
