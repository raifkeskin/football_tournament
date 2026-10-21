-- Kimlik doğrulama (onaylı profil): kimlik kartının çipi telefonla (NFC)
-- okunur; çipteki ad, soyad, doğum tarihi ve TC no ile sistemdeki futbolcu
-- eşleşirse profil onaylanır (mavi tik).
--
-- Gizlilik: TC numarası saklanmaz; yalnız gizli anahtarlı özeti (HMAC)
-- tutulur, o da kimseye okunmaz (aynı kimlik iki profile bağlanamasın diye).
-- Kimliğin görüntüsü ve çip fotoğrafı sunucuya hiç gelmez.
--
-- Sezon parametresi "Onaylı kimlik zorunlu" açıksa onaysız oyuncu esameye
-- eklenemez (tetikleyici; eski uygulama sürümleri ve kâğıttan esame dahil).

insert into public.app_private_settings (key, value) values
  ('identity_hash_secret', encode(extensions.gen_random_bytes(32), 'hex'))
on conflict (key) do nothing;

alter table public.seasons
  add column if not exists require_verified_id boolean not null default false;

create table if not exists public.player_verifications (
  player_id uuid primary key references public.players (id) on delete cascade,
  tc_hash text not null unique,
  method text not null default 'nfc',
  verified_at timestamptz not null default now(),
  verified_by uuid
);
alter table public.player_verifications enable row level security;
revoke all on public.player_verifications from anon, authenticated;
-- Onay bilgisi herkese açık; TC özeti ve onaylayan kimseye açık değil.
grant select (player_id, method, verified_at)
  on public.player_verifications to anon, authenticated;
drop policy if exists player_verifications_read on public.player_verifications;
create policy player_verifications_read on public.player_verifications
  for select using (true);

-- Onay/kaldırma/deneme kayıtları (denetim ve hız sınırı). Kimseye açık değil.
create table if not exists public.identity_events (
  id bigint generated always as identity primary key,
  player_id uuid,
  action text not null,           -- lookup | verify | unverify
  user_id uuid,
  created_at timestamptz not null default now()
);
alter table public.identity_events enable row level security;
revoke all on public.identity_events from anon, authenticated;
create index if not exists identity_events_user_time
  on public.identity_events (user_id, created_at desc);

-- Türkçe karakterleri katlayıp büyük harfe çevirir: çipteki "SIMSEK" ile
-- profildeki "Şimşek" eşleşsin.
create or replace function public.tr_fold(p text)
returns text
language sql
immutable
set search_path to ''
as $function$
  select btrim(regexp_replace(
    translate(upper(coalesce(p, '')), 'ŞĞÜÇÖİÂÎÛ', 'SGUCOIAIU'),
    '[^A-Z]+', ' ', 'g'))
$function$;

-- TC kimlik no biçim ve sağlama kontrolü.
create or replace function public.tc_valid(p text)
returns boolean
language plpgsql
immutable
set search_path to ''
as $function$
declare
  d int[];
  i int;
begin
  if p is null or p !~ '^[1-9][0-9]{10}$' then
    return false;
  end if;
  for i in 1..11 loop
    d[i] := substr(p, i, 1)::int;
  end loop;
  if ((d[1] + d[3] + d[5] + d[7] + d[9]) * 7
      - (d[2] + d[4] + d[6] + d[8])) % 10 <> d[10] then
    return false;
  end if;
  return (d[1] + d[2] + d[3] + d[4] + d[5] + d[6] + d[7] + d[8] + d[9]
          + d[10]) % 10 = d[11];
end;
$function$;

create or replace function public._identity_hash(p_tc text)
returns text
language sql
stable
security definer
set search_path to ''
as $function$
  select encode(extensions.hmac(p_tc, s.value, 'sha256'), 'hex')
    from public.app_private_settings s
   where s.key = 'identity_hash_secret'
$function$;
revoke all on function public._identity_hash(text) from public, anon, authenticated;

