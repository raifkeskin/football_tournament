-- Lisans Yönetimi'nde TC girişi: kimliği henüz okutulmamış futbolcu için
-- admin TC'yi girer; TC düz saklanmaz, girildiği anda kimlik doğrulamadaki
-- aynı özet (_identity_hash, HMAC-SHA256) alınır ve "bekleyen" olarak
-- tutulur. Mavi tik vermez. Futbolcu kimliğini okutunca (hangi yoldan
-- olursa olsun player_verifications'a yazılınca) özetler karşılaştırılır:
-- eşleşirse bekleyen kayıt silinir; eşleşmezse işaretlenir ve adminlere
-- Telegram'dan haber gider. Kendi kaydında da (register_player) bekleyen
-- özetle profil bulunur. Aynı TC iki profile girilemez.

create table if not exists public.player_tc_pending (
  player_id uuid primary key references public.players(id) on delete cascade,
  tc_hash text not null unique,
  -- Futbolcu TC'sini kendisi gönderdi (rıza kaydı).
  sent_by_player boolean not null default false,
  entered_by uuid,
  entered_at timestamptz not null default now(),
  -- Kimlik okutuldu ama özet uyuşmadı / başka profilde okutuldu.
  mismatch_at timestamptz
);

-- Doğrudan erişim yok: yalnız aşağıdaki fonksiyonlar (security definer).
alter table public.player_tc_pending enable row level security;
revoke all on public.player_tc_pending from anon, authenticated;

-- Girilecek TC için çakışma kontrolü; sorun yoksa null, varsa açıklama.
create or replace function public.tc_pending_check(p_tc text, p_player_id uuid default null)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_hash text;
  v_name text;
begin
  if not public.is_admin() then
    raise exception 'Bu işlem için yetkiniz yok.';
  end if;
  if not public.tc_valid(p_tc) then
    return 'TC Kimlik No geçersiz. 11 haneyi kontrol edin.';
  end if;
  v_hash := public._identity_hash(p_tc);

  if p_player_id is not null and exists (
    select 1 from public.player_verifications
     where player_id = p_player_id) then
    if exists (select 1 from public.player_verifications
                where player_id = p_player_id and tc_hash = v_hash) then
      return 'Bu futbolcu zaten bu kimlikle doğrulanmış.';
    end if;
    return 'Bu futbolcu başka bir kimlikle doğrulanmış.';
  end if;

  select p.name || ' ' || p.surname into v_name
    from public.player_verifications v
    join public.players p on p.id = v.player_id
   where v.tc_hash = v_hash
     and v.player_id is distinct from p_player_id;
  if v_name is not null then
    return 'Bu TC kimlikle doğrulanmış başka bir futbolcuya ait: ' || v_name || '.';
  end if;

  select p.name || ' ' || p.surname into v_name
    from public.player_tc_pending d
    join public.players p on p.id = d.player_id
   where d.tc_hash = v_hash
     and d.player_id is distinct from p_player_id;
  if v_name is not null then
    return 'Bu TC başka bir futbolcuya girilmiş: ' || v_name || '.';
  end if;
  return null;
end;
$$;

-- TC'yi girer (ya da değiştirir). Dönen: 'ok' ya da hata (raise).
create or replace function public.tc_pending_set(p_player_id uuid, p_tc text, p_sent boolean default false)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_problem text;
begin
  v_problem := public.tc_pending_check(p_tc, p_player_id);
  if v_problem is not null then
    raise exception '%', v_problem;
  end if;
  if not exists (select 1 from public.players where id = p_player_id) then
    raise exception 'Futbolcu bulunamadı.';
  end if;

  insert into public.player_tc_pending (player_id, tc_hash, sent_by_player, entered_by)
  values (p_player_id, public._identity_hash(p_tc), coalesce(p_sent, false), auth.uid())
  on conflict (player_id) do update
     set tc_hash = excluded.tc_hash,
         sent_by_player = excluded.sent_by_player,
         entered_by = excluded.entered_by,
         entered_at = now(),
         mismatch_at = null;

  insert into public.identity_events (player_id, action, user_id)
  values (p_player_id, 'tc_pending_set', auth.uid());
  return 'ok';
end;
$$;

-- Girilen TC'yi siler (yanlış girildiyse; TC görülmeden).
create or replace function public.tc_pending_clear(p_player_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Bu işlem için yetkiniz yok.';
  end if;
  delete from public.player_tc_pending where player_id = p_player_id;
  if found then
    insert into public.identity_events (player_id, action, user_id)
    values (p_player_id, 'tc_pending_clear', auth.uid());
  end if;
end;
$$;

-- Formdaki durum satırı için (TC'nin kendisi hiçbir zaman dönmez).
create or replace function public.tc_pending_info(p_player_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  d record;
begin
  if not public.is_admin() then
    raise exception 'Bu işlem için yetkiniz yok.';
  end if;
  select * into d from public.player_tc_pending where player_id = p_player_id;
  return jsonb_build_object(
    'verified', exists (select 1 from public.player_verifications
                         where player_id = p_player_id),
    'pending', d.player_id is not null,
    'entered_at', d.entered_at,
    'sent_by_player', coalesce(d.sent_by_player, false),
    'mismatch', d.mismatch_at is not null
  );
end;
$$;

-- Kimlik doğrulanınca bekleyen özetle karşılaştır.
create or replace function public.player_tc_pending_on_verify()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  d record;
  v_name text;
begin
  select * into d from public.player_tc_pending where player_id = new.player_id;
  if found then
    if d.tc_hash = new.tc_hash then
      delete from public.player_tc_pending where player_id = new.player_id;
      insert into public.identity_events (player_id, action, user_id)
      values (new.player_id, 'tc_pending_match', auth.uid());
    elsif d.mismatch_at is null then
      update public.player_tc_pending set mismatch_at = now()
       where player_id = new.player_id;
      insert into public.identity_events (player_id, action, user_id)
      values (new.player_id, 'tc_pending_mismatch', auth.uid());
      select name || ' ' || surname into v_name from public.players where id = new.player_id;
      perform public.telegram_notify(
        array(select user_id from public.admins where user_id is not null),
        'Kimlik uyuşmazlığı: ' || coalesce(v_name, 'futbolcu')
          || ' kimliğini okuttu ama Lisans Yönetimi''nde girilen TC kimlikle uyuşmadı. '
          || 'Doğrulama kimliğe göre yapıldı; girilen TC''yi kontrol edin.'
      );
    end if;
  end if;

  -- Aynı TC başka bir profile girilmişse: o profil büyük ihtimalle aynı kişi.
  for d in
    select * from public.player_tc_pending
     where tc_hash = new.tc_hash and player_id <> new.player_id
       and mismatch_at is null
  loop
    update public.player_tc_pending set mismatch_at = now()
     where player_id = d.player_id;
    insert into public.identity_events (player_id, action, user_id)
    values (d.player_id, 'tc_pending_other', auth.uid());
    select name || ' ' || surname into v_name from public.players where id = new.player_id;
    perform public.telegram_notify(
      array(select user_id from public.admins where user_id is not null),
      'Olası çift kayıt: Lisans Yönetimi''nde bir profile girilen TC, '
        || coalesce(v_name, 'başka bir futbolcu') || ' profilinde kimlikle doğrulandı. '
        || 'Profilleri kontrol edin.'
    );
  end loop;
  return new;
end;
$$;

drop trigger if exists tc_pending_on_verify on public.player_verifications;
create trigger tc_pending_on_verify
after insert or update of tc_hash on public.player_verifications
for each row execute function public.player_tc_pending_on_verify();

revoke all on function public.tc_pending_check(text, uuid) from public, anon;
revoke all on function public.tc_pending_set(uuid, text, boolean) from public, anon;
revoke all on function public.tc_pending_clear(uuid) from public, anon;
revoke all on function public.tc_pending_info(uuid) from public, anon;
revoke all on function public.player_tc_pending_on_verify() from public, anon, authenticated;
grant execute on function public.tc_pending_check(text, uuid) to authenticated;
grant execute on function public.tc_pending_set(uuid, text, boolean) to authenticated;
grant execute on function public.tc_pending_clear(uuid) to authenticated;
grant execute on function public.tc_pending_info(uuid) to authenticated;
