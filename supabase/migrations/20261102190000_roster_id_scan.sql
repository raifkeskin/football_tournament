-- Kadroda kimlik okut: takım ekranında onaysız oyuncunun satırından kimlik
-- okutulur; kart yalnız o profille karşılaştırılır.
--   ok       ad, soyad ve doğum tarihi tutuyor → hemen onaylı (mavi tik)
--   pending  soyad tutuyor, ad ya da tarih farklı → admin + kurucu başkana
--            Telegram onayı; onaylanınca profil karttaki bilgilerle düzelir
--   mismatch soyad farklı → red
--   dup      kimlik başka profile onaylı → birleştirme önerisi admine
-- Yeni özellik: yalnız admin; roster_id_scan_enabled açılınca yetkili herkes.

insert into public.app_settings (key, value)
values ('roster_id_scan_enabled', 'false'::jsonb)
on conflict (key) do nothing;

-- Uyuşmayan okumalar onay bekler. Yalnız fonksiyonlardan erişilir.
create table if not exists public.identity_verify_requests (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players (id) on delete cascade,
  season_id uuid not null references public.seasons (id) on delete cascade,
  team_id uuid not null references public.teams (id) on delete cascade,
  card_first text not null,
  card_last text not null,
  card_birth date not null,
  tc_hash text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'replaced')),
  requested_by uuid not null default auth.uid(),
  decided_by uuid,
  decided_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists identity_verify_requests_player_idx
  on public.identity_verify_requests (player_id) where status = 'pending';
alter table public.identity_verify_requests enable row level security;
revoke all on public.identity_verify_requests from public, anon, authenticated;

-- Ad kelimeleri: biri diğerinin içinde (ALİ HAKAN = Hakan), Türkçe harf
-- farkı sayılmaz.
create or replace function public._id_words_match(a text, b text)
returns boolean
language sql
stable
set search_path to ''
as $$
  with x as (
    select array_remove(regexp_split_to_array(public._id_fold(coalesce(a, '')), '\s+'), '') as wa,
           array_remove(regexp_split_to_array(public._id_fold(coalesce(b, '')), '\s+'), '') as wb
  )
  select coalesce(array_length(wa, 1), 0) > 0
     and coalesce(array_length(wb, 1), 0) > 0
     and (wa <@ wb or wb <@ wa)
    from x
$$;

