-- Admin, yırtık kart gibi durumlarda bir oyuncuya o sezon için kimlik istisnası verir:
-- oyuncu mavi tiksiz de esameye ve kadroya yazılabilir. Yalnız admin.
create table if not exists public.verified_id_exempt (
  player_id uuid not null references public.players(id) on delete cascade,
  season_id uuid not null references public.seasons(id) on delete cascade,
  reason text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (player_id, season_id)
);
alter table public.verified_id_exempt enable row level security;
-- Doğrudan erişim yok; yalnız aşağıdaki işlevler.

create or replace function public.admin_set_verified_exempt(p_player uuid, p_season uuid, p_exempt boolean, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Yetkiniz yok.'; end if;
  if p_exempt then
    insert into public.verified_id_exempt (player_id, season_id, reason)
    values (p_player, p_season, nullif(trim(coalesce(p_reason, '')), ''))
    on conflict (player_id, season_id) do update set reason = excluded.reason;
    insert into public.identity_events (player_id, action, user_id)
    values (p_player, 'exempt_on', auth.uid());
  else
    delete from public.verified_id_exempt where player_id = p_player and season_id = p_season;
    insert into public.identity_events (player_id, action, user_id)
    values (p_player, 'exempt_off', auth.uid());
  end if;
end $$;

-- Sezonda istisnası olan oyuncular (esame ekranı için).
create or replace function public.verified_exempt_list(p_season uuid)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(player_id), '{}') from public.verified_id_exempt where season_id = p_season
$$;

create or replace function public.identity_ok_for_season(p_player uuid, p_season uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(s.verified_id_mode, 'any') = 'any'
      or exists (select 1 from public.verified_id_exempt x
                  where x.player_id = p_player and x.season_id = p_season)
      or exists (select 1 from public.player_verifications v
                  where v.player_id = p_player
                    and (s.verified_id_mode = 'chip_ibraz' or v.method <> 'ibraz'))
    from public.seasons s where s.id = p_season
$$;

-- Esame tetikleyicisi de aynı yardımcıyı kullanır.
create or replace function public.match_rosters_require_verified()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare v_name text;
begin
  if new.player_id is null then return new; end if;
  if tg_op = 'UPDATE' and new.player_id is not distinct from old.player_id then
    return new;
  end if;
  if exists (select 1 from public.matches m where m.id = new.match_id and m.status = 'finished') then
    return new;
  end if;
  if public.identity_ok_for_season(new.player_id, new.season_id) then
    return new;
  end if;
  select p.name || ' ' || p.surname into v_name from public.players p where p.id = new.player_id;
  raise exception 'KIMLIK_ONAYSIZ: % kimliği onaylı değil; bu sezonda esameye eklenemez.',
    coalesce(v_name, 'Oyuncu');
end;
$function$;

revoke all on function public.admin_set_verified_exempt(uuid, uuid, boolean, text) from public, anon;
revoke all on function public.verified_exempt_list(uuid) from public, anon;
grant execute on function public.admin_set_verified_exempt(uuid, uuid, boolean, text) to authenticated;
grant execute on function public.verified_exempt_list(uuid) to authenticated;
