-- Sezon bazlı sağlık beyanı. Futbolcu bir sezon kadrosuna eklenince o sezon
-- için "oynamama engel bir sağlık durumum yok" beyanını ana sayfadaki karttan
-- onaylar. Beyan rapor değildir; yalnız beyan, tarih ve metin sürümü tutulur.
-- Kayıtlar değişmez (ispat): güncelleme/silme yok, hesap silinince user_id
-- boşalır, kayıt kalır.
--
-- Geçiş: 2026-11-13'ten önce kurulmuş sezonlarda, profilden verilmiş eski
-- (tek seferlik) sağlık beyanı geçerli sayılır; herkese birden kart çıkmaz.
--
-- Yeni özellik: app_settings.season_health_enabled kapalıyken yalnız admin
-- (UI + RPC). Bildirim yalnız anahtar herkese açıkken gider.

insert into public.app_settings (key, value)
values ('season_health_enabled', 'false'::jsonb)
on conflict (key) do nothing;

create or replace function public.season_health_on()
returns boolean
language sql
stable security definer
set search_path to ''
as $$
  select public.is_admin() or coalesce((
    select value = 'true'::jsonb from public.app_settings
     where key = 'season_health_enabled'), false)
$$;

create table if not exists public.player_season_declarations (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players(id) on delete cascade,
  season_id uuid not null references public.seasons(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  version text not null,
  user_agent text,
  created_at timestamptz not null default now()
);

create index if not exists player_season_declarations_ps_idx
  on public.player_season_declarations (player_id, season_id, created_at desc);

alter table public.player_season_declarations enable row level security;

drop policy if exists player_season_declarations_read
  on public.player_season_declarations;
create policy player_season_declarations_read
  on public.player_season_declarations
  for select to authenticated
  using (
    public.is_admin() or exists (
      select 1 from public.players p
       where p.id = player_id and p.auth_uid = auth.uid()
    )
  );

revoke insert, update, delete on public.player_season_declarations
  from anon, authenticated;

-- Oyuncunun o sezon için geçerli beyanı var mı (yeni kayıt ya da geçiş
-- dönemi sezonunda eski profil beyanı).
create or replace function public.season_health_declared(
  p_player_id uuid,
  p_season_id uuid
)
returns boolean
language sql
stable security definer
set search_path to ''
as $$
  select exists (
      select 1 from public.player_season_declarations d
       where d.player_id = p_player_id
         and d.season_id = p_season_id
         and d.version = public.current_consent_version()
    )
    or (
      (select s.created_at < timestamptz '2026-11-13 00:00:00+03'
         from public.seasons s where s.id = p_season_id)
      and coalesce((
        select c.granted
          from public.player_consents c
         where c.player_id = p_player_id
           and c.consent_type = 'health_declaration'
         order by c.created_at desc
         limit 1
      ), false)
    )
$$;

revoke all on function public.season_health_declared(uuid, uuid)
  from public, anon, authenticated;

-- Giriş yapan futbolcunun beyan bekleyen sezonları (aktif, silinmemiş,
-- bitmemiş, demo/pasif olmayan turnuva; kadroda aktif).
create or replace function public.my_pending_health_seasons()
returns table (
  season_id uuid,
  season_name text,
  league_name text,
  team_name text
)
language sql
stable security definer
set search_path to ''
as $$
  select distinct on (s.id)
         s.id, s.name::text, l.name::text, t.name::text
    from public.players p
    join public.season_team_players stp
      on stp.player_id = p.id and stp.is_active
    join public.seasons s on s.id = stp.season_id
    join public.leagues l on l.id = s.league_id
    left join public.teams t on t.id = stp.team_id
   where auth.uid() is not null
     and public.season_health_on()
     and p.auth_uid = auth.uid()
     and s.is_active
     and s.deleted_at is null
     and (s.end_date is null or s.end_date >= current_date)
     and not coalesce(l.is_demo, false)
     and coalesce(l.status, 'active') <> 'passive'
     and not public.season_health_declared(p.id, s.id)
   order by s.id, l.name
$$;

revoke all on function public.my_pending_health_seasons() from public, anon;
grant execute on function public.my_pending_health_seasons() to authenticated;

-- Beyanı verir: listedeki her sezon için, kullanıcının o sezon kadrosundaki
-- oyuncu kaydına bir satır yazar. Dönen değer yazılan satır sayısı.
create or replace function public.give_season_health_declarations(
  p_season_ids uuid[],
  p_version text,
  p_user_agent text default null
)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'Giriş yapmalısınız.';
  end if;
  if not public.season_health_on() then
    raise exception 'Bu özellik henüz açık değil.';
  end if;
  if p_version is distinct from public.current_consent_version() then
    raise exception 'Beyan metni güncellendi; sayfayı yenileyip tekrar deneyin.';
  end if;

  insert into public.player_season_declarations
    (player_id, season_id, user_id, version, user_agent)
  select distinct p.id, stp.season_id, auth.uid(), p_version,
         left(p_user_agent, 300)
    from public.players p
    join public.season_team_players stp
      on stp.player_id = p.id and stp.is_active
   where p.auth_uid = auth.uid()
     and stp.season_id = any (p_season_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.give_season_health_declarations(uuid[], text, text)
  from public, anon;
grant execute on function public.give_season_health_declarations(uuid[], text, text)
  to authenticated;

-- Kadroya eklenen hesaplı futbolcuya bir kez bildirim (yalnız özellik
-- herkese açıkken; admin aşamasında gitmez). Hata kadro eklemeyi bozmaz.
create or replace function public.season_health_push()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid;
  v_league text;
  v_demo boolean;
begin
  if not new.is_active then
    return new;
  end if;
  if not coalesce((
    select value = 'true'::jsonb from public.app_settings
     where key = 'season_health_enabled'), false) then
    return new;
  end if;
  begin
    select p.auth_uid into v_uid from public.players p where p.id = new.player_id;
    if v_uid is null then
      return new;
    end if;
    select l.name, coalesce(l.is_demo, false) into v_league, v_demo
      from public.seasons s join public.leagues l on l.id = s.league_id
     where s.id = new.season_id;
    if v_demo or public.season_health_declared(new.player_id, new.season_id) then
      return new;
    end if;
    perform public.push_send(
      array[v_uid],
      'Sağlık beyanı bekliyor',
      coalesce(v_league, 'Turnuva') || ' kadrosuna eklendin. Oynamadan önce '
        || 'ana sayfadan sağlık beyanını onayla.',
      '/',
      'health-' || new.season_id::text,
      true
    );
  exception when others then
    raise warning 'season_health_push: %', sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists season_health_push on public.season_team_players;
create trigger season_health_push
  after insert on public.season_team_players
  for each row execute function public.season_health_push();
