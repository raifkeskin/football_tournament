-- Sezon kadro kuralı: yalnız çip onaylı / çip + ibraz onaylı / hepsi.
-- Eski boolean (require_verified_id) eski sürümler için eşzamanlı tutulur.
alter table public.seasons
  add column if not exists verified_id_mode text not null default 'any'
  check (verified_id_mode in ('any', 'chip', 'chip_ibraz'));

update public.seasons set verified_id_mode = 'chip'
 where require_verified_id and verified_id_mode = 'any';

create or replace function public.seasons_sync_verified_mode()
 returns trigger language plpgsql set search_path to ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.verified_id_mode = 'any' and new.require_verified_id then
      new.verified_id_mode := 'chip';
    end if;
  else
    if new.verified_id_mode is distinct from old.verified_id_mode then
      null;  -- yeni alan değişti: boolean ondan türetilir
    elsif new.require_verified_id is distinct from old.require_verified_id then
      new.verified_id_mode := case when new.require_verified_id then 'chip' else 'any' end;
    end if;
  end if;
  new.require_verified_id := new.verified_id_mode <> 'any';
  return new;
end;
$$;

drop trigger if exists seasons_sync_verified_mode on public.seasons;
create trigger seasons_sync_verified_mode
  before insert or update on public.seasons
  for each row execute function public.seasons_sync_verified_mode();

create or replace function public.match_rosters_require_verified()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
declare
  v_name text;
  v_mode text;
begin
  if new.player_id is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.player_id is not distinct from old.player_id then
    return new;
  end if;
  select s.verified_id_mode into v_mode from public.seasons s where s.id = new.season_id;
  if coalesce(v_mode, 'any') = 'any' then
    return new;
  end if;
  if exists (select 1 from public.matches m
              where m.id = new.match_id and m.status = 'finished') then
    return new;
  end if;
  if exists (select 1 from public.player_verifications v
              where v.player_id = new.player_id
                and (v_mode = 'chip_ibraz' or v.method <> 'ibraz')) then
    return new;
  end if;
  select p.name || ' ' || p.surname into v_name
    from public.players p where p.id = new.player_id;
  raise exception 'KIMLIK_ONAYSIZ: % kimliği onaylı değil; bu sezonda esameye eklenemez.',
    coalesce(v_name, 'Oyuncu');
end;
$function$;
