-- Transfer dönemi desteği: aynı sezonda iki kayıt, kadro değişikliğine açık dönemde
-- (roster_add_open) takım değiştirmiş aynı kişi olabilir. Aday listesi bunu bildirir
-- ve birleştirmede hangi kaydın takımının kalacağı seçilebilir.
drop function if exists public.admin_player_merge(uuid, uuid, boolean);
drop function if exists public._player_merge(uuid, uuid, boolean);



-- Adayları listeler. Her satır bir çift; a ve b kayıtlarının özeti jsonb.
create or replace function public.admin_dup_candidates()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare out jsonb;
begin
  if not public.is_admin() then raise exception 'Yetkiniz yok.'; end if;
  with info as (
    select p.id, p.name, p.surname, p.birth_date, p.phone, (p.auth_uid is not null) as has_acc,
           public.norm_person_name(p.name) || ' ' || public.norm_person_name(p.surname) as k,
           coalesce((select jsonb_agg(jsonb_build_object(
                'season_id', s.season_id, 'team', t.name, 'league', l.name, 'season', se.name)
              order by l.name)
              from public.season_team_players s
              join public.teams t on t.id = s.team_id
              join public.seasons se on se.id = s.season_id
              join public.leagues l on l.id = se.league_id
              where s.player_id = p.id), '[]'::jsonb) as rosters,
           (select count(*) from public.match_events e where e.player_id = p.id) as ev,
           p.created_at
    from public.players p
  ), pairs as (
    select a.id as a_id, b.id as b_id,
           to_jsonb(a) - 'k' as a, to_jsonb(b) - 'k' as b,
           coalesce((select jsonb_agg(jsonb_build_object(
                'season_id', x->>'season_id', 'season', x->>'season', 'league', x->>'league',
                'a_team', x->>'team', 'b_team', y->>'team',
                'open', public.roster_add_open((x->>'season_id')::uuid)))
              from jsonb_array_elements(a.rosters) x, jsonb_array_elements(b.rosters) y
              where x->>'season_id' = y->>'season_id'), '[]'::jsonb) as shared
    from info a join info b on a.k = b.k and a.id < b.id
    where not exists (select 1 from public.player_dup_dismissed d where d.a = a.id and d.b = b.id)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'a', pairs.a, 'b', pairs.b, 'shared', pairs.shared,
      'same_season', jsonb_array_length(pairs.shared) > 0,
      'transfer_open', jsonb_array_length(pairs.shared) > 0
        and not exists (select 1 from jsonb_array_elements(pairs.shared) z where (z->>'open')::boolean is not true),
      'both_accounts', (pairs.a->>'has_acc')::boolean and (pairs.b->>'has_acc')::boolean)
    order by pairs.a->>'name', pairs.a->>'surname'), '[]'::jsonb)
  into out from pairs;
  return out;
end $$;

-- Asıl birleştirme (yetki denetimi sarmalayıcıda). p_keep kalır, p_drop silinir.
create or replace function public._player_merge(p_keep uuid, p_drop uuid, p_force boolean, p_team_from_drop boolean default false)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  kp public.players;
  dp public.players;
  rows_json jsonb := '[]'::jsonb;
  moved bigint;
begin
  if p_keep = p_drop then raise exception 'Aynı kayıt seçildi.'; end if;
  select * into kp from public.players where id = p_keep;
  select * into dp from public.players where id = p_drop;
  if kp.id is null or dp.id is null then raise exception 'Kayıt bulunamadı.'; end if;
  if kp.auth_uid is not null and dp.auth_uid is not null then
    raise exception 'İki kaydın da giriş hesabı var; otomatik birleştirilemez.';
  end if;
  -- Hesabı olan kayıt her zaman kalır.
  if dp.auth_uid is not null then
    raise exception 'Giriş hesabı olan kaydı silemezsiniz; onu tutan kaydı seçin.';
  end if;
  if exists (select 1 from public.season_team_players a
             join public.season_team_players b on a.season_id = b.season_id
             where a.player_id = p_keep and b.player_id = p_drop) and not p_force then
    raise exception 'AYNI_SEZON';
  end if;

  -- Transfer: takım kaydı silinecek kayıttan kalacaksa tutulan kaydın aynı sezondaki satırı atılır.
  if p_team_from_drop then
    delete from public.season_team_players k
    where k.player_id = p_keep
      and k.season_id in (select season_id from public.season_team_players where player_id = p_drop);
  end if;

  -- Yedek: silinecek kayıt ve bağlı kadro satırları.
  select coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb) into rows_json
  from public.season_team_players s where s.player_id = p_drop;
  insert into public.player_merge_backup(kept_id, dropped_id, dropped_player, dropped_rows)
  values (p_keep, p_drop, to_jsonb(dp), rows_json);

  -- Bağlı tüm tabloları taşı; benzersizlik çakışırsa silinecek kaydın satırı atılır.
  for r in
    select c.conrelid::regclass as tbl, a.attname as col
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
    where c.contype = 'f' and c.confrelid = 'public.players'::regclass
  loop
    begin
      execute format('update %s set %I = $1 where %I = $2', r.tbl, r.col, r.col) using p_keep, p_drop;
    exception when unique_violation then
      execute format('delete from %s where %I = $1', r.tbl, r.col) using p_drop;
    end;
  end loop;

  delete from public.players where id = p_drop;

  -- Tutulan kayıtta boş kalan alanlar silinen kayıttan tamamlanır.
  update public.players set
    phone = coalesce(kp.phone, dp.phone),
    photo_url = coalesce(kp.photo_url, dp.photo_url),
    preferred_foot = coalesce(kp.preferred_foot, dp.preferred_foot),
    main_position = coalesce(kp.main_position, dp.main_position),
    sub_position = coalesce(kp.sub_position, dp.sub_position),
    other_positions = coalesce(kp.other_positions, dp.other_positions),
    height = coalesce(kp.height, dp.height),
    weight = coalesce(kp.weight, dp.weight)
  where id = p_keep;

  delete from public.player_dup_dismissed where a in (p_keep, p_drop) or b in (p_keep, p_drop);
end $$;
revoke all on function public._player_merge(uuid, uuid, boolean, boolean) from public, anon, authenticated;

create or replace function public.admin_player_merge(p_keep uuid, p_drop uuid, p_force boolean default false, p_team_from_drop boolean default false)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Yetkiniz yok.'; end if;
  perform public._player_merge(p_keep, p_drop, p_force, p_team_from_drop);
end $$;

revoke all on function public.admin_dup_candidates() from public, anon;
revoke all on function public.admin_player_merge(uuid, uuid, boolean, boolean) from public, anon;
grant execute on function public.admin_dup_candidates() to authenticated;
grant execute on function public.admin_player_merge(uuid, uuid, boolean, boolean) to authenticated;