create or replace function public.identity_verify_for(
  p_player_id uuid,
  p_season_id uuid,
  p_team_id uuid,
  p_first text,
  p_last text,
  p_birth date,
  p_tc text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_hash text;
  p public.players%rowtype;
  v_other record;
  v_card_name text := trim(coalesce(public.tr_name_fix(p_first), '') || ' '
                           || coalesce(public.tr_name_fix(p_last), ''));
  v_name_ok boolean;
  v_date_ok boolean;
  v_req uuid;
  v_sugg uuid;
  v_league uuid;
  v_team text;
begin
  perform public._identity_guard(p_tc);
  if not (public.is_admin()
          or coalesce((select value = 'true'::jsonb from public.app_settings
                        where key = 'roster_id_scan_enabled'), false)) then
    raise exception 'Kadroda kimlik okutma henüz kullanıma açık değil.';
  end if;
  if not (public.owns_season_team(p_season_id, p_team_id)
          or public.attendance_is_manager(p_season_id, p_team_id)) then
    raise exception 'Bu takımda kimlik okutma yetkiniz yok.';
  end if;
  if not exists (select 1 from public.season_team_players
                  where season_id = p_season_id and team_id = p_team_id
                    and player_id = p_player_id and is_active) then
    raise exception 'Oyuncu bu takımın kadrosunda değil.';
  end if;

  select * into p from public.players where id = p_player_id;
  v_hash := public._identity_hash(p_tc);
  select s.league_id into v_league from public.seasons s where s.id = p_season_id;
  select t.name into v_team from public.teams t where t.id = p_team_id;

  if exists (select 1 from public.player_verifications
              where player_id = p_player_id and tc_hash = v_hash) then
    return jsonb_build_object('result', 'ok', 'already', true,
                              'name', trim(p.name || ' ' || p.surname));
  end if;
  if exists (select 1 from public.player_verifications
              where player_id = p_player_id) then
    raise exception 'Bu profil başka bir kimlikle onaylı. Önce onayın kaldırılması gerekir.';
  end if;

  -- Kimlik başka profile onaylı: çift kayıt olabilir.
  select v.player_id, pl.name, pl.surname,
         (select string_agg(distinct t.name, ', ')
            from public.season_team_players s
            join public.teams t on t.id = s.team_id
           where s.player_id = v.player_id and s.is_active) as teams
    into v_other
    from public.player_verifications v
    join public.players pl on pl.id = v.player_id
   where v.tc_hash = v_hash;
  if found then
    insert into public.identity_events (player_id, action, user_id)
    values (p_player_id, 'target_dup', auth.uid());
    insert into public.player_merge_suggestions (keep_id, drop_id)
    values (v_other.player_id, p_player_id)
    on conflict (keep_id, drop_id) do nothing
    returning id into v_sugg;
    if v_sugg is not null then
      perform public.telegram_notify(
        array(select user_id from public.admins where user_id is not null),
        '👥 Olası çift kayıt (kadroda kimlik okutuldu)'
          || E'\nOkutulan: ' || p.name || ' ' || p.surname
          || ' · ' || coalesce(to_char(p.birth_date, 'DD.MM.YYYY'), '?')
          || coalesce(' · ' || v_team, '')
          || E'\nKimliğin onaylı olduğu: ' || v_other.name || ' ' || v_other.surname
          || coalesce(' · ' || v_other.teams, '')
          || E'\nBirleştirilirse onaylı profil kalır; okutulan profilin kadro ve maç kayıtları ona taşınır.',
        jsonb_build_array(jsonb_build_array(
          jsonb_build_object('text', '✅ Birleştir', 'callback_data', 'dup_ok:' || v_sugg),
          jsonb_build_object('text', '❌ Ayrı kişi', 'callback_data', 'dup_no:' || v_sugg)
        ))
      );
    end if;
    return jsonb_build_object(
      'result', 'dup',
      'other_name', trim(v_other.name || ' ' || v_other.surname),
      'other_teams', coalesce(v_other.teams, ''));
  end if;

  -- Soyad farklıysa kart bu kişiye ait değil.
  if not public._id_words_match(p.surname, p_last) then
    insert into public.identity_events (player_id, action, user_id)
    values (p_player_id, 'target_mismatch', auth.uid());
    return jsonb_build_object(
      'result', 'mismatch',
      'card_name', v_card_name,
      'card_year', extract(year from p_birth)::int);
  end if;

  v_name_ok := public._id_words_match(p.name, p_first);
  -- Profilde yalnız yıl varsa (01.01) ya da tarih yoksa aynı yıl yeterli.
  v_date_ok := p.birth_date = p_birth
    or p.birth_date is null
    or (extract(month from p.birth_date) = 1 and extract(day from p.birth_date) = 1
        and extract(year from p.birth_date) = extract(year from p_birth));

  if v_name_ok and v_date_ok then
    if p.birth_date is distinct from p_birth then
      update public.players set birth_date = p_birth where id = p_player_id;
      insert into public.identity_events (player_id, action, user_id)
      values (p_player_id, 'correct: birth ' || coalesce(p.birth_date::text, '-'), auth.uid());
    end if;
    insert into public.player_verifications (player_id, tc_hash, verified_by)
    values (p_player_id, v_hash, auth.uid());
    insert into public.identity_events (player_id, action, user_id)
    values (p_player_id, 'verify', auth.uid());
    update public.identity_verify_requests
       set status = 'replaced', tc_hash = null
     where player_id = p_player_id and status = 'pending';
    return jsonb_build_object('result', 'ok',
                              'name', trim(p.name || ' ' || p.surname));
  end if;

  -- Soyad tutuyor, ad ya da tarih farklı: onaya gider.
  update public.identity_verify_requests
     set status = 'replaced', tc_hash = null
   where player_id = p_player_id and status = 'pending';
  insert into public.identity_verify_requests (
    player_id, season_id, team_id, card_first, card_last, card_birth, tc_hash
  ) values (
    p_player_id, p_season_id, p_team_id,
    coalesce(public.tr_name_fix(p_first), ''),
    coalesce(public.tr_name_fix(p_last), ''),
    p_birth, v_hash
  ) returning id into v_req;
  insert into public.identity_events (player_id, action, user_id)
  values (p_player_id, 'target_pending', auth.uid());

  perform public.telegram_notify(
    array(
      select user_id from public.admins where user_id is not null
      union
      select o.user_id from public.league_owners o where o.league_id = v_league
    ),
    '🪪 Kimlik onayı bekliyor' || coalesce(E'\n' || v_team, '')
      || E'\nProfil: ' || p.name || ' ' || p.surname
      || ' · ' || coalesce(to_char(p.birth_date, 'DD.MM.YYYY'), '?')
      || E'\nKart: ' || v_card_name || ' · ' || to_char(p_birth, 'DD.MM.YYYY')
      || E'\nSoyad tutuyor, '
      || case when not v_name_ok and not v_date_ok then 'ad ve doğum tarihi'
              when not v_name_ok then 'ad' else 'doğum tarihi' end
      || ' farklı. Onaylanırsa profil karttaki bilgilerle düzelir ve mavi tik alır.',
    jsonb_build_array(jsonb_build_array(
      jsonb_build_object('text', '✅ Onayla', 'callback_data', 'idv_ok:' || v_req),
      jsonb_build_object('text', '❌ Reddet', 'callback_data', 'idv_no:' || v_req)
    ))
  );

  return jsonb_build_object(
    'result', 'pending',
    'name_ok', v_name_ok,
    'date_ok', v_date_ok,
    'profile_first', p.name,
    'profile_birth', p.birth_date,
    'card_first', coalesce(public.tr_name_fix(p_first), ''),
    'card_birth', p_birth);
end;
$$;

revoke all on function public.identity_verify_for(uuid, uuid, uuid, text, text, date, text)
  from public, anon;
grant execute on function public.identity_verify_for(uuid, uuid, uuid, text, text, date, text)
  to authenticated;

-- Onay talebini sonuçlandırır (Telegram düğmesinden).
create or replace function public.review_identity_request(p_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  r public.identity_verify_requests%rowtype;
  p public.players%rowtype;
  v_other text;
begin
  select * into r from public.identity_verify_requests where id = p_id for update;
  if not found then
    raise exception 'Talep bulunamadı.';
  end if;
  if not (public.is_admin()
          or public.owns_league((select s.league_id from public.seasons s
                                  where s.id = r.season_id))) then
    raise exception 'Bu talebi inceleme yetkiniz yok.';
  end if;
  if r.status <> 'pending' then
    raise exception 'Talep zaten sonuçlanmış.';
  end if;

  if p_approve then
    if r.tc_hash is null then
      raise exception 'Talep eksik. Kimliği yeniden okutun.';
    end if;
    select pl.name || ' ' || pl.surname into v_other
      from public.player_verifications v
      join public.players pl on pl.id = v.player_id
     where v.tc_hash = r.tc_hash and v.player_id <> r.player_id;
    if v_other is not null then
      raise exception 'Bu kimlik başka bir profile onaylı: %.', v_other;
    end if;
    if exists (select 1 from public.player_verifications
                where player_id = r.player_id and tc_hash <> r.tc_hash) then
      raise exception 'Profil başka bir kimlikle onaylanmış.';
    end if;

    select * into p from public.players where id = r.player_id;
    update public.players
       set birth_date = r.card_birth,
           name = case when public._id_words_match(name, r.card_first)
                       then name else r.card_first end,
           surname = case when public._id_fold(surname) = public._id_fold(r.card_last)
                          then surname else r.card_last end
     where id = r.player_id;
    insert into public.identity_events (player_id, action, user_id)
    values (r.player_id,
            'correct: ' || coalesce(p.name, '') || ' ' || coalesce(p.surname, '')
              || ' ' || coalesce(p.birth_date::text, '-'),
            auth.uid());
    insert into public.player_verifications (player_id, tc_hash, verified_by)
    values (r.player_id, r.tc_hash, r.requested_by)
    on conflict (player_id) do nothing;
    insert into public.identity_events (player_id, action, user_id)
    values (r.player_id, 'verify', auth.uid());
  end if;

  update public.identity_verify_requests
     set status = case when p_approve then 'approved' else 'rejected' end,
         decided_by = auth.uid(), decided_at = now(), tc_hash = null
   where id = r.id;

  perform public.push_send(
    array[r.requested_by],
    case when p_approve then 'Kimlik onaylandı' else 'Kimlik onayı reddedildi' end,
    (select trim(name || ' ' || surname) from public.players where id = r.player_id),
    '/',
    'roster-idv-' || r.id
  );
end;
$$;

revoke all on function public.review_identity_request(uuid, boolean) from public, anon, authenticated;

create or replace function public.telegram_act(p_chat_id bigint, p_action text, p_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_user uuid;
  v_status text;
  v_grant jsonb;
  r public.profile_change_requests%rowtype;
  s public.player_merge_suggestions%rowtype;
begin
  select user_id into v_user from public.telegram_links where chat_id = p_chat_id;
  if v_user is null then
    raise exception 'Bu Telegram hesabı bir kullanıcıya bağlı değil.';
  end if;
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_user, 'role', 'authenticated')::text,
    true
  );

  if p_action in ('acc_ok', 'acc_no') then
    if not public.is_admin() then
      raise exception 'Bu talebi inceleme yetkiniz yok.';
    end if;
    select status into v_status from public.account_requests where id = p_id for update;
    if v_status is null then
      raise exception 'Talep bulunamadı.';
    end if;
    if v_status <> 'pending' then
      raise exception 'Talep zaten sonuçlanmış.';
    end if;
    if p_action = 'acc_ok' then
      v_grant := public.approve_account_request(p_id);
      return v_grant || jsonb_build_object('status', 'approved');
    end if;
    update public.account_requests
    set status = 'rejected', reviewed_by = v_user, reviewed_at = now()
    where id = p_id;
    return jsonb_build_object('status', 'rejected');
  end if;

  if p_action in ('prof_ok', 'prof_no') then
    perform public.review_profile_change(p_id, p_action = 'prof_ok', null);
    select * into r from public.profile_change_requests where id = p_id;
    return jsonb_build_object(
      'status', r.status,
      'delete_photo', case
        when r.status = 'rejected' then r.changes ->> 'photo_url'
        when r.status = 'approved' and r.changes ? 'photo_url'
             and (r.previous ->> 'photo_url') like '%/media/profile_requests/%'
          then r.previous ->> 'photo_url'
      end
    );
  end if;

  -- Kadroda okutulan kimlik profille tam tutmadı: onayla / reddet.
  if p_action in ('idv_ok', 'idv_no') then
    perform public.review_identity_request(p_id, p_action = 'idv_ok');
    return jsonb_build_object(
      'status', case when p_action = 'idv_ok' then 'approved' else 'rejected' end);
  end if;

  -- Geçici kod iletildi: hatırlatma durur (mesaja "✅ Onaylandı" eklenir).
  if p_action = 'otp_ack' then
    if not public.is_admin() then
      raise exception 'Yetkiniz yok.';
    end if;
    update public.otp_telegram_reminders
       set done_at = coalesce(done_at, now()), code = null
     where otp_id = p_id;
    return jsonb_build_object('status', 'approved');
  end if;

  -- Olası çift kayıt: birleştir / ayrı kişi.
  if p_action in ('dup_ok', 'dup_no') then
    if not public.is_admin() then
      raise exception 'Yetkiniz yok.';
    end if;
    select * into s from public.player_merge_suggestions where id = p_id for update;
    if s.id is null then
      raise exception 'Öneri bulunamadı.';
    end if;
    if s.status <> 'pending' then
      raise exception 'Bu öneri zaten sonuçlanmış.';
    end if;
    if p_action = 'dup_ok' then
      perform public.merge_players(s.keep_id, s.drop_id);
    end if;
    update public.player_merge_suggestions
       set status = case when p_action = 'dup_ok' then 'merged' else 'rejected' end,
           decided_by = v_user, decided_at = now()
     where id = p_id;
    return jsonb_build_object(
      'status', case when p_action = 'dup_ok' then 'approved' else 'rejected' end);
  end if;

  raise exception 'Bilinmeyen işlem.';
end;
$function$;
