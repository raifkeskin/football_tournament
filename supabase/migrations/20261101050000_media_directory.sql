-- Medya rehberi: yayıncı / fotoğrafçı bir kez kaydedilir (media_credits),
-- turnuvalar rehberden kişiyi kendi listesine bağlar
-- (league_media_credits; turnuva başına türünün varsayılanı). Aynı kişi
-- birden çok turnuvada görev alabilir, kaydı çoklanmaz.
-- media_credits.league_id: kaydı açan turnuva (eski uygulama sürümleri
-- turnuvanın künyesini bu kolondan okur).

create table if not exists public.league_media_credits (
  league_id uuid not null references public.leagues(id) on delete cascade,
  credit_id uuid not null references public.media_credits(id) on delete cascade,
  kind text not null check (kind in ('photo', 'broadcast')),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (league_id, credit_id)
);
create unique index if not exists league_media_credits_one_default
  on public.league_media_credits (league_id, kind) where is_default;

alter table public.league_media_credits enable row level security;
drop policy if exists lmc_read on public.league_media_credits;
create policy lmc_read on public.league_media_credits for select
  using (public.can_view_league(league_id));
drop policy if exists lmc_write on public.league_media_credits;
create policy lmc_write on public.league_media_credits for all to authenticated
  using (public.owns_league(league_id) or public.is_region_owner_of_league(league_id))
  with check (public.owns_league(league_id) or public.is_region_owner_of_league(league_id));
grant select on public.league_media_credits to anon, authenticated;
grant insert, update, delete on public.league_media_credits to authenticated;

-- Çiftleri birleştir: aynı tür + aynı Instagram (yoksa aynı ad) → en son
-- açılan kayıt kalır, diğerleri ona bağlanıp silinir.
create temp table _dup on commit drop as
select id,
       first_value(id) over (
         partition by kind, coalesce(nullif(lower(regexp_replace(instagram, '[?#].*$', '')), ''), lower(btrim(name)))
         order by created_at desc) as keep_id
  from public.media_credits;

insert into public.league_media_credits (league_id, credit_id, kind, is_default)
select distinct on (m.league_id, d.keep_id) m.league_id, d.keep_id, m.kind, m.is_default
  from public.media_credits m join _dup d on d.id = m.id
on conflict do nothing;

update public.match_media_crew c set credit_id = d.keep_id
  from _dup d where d.id = c.credit_id and d.id <> d.keep_id;
delete from public.media_credits m using _dup d where d.id = m.id and d.id <> d.keep_id;

alter table public.media_credits drop column if exists is_default;
drop index if exists public.media_credits_one_default;

-- Rehber: herkes okur (kartvizit zaten açık; iletişim izinle). Kişi ekleyen
-- turnuva yöneticisi; düzenleme, kişiyi listesine bağlamış yöneticiler.
drop policy if exists media_credits_read on public.media_credits;
create policy media_credits_read on public.media_credits for select using (true);

drop policy if exists media_credits_update on public.media_credits;
create policy media_credits_update on public.media_credits for update to authenticated
  using (public.is_admin() or exists (
    select 1 from public.league_media_credits l
     where l.credit_id = id
       and (public.owns_league(l.league_id) or public.is_region_owner_of_league(l.league_id))))
  with check (true);

drop policy if exists media_credits_delete on public.media_credits;
create policy media_credits_delete on public.media_credits for delete to authenticated
  using (public.is_admin());

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
  select p_match_id, l.credit_id from public.league_media_credits l
   where l.league_id = v_league and l.credit_id = any (p_credit_ids);
  update public.matches set media_crew_custom = true where id = p_match_id;
end;
$$;
