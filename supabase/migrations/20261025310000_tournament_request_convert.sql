-- Turnuva talebi (3. aşama): ödemesi alınan talep tek tuşla turnuvaya
-- dönüşür. Lig + ilk sezon (+ gruplar) açılır, talep sahibi telefonuyla
-- kurucu başkan olur (hesabı yoksa davet bekler, kayıt olunca bağlanır).
-- Yalnız admin.

alter table public.tournament_requests
  add column if not exists league_id uuid references public.leagues (id) on delete set null,
  add column if not exists converted_at timestamptz;

create or replace function public.convert_tournament_request(
  p_request_id uuid,
  p_league_name text,
  p_short_name text,
  p_city text,
  p_start_date date,
  p_end_date date
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r public.tournament_requests;
  v_name text := left(btrim(coalesce(p_league_name, '')), 80);
  v_short text := nullif(left(btrim(coalesce(p_short_name, '')), 24), '');
  v_city text := nullif(left(btrim(coalesce(p_city, '')), 30), '');
  v_groups int;
  v_teams int;
  v_start int;
  v_league uuid;
  v_season uuid;
  v_owner text;
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;

  select * into r from public.tournament_requests
   where id = p_request_id for update;
  if not found then
    raise exception 'Talep bulunamadı.';
  end if;
  if r.league_id is not null then
    raise exception 'Bu talep zaten turnuvaya dönüştürüldü.';
  end if;
  if char_length(v_name) < 3 then
    raise exception 'Turnuva adı gerekli.';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Başlangıç ve bitiş tarihini kontrol edin.';
  end if;
  if coalesce(r.phone_raw10, '') !~ '^5[0-9]{9}$' then
    raise exception 'Talepte geçerli telefon yok.';
  end if;

  v_groups := greatest(coalesce(r.group_count, 1), 1);
  v_teams := coalesce(r.team_count, 0);
  -- Sahadaki oyuncu: "7+1" → 8, "11" → 11.
  v_start := case
    when r.players_format ~ '^\d+\+1$' then split_part(r.players_format, '+', 1)::int + 1
    when r.players_format ~ '^\d+$' then r.players_format::int
    else 11
  end;

  insert into public.leagues (name, short_name)
  values (v_name, v_short)
  returning id into v_league;

  insert into public.seasons (
    league_id, name, start_date, end_date, city, country,
    starting_player_count, sub_player_count, match_period_duration,
    number_of_player_changes, is_double_round, number_of_groups,
    teams_per_group, is_active, is_default
  ) values (
    v_league, extract(year from p_start_date)::int || ' Sezonu',
    p_start_date, p_end_date, v_city, 'Türkiye',
    v_start, 7, 25, 3, r.double_round, v_groups,
    case when v_teams > 0 then ceil(v_teams::numeric / v_groups)::int else 4 end,
    true, true
  )
  returning id into v_season;

  -- Tek grupta grup turnuva adıyla; çok grupta A, B, C… Grubu.
  if v_groups = 1 then
    insert into public.groups (season_id, name) values (v_season, v_name);
  else
    insert into public.groups (season_id, name)
    select v_season, chr(64 + g) || ' Grubu'
      from generate_series(1, least(v_groups, 26)) g;
  end if;

  v_owner := public.add_league_owner(v_league, r.contact_name, r.phone_raw10);

  update public.tournament_requests
     set league_id = v_league,
         converted_at = now(),
         status = 'won'
   where id = r.id;

  return jsonb_build_object(
    'league_id', v_league,
    'season_id', v_season,
    'owner', v_owner
  );
end;
$function$;

revoke all on function public.convert_tournament_request(uuid, text, text, text, date, date) from public, anon;
grant execute on function public.convert_tournament_request(uuid, text, text, text, date, date) to authenticated;
