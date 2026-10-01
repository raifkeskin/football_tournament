-- ============================================================================
-- Tarih alanları + ekranı olup tablosu olmayan tablolar
--
-- B1  set_updated_at()  : her UPDATE'te updated_at = now()
-- B2  created_at        : eksik tablolara eklenir (mevcut kayıtlar = bugün)
-- B3  updated_at        : eksik tablolara eklenir, boş olanlar bugünle dolar
-- B4  news              : Haber Yönetimi
-- B5  awards            : Ödül / Kupa Yönetimi
-- B6  otp_codes         : OTP Takip, Şifremi Unuttum, Online Kayıt
-- B7  verify_otp_code() : kod kontrolü sunucuda (kodlar istemciye okunmaz)
-- B8  updated_at trigger'ları (tüm tablolar)
-- B9  realtime yayını (news, awards)
--
-- psql --single-transaction ile çalıştırılır; bir adım hata verirse hiçbiri
-- uygulanmaz.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- B1) updated_at trigger fonksiyonu
-- ----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- B2) created_at eksik olan tablolar
-- ----------------------------------------------------------------------------
alter table public.match_rosters
  add column if not exists created_at timestamptz not null default now();
alter table public.player_season_stats
  add column if not exists created_at timestamptz not null default now();
alter table public.season_registrations
  add column if not exists created_at timestamptz not null default now();
alter table public.season_team_players
  add column if not exists created_at timestamptz not null default now();

-- ----------------------------------------------------------------------------
-- B3) updated_at eksik olan tablolar
-- ----------------------------------------------------------------------------
alter table public.admins
  add column if not exists updated_at timestamptz not null default now();
alter table public.league_owners
  add column if not exists updated_at timestamptz not null default now();
alter table public.leagues
  add column if not exists updated_at timestamptz not null default now();
alter table public.match_events
  add column if not exists updated_at timestamptz not null default now();
alter table public.match_media
  add column if not exists updated_at timestamptz not null default now();
alter table public.match_rosters
  add column if not exists updated_at timestamptz not null default now();
alter table public.pending_actions
  add column if not exists updated_at timestamptz not null default now();
alter table public.player_season_stats
  add column if not exists updated_at timestamptz not null default now();
alter table public.season_registrations
  add column if not exists updated_at timestamptz not null default now();
alter table public.season_team_players
  add column if not exists updated_at timestamptz not null default now();
alter table public.season_teams
  add column if not exists updated_at timestamptz not null default now();
alter table public.team_managers
  add column if not exists updated_at timestamptz not null default now();

-- updated_at alanı olup varsayılanı olmayan tablolar: boşları bugünle doldur.
do $$
declare
  t text;
begin
  foreach t in array array[
    'groups', 'matches', 'pitches', 'player_penalties', 'players', 'seasons',
    'teams'
  ] loop
    execute format(
      'update public.%I set updated_at = now() where updated_at is null', t);
    execute format(
      'alter table public.%I alter column updated_at set default now()', t);
  end loop;
end;
$$;