-- Ortak kontroller: giriş yapmış (misafir olmayan) kullanıcı, geçerli TC,
-- saatte en fazla 150 işlem.
create or replace function public._identity_guard(p_tc text)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if auth.uid() is null
     or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'Kimlik doğrulama için giriş yapın.';
  end if;
  if not public.tc_valid(p_tc) then
    raise exception 'Kimlik numarası okunamadı. Kartı tekrar okutun.';
  end if;
  if (select count(*) from public.identity_events
       where user_id = auth.uid()
         and created_at > now() - interval '1 hour') >= 150 then
    raise exception 'Çok fazla deneme. Bir süre sonra tekrar deneyin.';
  end if;
end;
$function$;
revoke all on function public._identity_guard(text) from public, anon, authenticated;

-- Çipten okunan bilgilere uyan profiller. match:
--   tc     bu kimlik zaten bu profile onaylı
--   exact  ad, soyad ve doğum tarihi tutuyor
--   near   doğum tarihi ve ad ya da soyad tutuyor (okutan kişi seçer)
-- verified: profil başka bir kimlikle onaylı.
create or replace function public.identity_candidates(
  p_first text, p_last text, p_birth date, p_tc text
)
returns table (
  player_id uuid, name text, surname text, birth_date date,
  photo_url text, teams text, match_kind text, verified boolean
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_hash text;
  v_first text := public.tr_fold(p_first);
  v_last text := public.tr_fold(p_last);
begin
  perform public._identity_guard(p_tc);
  insert into public.identity_events (action, user_id)
  values ('lookup', auth.uid());
  v_hash := public._identity_hash(p_tc);

  return query
  with c as (
    select p.*,
           case
             when v.tc_hash = v_hash then 'tc'
             when p.birth_date = p_birth
                  and public.tr_fold(p.surname) = v_last
                  and (public.tr_fold(p.name) = v_first
                       or v_first like public.tr_fold(p.name) || ' %'
                       or public.tr_fold(p.name) like v_first || ' %')
               then 'exact'
             else 'near'
           end as m,
           v.player_id is not null and v.tc_hash <> v_hash as other
      from public.players p
      left join public.player_verifications v on v.player_id = p.id
     where v.tc_hash = v_hash
        or (p.birth_date = p_birth
            and (public.tr_fold(p.surname) = v_last
                 or split_part(public.tr_fold(p.name), ' ', 1)
                    = split_part(v_first, ' ', 1)))
  )
  select c.id, c.name::text, c.surname, c.birth_date, c.photo_url,
         (select string_agg(distinct t.name, ', ')
            from public.season_team_players stp
            join public.teams t on t.id = stp.team_id
           where stp.player_id = c.id and stp.is_active),
         c.m, c.other
    from c
   order by case c.m when 'tc' then 0 when 'exact' then 1 else 2 end,
            c.surname, c.name
   limit 10;
end;
$function$;
revoke all on function public.identity_candidates(text, text, date, text) from public, anon;
grant execute on function public.identity_candidates(text, text, date, text) to authenticated;

-- Seçilen profili onaylar. Doğum tarihi aynı, ad ya da soyad tutmalı.
create or replace function public.identity_verify(
  p_player_id uuid, p_first text, p_last text, p_birth date, p_tc text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_hash text;
  p record;
  v_other record;
begin
  perform public._identity_guard(p_tc);
  v_hash := public._identity_hash(p_tc);

  select * into p from public.players where id = p_player_id;
  if not found then
    raise exception 'Profil bulunamadı.';
  end if;
  if p.birth_date is distinct from p_birth then
    raise exception 'Kimlikteki doğum tarihi profille eşleşmiyor.';
  end if;
  if public.tr_fold(p.surname) <> public.tr_fold(p_last)
     and split_part(public.tr_fold(p.name), ' ', 1)
         <> split_part(public.tr_fold(p_first), ' ', 1) then
    raise exception 'Kimlikteki ad soyad profille eşleşmiyor.';
  end if;

  select v.player_id, pl.name, pl.surname into v_other
    from public.player_verifications v
    join public.players pl on pl.id = v.player_id
   where v.tc_hash = v_hash and v.player_id <> p_player_id;
  if found then
    raise exception 'Bu kimlik başka bir profile onaylı: % %.',
      v_other.name, v_other.surname;
  end if;
  if exists (select 1 from public.player_verifications
              where player_id = p_player_id and tc_hash <> v_hash) then
    raise exception 'Bu profil başka bir kimlikle onaylı. Önce onayın kaldırılması gerekir.';
  end if;

  insert into public.player_verifications (player_id, tc_hash, verified_by)
  values (p_player_id, v_hash, auth.uid())
  on conflict (player_id) do nothing;
  insert into public.identity_events (player_id, action, user_id)
  values (p_player_id, 'verify', auth.uid());
end;
$function$;
revoke all on function public.identity_verify(uuid, text, text, date, text) from public, anon;
grant execute on function public.identity_verify(uuid, text, text, date, text) to authenticated;

-- Onayı kaldırma: admin ya da oyuncunun oynadığı turnuvanın kurucu başkanı.
create or replace function public.can_unverify_player(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select public.is_admin() or exists (
    select 1
      from public.season_team_players stp
      join public.seasons s on s.id = stp.season_id
      join public.league_owners lo on lo.league_id = s.league_id
     where stp.player_id = p_player_id and lo.user_id = auth.uid()
  )
$function$;
grant execute on function public.can_unverify_player(uuid) to authenticated;

create or replace function public.identity_unverify(p_player_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not public.can_unverify_player(p_player_id) then
    raise exception 'Onayı yalnız admin ya da kurucu başkan kaldırabilir.';
  end if;
  delete from public.player_verifications where player_id = p_player_id;
  insert into public.identity_events (player_id, action, user_id)
  values (p_player_id, 'unverify', auth.uid());
end;
$function$;
revoke all on function public.identity_unverify(uuid) from public, anon;
grant execute on function public.identity_unverify(uuid) to authenticated;

-- Esame engeli: sezonda onaylı kimlik zorunluysa onaysız oyuncu esameye
-- eklenemez. Bitmiş maçların esamesi (geçmiş düzeltmeleri) etkilenmez.
create or replace function public.match_rosters_require_verified()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_name text;
begin
  if new.player_id is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.player_id is not distinct from old.player_id then
    return new;
  end if;
  if not exists (
    select 1 from public.seasons s
     where s.id = new.season_id and s.require_verified_id
  ) then
    return new;
  end if;
  if exists (select 1 from public.matches m
              where m.id = new.match_id and m.status = 'finished') then
    return new;
  end if;
  if exists (select 1 from public.player_verifications v
              where v.player_id = new.player_id) then
    return new;
  end if;
  select p.name || ' ' || p.surname into v_name
    from public.players p where p.id = new.player_id;
  raise exception 'KIMLIK_ONAYSIZ: % kimliği onaylı değil; bu sezonda esameye eklenemez.',
    coalesce(v_name, 'Oyuncu');
end;
$function$;

drop trigger if exists require_verified on public.match_rosters;
create trigger require_verified
  before insert or update of player_id on public.match_rosters
  for each row execute function public.match_rosters_require_verified();

-- Hesap silinince kimlik onayı (TC özeti dahil) da silinir.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_leagues text;
begin
  if v_uid is null then
    raise exception 'Giriş yapılmamış.';
  end if;

  select string_agg(l.name, ', ' order by l.name) into v_leagues
  from public.league_owners o
  join public.leagues l on l.id = o.league_id
  where o.user_id = v_uid
    and not exists (
      select 1 from public.league_owners x
      where x.league_id = o.league_id and x.user_id <> v_uid
    );
  if v_leagues is not null then
    raise exception 'SOLE_OWNER: %', v_leagues;
  end if;

  update public.player_consents set user_id = null where user_id = v_uid;

  delete from public.player_verifications
  where player_id in (select id from public.players where auth_uid = v_uid);

  update public.players
  set phone = null,
      national_id = null,
      photo_url = null,
      height = null,
      weight = null,
      auth_uid = null
  where auth_uid = v_uid;

  delete from public.app_users
  where auth_uid = v_uid::text or uid = v_uid::text;

  delete from public.account_requests where user_id = v_uid;

  delete from auth.users where id = v_uid;
end;
$function$;
