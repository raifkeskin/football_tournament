-- Kayıt talebi: hesabı olmayan ve hiçbir oyuncu kaydında bulunmayan numara
-- talep açamaz ('unknown_phone'); kullanıcı takım sorumlusuna yönlendirilir.
-- (Turnuva sorumluları / görevliler admin tarafından doğrudan eklenir.)
create or replace function public.request_account_password(
  p_phone text,
  p_full_name text default null,
  p_reset boolean default false
)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_raw text := public.phone_raw10(p_phone);
  v_name text := nullif(trim(coalesce(p_full_name, '')), '');
  v_has_account boolean;
  v_kind text;
begin
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    return 'invalid_phone';
  end if;

  select exists (
    select 1 from auth.users where email = v_raw || '@masterclass.com'
  ) into v_has_account;

  if p_reset and not v_has_account then
    return 'not_registered';
  end if;

  if not v_has_account and not exists (
    select 1 from public.players p where public.phone_raw10(p.phone) = v_raw
  ) then
    return 'unknown_phone';
  end if;

  v_kind := case when v_has_account then 'reset' else 'register' end;

  update public.account_requests
  set kind = v_kind,
      full_name = coalesce(v_name, full_name)
  where phone_raw10 = v_raw and status = 'pending';
  if found then
    return 'already_pending';
  end if;

  insert into public.account_requests (phone_raw10, kind, full_name)
  values (v_raw, v_kind, left(v_name, 80));

  return case when v_has_account then 'reset_requested' else 'requested' end;
end;
$$;
