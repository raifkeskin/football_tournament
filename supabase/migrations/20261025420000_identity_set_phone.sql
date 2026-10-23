-- Kimliği doğrulanan telefonsuz profile numara: yetkili (admin, kurucu
-- başkan, bölge sorumlusu, takım sorumlusu) kimliği okuttuktan sonra
-- numarayı yazar. Numara hesabı olmayan ("onaysız") numaradır; futbolcu ilk
-- girişinde (Şifremi Unuttum / şifre al) o numaraya gelen kodla hesabını
-- açınca onaylanmış olur.
--
-- Kural: hesabı açılmış (onaylı) doğrulanmış profilin numarası yalnızca
-- kişinin kendisi kimliğini okutarak değiştirir (phone_change_*); admin
-- dışında kimse elle değiştiremez.

create or replace function public.identity_set_phone(
  p_player_id uuid, p_phone text
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_raw text := public.phone_raw10(p_phone);
  p record;
begin
  if auth.uid() is null
     or coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    return 'forbidden';
  end if;
  if not public.identity_allowed() then
    return 'disabled';
  end if;
  if not (public.owns_player(p_player_id) or public.manages_player(p_player_id)) then
    return 'forbidden';
  end if;

  select * into p from public.players where id = p_player_id for update;
  if not found then
    return 'not_found';
  end if;
  if not exists (select 1 from public.player_verifications
                  where player_id = p_player_id) then
    return 'not_verified';
  end if;
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    return 'invalid_phone';
  end if;
  if public.phone_raw10(p.phone) = v_raw then
    return 'same_phone';
  end if;
  -- Hesabı açılmış numara yalnızca kimlikle değişir.
  if p.auth_uid is not null then
    return 'confirmed';
  end if;
  if exists (select 1 from public.players x
              where public.phone_raw10(x.phone) = v_raw and x.id <> p_player_id)
     or exists (select 1 from auth.users u
                 where u.email = v_raw || '@masterclass.com'
                    or public.phone_raw10(u.phone) = v_raw) then
    return 'phone_taken';
  end if;

  update public.players set phone = v_raw where id = p_player_id;
  insert into public.identity_events (player_id, action, user_id)
  values (p_player_id, 'set_phone', auth.uid());
  return 'ok';
end;
$function$;
revoke all on function public.identity_set_phone(uuid, text) from public, anon;
grant execute on function public.identity_set_phone(uuid, text) to authenticated;

-- Onaylı numaranın elle değişmesini engeller (admin ve kişinin kendi
-- kimlikli akışı hariç).
create or replace function public.players_guard_verified_phone()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if public.phone_raw10(old.phone) is not null
     and public.phone_raw10(new.phone) is distinct from public.phone_raw10(old.phone)
     and old.auth_uid is not null
     and auth.uid() is not null
     and auth.uid() is distinct from old.auth_uid
     and not public.is_admin()
     and exists (select 1 from public.player_verifications v
                  where v.player_id = old.id) then
    raise exception 'Kimliği onaylı profilin numarası yalnızca kişinin kendisi kimliğini okutarak değiştirilebilir.';
  end if;
  return new;
end;
$function$;

drop trigger if exists players_guard_verified_phone on public.players;
create trigger players_guard_verified_phone
  before update of phone on public.players
  for each row execute function public.players_guard_verified_phone();

-- Kimlik okutulduktan sonra numara sorulsun mu: none (numara yok),
-- unconfirmed (var, hesap açılmamış), confirmed (hesabı var), forbidden.
create or replace function public.identity_phone_state(p_player_id uuid)
returns text
language sql
stable
security definer
set search_path to ''
as $function$
  select case
    when not (public.owns_player(p_player_id) or public.manages_player(p_player_id))
      then 'forbidden'
    when p.auth_uid is not null then 'confirmed'
    when public.phone_raw10(p.phone) is null then 'none'
    else 'unconfirmed'
  end
  from public.players p
  where p.id = p_player_id
$function$;
revoke all on function public.identity_phone_state(uuid) from public, anon;
grant execute on function public.identity_phone_state(uuid) to authenticated;
