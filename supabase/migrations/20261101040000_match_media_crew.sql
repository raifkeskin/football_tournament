-- Maçın medya ekibi: turnuvanın künye havuzunda her türden birden fazla
-- kişi olabilir (biri varsayılan). Maç için ayrı ekip seçilebilir; seçilmemiş
-- maçta varsayılanlar görünür. Admin, kurucu başkan ve maçın bölge sorumlusu
-- düzenler; bölge sorumlusu havuza yeni kişi de ekleyebilir.

alter table public.media_credits drop constraint if exists media_credits_league_id_kind_key;
alter table public.media_credits add column if not exists is_default boolean not null default false;
update public.media_credits set is_default = true where not is_default;
create unique index if not exists media_credits_one_default
  on public.media_credits (league_id, kind) where is_default;

drop policy if exists media_credits_insert on public.media_credits;
create policy media_credits_insert on public.media_credits for insert to authenticated
  with check (public.owns_league(league_id) or public.is_region_owner_of_league(league_id));

drop policy if exists media_credits_update on public.media_credits;
create policy media_credits_update on public.media_credits for update to authenticated
  using (public.owns_league(league_id) or public.is_region_owner_of_league(league_id))
  with check (public.owns_league(league_id) or public.is_region_owner_of_league(league_id));

alter table public.matches add column if not exists media_crew_custom boolean not null default false;

create table if not exists public.match_media_crew (
  match_id uuid not null references public.matches(id) on delete cascade,
  credit_id uuid not null references public.media_credits(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (match_id, credit_id)
);
alter table public.match_media_crew enable row level security;
drop policy if exists match_media_crew_read on public.match_media_crew;
create policy match_media_crew_read on public.match_media_crew for select
  using (public.can_view_match(match_id));
grant select on public.match_media_crew to anon, authenticated;

-- Maçın ekibini yazar. p_credit_ids null → turnuvanın varsayılanına döner;
-- boş dizi → bu maçta medya ekibi yok.
create or replace function public.set_match_media_crew(p_match_id uuid, p_credit_ids uuid[])
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_league uuid;
begin
  if not public.owns_match(p_match_id) then
    raise exception 'Bu maçın ekibini düzenleme yetkiniz yok.';
  end if;
  select coalesce(m.league_id, s.league_id) into v_league
    from public.matches m left join public.seasons s on s.id = m.season_id
   where m.id = p_match_id;
  delete from public.match_media_crew where match_id = p_match_id;
  if p_credit_ids is null then
    update public.matches set media_crew_custom = false where id = p_match_id;
    return;
  end if;
  insert into public.match_media_crew (match_id, credit_id)
  select p_match_id, c.id from public.media_credits c
   where c.id = any (p_credit_ids) and c.league_id = v_league;
  update public.matches set media_crew_custom = true where id = p_match_id;
end;
$$;
revoke all on function public.set_match_media_crew(uuid, uuid[]) from public, anon;
grant execute on function public.set_match_media_crew(uuid, uuid[]) to authenticated;
