-- Esamede "Kadroda yok" → kimlik okutarak oyuncu ekleme.
-- Admin / kurucu başkan / bölge sorumlusu okutursa oyuncu doğrudan sezon
-- kadrosuna eklenir (esameye ekranda yerleşir). Takım sorumlusu okutursa
-- kadro talebi açılır; onaylanınca oyuncu sezon kadrosuna ve o maçın
-- esamesine yazılır. Profil yoksa kimlik çipindeki bilgilerle onaylı profil
-- açılır (elle ekleme anahtarından etkilenmez: kimlikle kayıt).

create or replace function public.identity_add_to_roster(
  p_match_id uuid,
  p_team_id uuid,
  p_first text,
  p_last text,
  p_birth date,
  p_tc text,
  p_player_id uuid default null,
  p_jersey smallint default null,
  p_display text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  m public.matches;
  v_staff boolean;
  v_hash text;
  v_player uuid := p_player_id;
  v_first text := initcap(lower(trim(p_first)));
  v_last text := initcap(lower(trim(p_last)));
  v_disp text[];
  v_cur public.season_team_players;
  v_name text;
begin
  perform public._identity_guard(p_tc);
  select * into m from public.matches where id = p_match_id;
  if not found then
    raise exception 'Maç bulunamadı.';
  end if;
  if p_team_id not in (m.home_team_id, m.away_team_id) then
    raise exception 'Takım bu maçta değil.';
  end if;
  v_staff := public.owns_season_team(m.season_id, p_team_id);
  if not v_staff and not public.attendance_is_manager(m.season_id, p_team_id) then
    raise exception 'Bu takıma oyuncu ekleme yetkiniz yok.';
  end if;
  v_hash := public._identity_hash(p_tc);

  if v_player is not null then
    -- Seçilen mevcut profil kimlikle onaylanır (kurallar identity_verify'da).
    perform public.identity_verify(v_player, p_first, p_last, p_birth, p_tc);
  else
    select player_id into v_player
      from public.player_verifications where tc_hash = v_hash;
    if v_player is null then
      -- Çip adı Türkçe harf taşımaz; kağıttaki yazım aynı harflerse o kullanılır.
      v_disp := regexp_split_to_array(trim(coalesce(p_display, '')), '\s+');
      if array_length(v_disp, 1) >= 2
         and public._id_fold(array_to_string(v_disp[1:array_length(v_disp, 1) - 1], ' '))
             = public._id_fold(trim(p_first))
         and public._id_fold(v_disp[array_length(v_disp, 1)]) = public._id_fold(trim(p_last)) then
        v_first := array_to_string(v_disp[1:array_length(v_disp, 1) - 1], ' ');
        v_last := v_disp[array_length(v_disp, 1)];
      end if;
      insert into public.players (name, surname, birth_date)
      values (v_first, v_last, p_birth)
      returning id into v_player;
      insert into public.player_verifications (player_id, tc_hash, verified_by)
      values (v_player, v_hash, auth.uid());
      insert into public.identity_events (player_id, action, user_id)
      values (v_player, 'create', auth.uid()), (v_player, 'verify', auth.uid());
    end if;
  end if;

  select trim(coalesce(name, '') || ' ' || coalesce(surname, '')) into v_name
    from public.players where id = v_player;

  select * into v_cur from public.season_team_players
   where season_id = m.season_id and player_id = v_player
   order by is_active desc limit 1;
  if found and v_cur.is_active and v_cur.team_id <> p_team_id then
    raise exception '% bu sezon başka bir takımda kayıtlı.', v_name;
  end if;
  if found and v_cur.is_active then
    return jsonb_build_object('status', 'added', 'player_id', v_player, 'name', v_name);
  end if;

  if v_staff then
    if found then
      update public.season_team_players
         set team_id = p_team_id, is_active = true,
             jersey_number = coalesce(p_jersey, jersey_number)
       where id = v_cur.id;
    else
      insert into public.season_team_players (season_id, team_id, player_id, jersey_number, is_active)
      values (m.season_id, p_team_id, v_player, p_jersey, true);
    end if;
    return jsonb_build_object('status', 'added', 'player_id', v_player, 'name', v_name);
  end if;

  insert into public.pending_actions (action_type, season_id, team_id, payload)
  values ('roster_add', m.season_id, p_team_id, jsonb_build_object(
    'player_id', v_player, 'player_name', v_name,
    'match_id', p_match_id, 'jersey_number', p_jersey, 'via', 'identity'))
  on conflict do nothing;
  return jsonb_build_object('status', 'pending', 'player_id', v_player, 'name', v_name);
end;
$function$;

revoke all on function public.identity_add_to_roster(uuid, uuid, text, text, date, text, uuid, smallint, text) from public, anon;
grant execute on function public.identity_add_to_roster(uuid, uuid, text, text, date, text, uuid, smallint, text) to authenticated;

CREATE OR REPLACE FUNCTION public.review_pending_action(p_action_id uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if not (public.owns_league(a.league_id)
          or public.owns_season_team(a.season_id, a.team_id)) then
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
        if not public.manual_player_create_allowed() then
          raise exception 'Yeni futbolcu ekleme kapalı. Futbolcu uygulamadan kayıt olsun; sonra listeden seçin.';
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

      -- Esameden (kimlikle) gelen talep: oyuncu o maçın esamesine de yazılır
      -- (maç başlamış ya da bitmiş olsa da; yedek olarak, listenin sonuna).
      if nullif(a.payload ->> 'match_id', '') is not null then
        insert into public.match_rosters (
          match_id, league_id, season_id, team_id, player_id, is_home,
          is_starting, jersey_number, list_order
        )
        select m.id, m.league_id, m.season_id, a.team_id, v_player,
               (m.home_team_id = a.team_id)::text, false,
               coalesce(v_jersey, (select stp.jersey_number
                                     from public.season_team_players stp
                                    where stp.season_id = a.season_id
                                      and stp.player_id = v_player
                                      and stp.is_active limit 1)),
               (select coalesce(max(mr.list_order) + 1, 0)
                  from public.match_rosters mr
                 where mr.match_id = m.id and mr.team_id = a.team_id)
          from public.matches m
         where m.id = (a.payload ->> 'match_id')::uuid
           and a.team_id in (m.home_team_id, m.away_team_id)
           and not exists (select 1 from public.match_rosters mr
                            where mr.match_id = m.id and mr.player_id = v_player);
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
$function$;
