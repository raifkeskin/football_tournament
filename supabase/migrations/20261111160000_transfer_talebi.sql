-- Transfer talebi: payload.transfer=true ise onayda oyuncu eski takımdan yeni takıma taşınır.
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

      if found and v_current.is_active and v_current.team_id <> a.team_id
         and coalesce((a.payload ->> 'transfer')::boolean, false) is not true then
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
