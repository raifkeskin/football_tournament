-- Yönetim Masası, Onaylar: bekleyen bütün talepler tek istekte. Kişinin
-- yetkisiyle çalışır (security invoker: RLS ve mevcut onay RPC'leri ne
-- gösteriyorsa o). Kararlar uygulamanın kullandığı RPC'lerle verilir:
-- review_pending_action, review_profile_change, review_player_penalty,
-- resolve_youtube_conflict; Instagram haberi news.is_published.

create or replace function public.desk_approvals()
returns jsonb
language sql
stable security invoker
set search_path to ''
as $$
  select jsonb_build_object(
    -- Kadroya ekleme / çıkarma / forma no (takım sorumlusundan).
    'roster', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id, 'type', a.action_type, 'created_at', a.created_at,
        'league_id', a.league_id, 'team', t.name, 'season', s.name,
        'player', coalesce(
          nullif(trim(coalesce(a.payload->'player'->>'name', '') || ' ' || coalesce(a.payload->'player'->>'surname', '')), ''),
          trim(coalesce(pp.name, '') || ' ' || coalesce(pp.surname, ''))),
        'new_player', a.payload ? 'player',
        'jersey', a.payload->>'jersey_number',
        'by', trim(coalesce(u.display_name, u.name, ''))
      ) order by a.created_at desc)
      from public.pending_actions a
      left join public.teams t on t.id = a.team_id
      left join public.seasons s on s.id = a.season_id
      left join public.players_public pp on pp.id = nullif(a.payload->>'player_id', '')::uuid
      left join public.app_users u on u.auth_uid = a.submitted_by::text
      where a.status = 'pending'
        and (public.owns_league(a.league_id) or public.owns_season_team(a.season_id, a.team_id))
    ), '[]'::jsonb),
    -- Oyuncunun profil değişikliği (fotoğraf, boy, kilo, mevki, doğum tarihi).
    'profile', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'player', r.player_name, 'team', r.team_name,
        'photo', r.current_photo_url, 'changes', r.changes, 'previous', r.previous,
        'created_at', r.created_at
      ) order by r.created_at desc)
      from public.list_profile_change_requests(true, null) r
      where not r.is_mine
    ), '[]'::jsonb),
    -- Karttan doğan cezalar (kırmızı / ikinci sarı).
    'penalties', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'kind', p.kind, 'match_count', p.match_count,
        'reason', p.penalty_reason, 'created_at', p.created_at,
        'league_id', s.league_id,
        'player', trim(coalesce(pl.name, '') || ' ' || coalesce(pl.surname, '')),
        'team', (select t.name from public.season_team_players stp
                   join public.teams t on t.id = stp.team_id
                  where stp.season_id = p.season_id and stp.player_id = p.player_id
                  order by stp.is_active desc limit 1),
        'match', (select ht.name || ' – ' || at.name ||
                         coalesce(' · ' || m.week || '. hafta', '')
                    from public.matches m
                    join public.teams ht on ht.id = m.home_team_id
                    join public.teams at on at.id = m.away_team_id
                   where m.id = p.match_id)
      ) order by p.created_at desc)
      from public.player_penalties p
      join public.seasons s on s.id = p.season_id
      left join public.players_public pl on pl.id = p.player_id
      where p.status = 'pending' and public.owns_season_player(p.season_id, p.player_id)
    ), '[]'::jsonb),
    -- Yayın linki uyuşmazlığı (elle girilen ↔ kanalda bulunan).
    'conflicts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id, 'league_id', c.league_id, 'created_at', c.created_at,
        'match', ht.name || ' – ' || at.name || coalesce(' · ' || m.week || '. hafta', ''),
        'manual_title', c.manual_title, 'manual_video', c.manual_video_id,
        'auto_title', c.auto_title, 'auto_video', c.auto_video_id
      ) order by c.created_at desc)
      from public.youtube_link_conflicts c
      join public.matches m on m.id = c.match_id
      join public.teams ht on ht.id = m.home_team_id
      join public.teams at on at.id = m.away_team_id
      where c.status = 'pending'
    ), '[]'::jsonb),
    -- Instagram'dan gelen, Haberler'e alınmayı bekleyen gönderiler.
    'instagram', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', n.id, 'content', n.content, 'image', n.image_url,
        'created_at', n.created_at, 'league_id', s.league_id, 'league', l.name
      ) order by n.created_at desc)
      from public.news n
      left join public.seasons s on s.id = n.season_id
      left join public.leagues l on l.id = s.league_id
      where n.auto_kind = 'instagram' and not n.is_published
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.desk_approvals() from public, anon;
grant execute on function public.desk_approvals() to authenticated;
