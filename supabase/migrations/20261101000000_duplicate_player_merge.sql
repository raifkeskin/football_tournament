-- Olası çift kayıt: futbolcu kendi kaydıyla YENİ profil açtığında, adı
-- tutan onaysız eski bir profil varsa adminlere Telegram'dan bildirilir;
-- "✅ Birleştir" eski profili korur, yeni profilin hesabını, telefonunu,
-- kimlik onayını ve kimlikteki ad/doğum tarihini ona taşır, yeni profili
-- siler. "❌ Ayrı kişi" yalnız öneriyi kapatır.

create table if not exists public.player_merge_suggestions (
  id uuid primary key default gen_random_uuid(),
  keep_id uuid not null,
  drop_id uuid not null,
  status text not null default 'pending'
    check (status in ('pending', 'merged', 'rejected')),
  decided_by uuid,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  unique (keep_id, drop_id)
);
alter table public.player_merge_suggestions enable row level security;
revoke all on public.player_merge_suggestions from anon, authenticated;

-- [p_drop] profilinin bütün kayıtlarını [p_keep]'e taşır ve p_drop'u siler.
-- Benzersizlik çakışmasında (ör. aynı sezonda iki kadro kaydı) p_drop'un
-- satırı silinir, p_keep'inki kalır.
create or replace function public.merge_players(p_keep uuid, p_drop uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  fk record;
  ix record;
  cond text;
  d public.players%rowtype;
  k public.players%rowtype;
  keep_txt text := p_keep::text;
  drop_txt text := p_drop::text;
begin
  if p_keep = p_drop then
    raise exception 'Aynı profil.';
  end if;
  select * into k from public.players where id = p_keep for update;
  select * into d from public.players where id = p_drop for update;
  if k.id is null or d.id is null then
    raise exception 'Profil bulunamadı.';
  end if;
  if k.auth_uid is not null and d.auth_uid is not null
     and k.auth_uid <> d.auth_uid then
    raise exception 'İki profilin de ayrı hesabı var; birleştirilemez.';
  end if;

  for fk in
    select c.conrelid::regclass as tbl, a.attname as col, c.conrelid as rel,
           a.attnum as num
      from pg_constraint c
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
     where c.contype = 'f' and c.confrelid = 'public.players'::regclass
  loop
    -- Bu kolonu içeren benzersiz indekslerde çakışacak p_drop satırları silinir.
    for ix in
      select i.indkey::int[] as keys
        from pg_index i
       where i.indrelid = fk.rel and i.indisunique
         and fk.num = any (i.indkey::int[]) and not (0 = any (i.indkey::int[]))
    loop
      select string_agg(format('t2.%I is not distinct from t.%I', at.attname, at.attname), ' and ')
        into cond
        from unnest(ix.keys) as kk(n)
        join pg_attribute at on at.attrelid = fk.rel and at.attnum = kk.n
       where kk.n <> fk.num;
      execute format(
        'delete from %s t where t.%I = $2 and exists (select 1 from %s t2 where t2.%I = $1%s)',
        fk.tbl, fk.col, fk.tbl, fk.col,
        case when cond is null then '' else ' and ' || cond end)
        using p_keep, p_drop;
    end loop;
    execute format('update %s set %I = $1 where %I = $2', fk.tbl, fk.col, fk.col)
      using p_keep, p_drop;
  end loop;

  update public.identity_events set player_id = p_keep where player_id = p_drop;
  update public.news set auto_data = replace(auto_data::text, drop_txt, keep_txt)::jsonb
   where auto_data::text like '%' || drop_txt || '%';
  update public.news set poll = replace(poll::text, drop_txt, keep_txt)::jsonb
   where poll::text like '%' || drop_txt || '%';
  update public.matches set shootout = replace(shootout::text, drop_txt, keep_txt)::jsonb
   where shootout::text like '%' || drop_txt || '%';
  update public.pending_actions set payload = replace(payload::text, drop_txt, keep_txt)::jsonb
   where payload::text like '%' || drop_txt || '%';

  -- Yeni profilin hesap ve kimlik bilgileri eskisine; önce yeni profil silinir
  -- (telefon / ad-soyad-doğum benzersizliği çakışmasın).
  delete from public.players where id = p_drop;
  update public.players
     set auth_uid = coalesce(d.auth_uid, k.auth_uid),
         phone = coalesce(d.phone, k.phone),
         photo_url = coalesce(k.photo_url, d.photo_url),
         main_position = coalesce(k.main_position, d.main_position),
         sub_position = coalesce(k.sub_position, d.sub_position),
         preferred_foot = coalesce(k.preferred_foot, d.preferred_foot),
         height = coalesce(k.height, d.height),
         weight = coalesce(k.weight, d.weight)
   where id = p_keep;
  -- Kimlikle onaylı yeni profilin adı ve doğum tarihi (çakışırsa eskisi kalır).
  if exists (select 1 from public.player_verifications v where v.player_id = p_keep) then
    begin
      update public.players
         set name = case when public._id_fold(name) = public._id_fold(d.name)
                         then name else d.name end,
             surname = case when public._id_fold(surname) = public._id_fold(d.surname)
                            then surname else d.surname end,
             birth_date = d.birth_date
       where id = p_keep;
    exception when unique_violation then
      null;
    end;
  end if;
end;
$$;
revoke all on function public.merge_players(uuid, uuid) from public, anon, authenticated;

-- Kendi kaydıyla açılan yeni profil (kadrosu yok) için adı tutan onaysız
-- profiller aranır; her biri için öneri ve Telegram bildirimi.
create or replace function public.identity_events_dup_check()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  n public.players%rowtype;
  c record;
  v_id uuid;
  v_teams text;
begin
  if new.action <> 'register' then
    return new;
  end if;
  select * into n from public.players where id = new.player_id;
  if n.id is null
     or exists (select 1 from public.season_team_players s where s.player_id = n.id)
     or exists (select 1 from public.match_rosters r where r.player_id = n.id) then
    return new;
  end if;
  for c in
    select p.*
      from public.players p
     where p.id <> n.id
       and not exists (select 1 from public.player_verifications v where v.player_id = p.id)
       and p.auth_uid is null
       and (' ' || public._id_fold(n.surname) || ' ' like '% ' || public._id_fold(p.surname) || ' %'
            or ' ' || public._id_fold(p.surname) || ' ' like '% ' || public._id_fold(n.surname) || ' %')
       and (' ' || public._id_fold(n.name) || ' ' like '% ' || public._id_fold(p.name) || ' %'
            or ' ' || public._id_fold(p.name) || ' ' like '% ' || public._id_fold(n.name) || ' %')
     limit 3
  loop
    insert into public.player_merge_suggestions (keep_id, drop_id)
    values (c.id, n.id)
    on conflict (keep_id, drop_id) do nothing
    returning id into v_id;
    if v_id is null then
      continue;
    end if;
    select string_agg(distinct t.name, ', ') into v_teams
      from public.season_team_players s join public.teams t on t.id = s.team_id
     where s.player_id = c.id;
    perform public.telegram_notify(
      array(select user_id from public.admins where user_id is not null),
      '👥 Olası çift kayıt'
        || E'\nYeni (kendi kaydı, onaylı): ' || n.name || ' ' || n.surname
        || ' · ' || coalesce(to_char(n.birth_date, 'DD.MM.YYYY'), '?')
        || E'\nMevcut: ' || c.name || ' ' || c.surname
        || ' · ' || coalesce(to_char(c.birth_date, 'DD.MM.YYYY'), '?')
        || case when v_teams is null then '' else ' · ' || v_teams end
        || E'\nBirleştirilirse mevcut profil kalır; hesap, telefon ve kimlik onayı ona taşınır.',
      jsonb_build_array(jsonb_build_array(
        jsonb_build_object('text', '✅ Birleştir', 'callback_data', 'dup_ok:' || v_id),
        jsonb_build_object('text', '❌ Ayrı kişi', 'callback_data', 'dup_no:' || v_id)
      ))
    );
  end loop;
  return new;
exception when others then
  raise warning 'identity_events_dup_check: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists identity_events_dup_check on public.identity_events;
create trigger identity_events_dup_check
  after insert on public.identity_events
  for each row execute function public.identity_events_dup_check();

CREATE OR REPLACE FUNCTION public.telegram_act(p_chat_id bigint, p_action text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
