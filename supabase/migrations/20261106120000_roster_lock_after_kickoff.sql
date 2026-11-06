-- Başlama düdüğünden sonra (kickoff_at dolu) esame kilitlenir:
--   * Takım sorumlusu ve diğerleri esameyi değiştiremez.
--   * Admin ve kurucu başkan yalnız yedeğe oyuncu ekleyebilir; ilk 11
--     değişmez, oyuncu çıkarılamaz. Forma no, kaptan ve saha sırası
--     (diziliş) güncellenebilir.
-- Sunucu işleri (auth.uid() yok) etkilenmez.
create or replace function public.match_rosters_lock_after_kickoff()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_match uuid := coalesce(new.match_id, old.match_id);
  v_started boolean;
  v_league uuid;
begin
  if auth.uid() is null then
    return coalesce(new, old);
  end if;
  select m.kickoff_at is not null, coalesce(m.league_id, s.league_id)
    into v_started, v_league
    from public.matches m
    left join public.seasons s on s.id = m.season_id
   where m.id = v_match;
  if not coalesce(v_started, false) then
    return coalesce(new, old);
  end if;
  if not (public.is_admin() or public.owns_league(v_league)) then
    raise exception 'Maç başladı; esame artık değiştirilemez.' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'Maç başladı; esameden oyuncu çıkarılamaz.' using errcode = '23514';
  end if;
  if tg_op = 'INSERT' and coalesce(new.is_starting, false) then
    raise exception 'Maç başladı; yalnız yedeğe oyuncu eklenebilir.' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' and (new.player_id is distinct from old.player_id
       or coalesce(new.is_starting, false) <> coalesce(old.is_starting, false)) then
    raise exception 'Maç başladı; ilk 11 değiştirilemez, yalnız yedeğe oyuncu eklenebilir.' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists match_rosters_lock_after_kickoff on public.match_rosters;
create trigger match_rosters_lock_after_kickoff
  before insert or update or delete on public.match_rosters
  for each row execute function public.match_rosters_lock_after_kickoff();