-- ----------------------------------------------------------------------------
-- B4) news
-- ----------------------------------------------------------------------------
create table if not exists public.news (
  id           uuid primary key default gen_random_uuid(),
  league_id    uuid not null references public.leagues (id) on delete cascade,
  content      text not null check (length(trim(content)) > 0),
  is_published boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists news_league_created_idx
  on public.news (league_id, created_at desc);

alter table public.news enable row level security;
drop policy if exists news_read on public.news;
drop policy if exists news_write on public.news;
-- Yayındaki haberleri herkes, yayında olmayanları turnuva sahibi/admin görür.
create policy news_read on public.news for select
  using (is_published or public.owns_league(league_id));
create policy news_write on public.news for all to authenticated
  using (public.owns_league(league_id))
  with check (public.owns_league(league_id));

-- ----------------------------------------------------------------------------
-- B5) awards
-- ----------------------------------------------------------------------------
create table if not exists public.awards (
  id          uuid primary key default gen_random_uuid(),
  league_id   uuid not null references public.leagues (id) on delete cascade,
  name        text not null check (length(trim(name)) > 0),
  description text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists awards_league_idx on public.awards (league_id);

alter table public.awards enable row level security;
drop policy if exists awards_read on public.awards;
drop policy if exists awards_write on public.awards;
create policy awards_read on public.awards for select using (true);
create policy awards_write on public.awards for all to authenticated
  using (public.owns_league(league_id))
  with check (public.owns_league(league_id));

-- ----------------------------------------------------------------------------
-- B6) otp_codes
-- ----------------------------------------------------------------------------
create table if not exists public.otp_codes (
  id          uuid primary key default gen_random_uuid(),
  phone_raw10 text not null check (phone_raw10 ~ '^[0-9]{10}$'),
  code        text not null check (code ~ '^[0-9]{6}$'),
  status      text not null default 'pending'
                check (status in ('pending', 'verified', 'expired', 'locked')),
  attempts    integer not null default 0,
  expires_at  timestamptz not null,
  verified_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists otp_codes_phone_created_idx
  on public.otp_codes (phone_raw10, created_at desc);

alter table public.otp_codes enable row level security;
drop policy if exists otp_codes_request on public.otp_codes;
drop policy if exists otp_codes_admin on public.otp_codes;
-- Kod talebini herkes oluşturabilir (giriş yapmadan), ama okuyamaz.
create policy otp_codes_request on public.otp_codes for insert
  to anon, authenticated
  with check (
    status = 'pending'
    and attempts = 0
    and verified_at is null
    and expires_at <= now() + interval '30 minutes'
  );
-- OTP Takip ekranı: sadece admin okur/yönetir.
create policy otp_codes_admin on public.otp_codes for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ----------------------------------------------------------------------------
-- B7) verify_otp_code(): 'ok' | 'not_found' | 'expired' | 'invalid' | 'locked'
--     5 hatalı denemede kod kilitlenir. p_consume = false ise kod geçerli
--     kalır (şifre sıfırlamada sonraki adım aynı kodu kullanıyor).
-- ----------------------------------------------------------------------------
create or replace function public.verify_otp_code(
  p_phone   text,
  p_code    text,
  p_consume boolean default true
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.otp_codes%rowtype;
begin
  select * into r
  from public.otp_codes
  where phone_raw10 = trim(p_phone)
    and status = 'pending'
  order by created_at desc
  limit 1
  for update;

  if not found then
    return 'not_found';
  end if;

  if r.expires_at < now() then
    update public.otp_codes set status = 'expired' where id = r.id;
    return 'expired';
  end if;

  if r.code <> trim(p_code) then
    update public.otp_codes
    set attempts = attempts + 1,
        status = case when attempts + 1 >= 5 then 'locked' else status end
    where id = r.id;
    return case when r.attempts + 1 >= 5 then 'locked' else 'invalid' end;
  end if;

  if p_consume then
    update public.otp_codes
    set status = 'verified', verified_at = now()
    where id = r.id;
  end if;
  return 'ok';
end;
$$;

revoke all on function public.verify_otp_code(text, text, boolean) from public;
grant execute on function public.verify_otp_code(text, text, boolean)
  to anon, authenticated;

grant select, insert, update, delete on public.news, public.awards
  to anon, authenticated;
grant insert on public.otp_codes to anon;
grant select, insert, update, delete on public.otp_codes to authenticated;

-- ----------------------------------------------------------------------------
-- B8) updated_at trigger'ı: updated_at alanı olan tüm public tablolar
-- ----------------------------------------------------------------------------
do $$
declare
  t text;
begin
  for t in
    select c.table_name
    from information_schema.columns c
    join information_schema.tables tb
      on tb.table_schema = c.table_schema and tb.table_name = c.table_name
    where c.table_schema = 'public'
      and c.column_name = 'updated_at'
      and tb.table_type = 'BASE TABLE'
  loop
    execute format('drop trigger if exists set_updated_at on public.%I', t);
    execute format(
      'create trigger set_updated_at before update on public.%I '
      'for each row execute function public.set_updated_at()', t);
  end loop;
end;
$$;

-- ----------------------------------------------------------------------------
-- B9) Realtime: ekranlar değişiklik sinyalini dinliyor
-- ----------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and tablename = 'news') then
      alter publication supabase_realtime add table public.news;
    end if;
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and tablename = 'awards') then
      alter publication supabase_realtime add table public.awards;
    end if;
  end if;
end;
$$;
