-- Turnuva sahibi / bölge sorumlusu eklerken önce telefon yazılır; kişi
-- sistemde kayıtlıysa adı dolu gelir. Yalnız admin ve turnuva sahipleri
-- (bölge sorumlusu ekleyebilenler) sorgular; yalnız ad döner.

create or replace function public.person_name_by_phone(p_phone text)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_raw text := public.phone_raw10(p_phone);
  v_uid uuid;
  v_name text;
begin
  if not (public.is_admin() or public.is_any_league_owner()) then
    raise exception 'Yetkiniz yok.' using errcode = '42501';
  end if;
  if v_raw is null or v_raw !~ '^5[0-9]{9}$' then
    return null;
  end if;

  select id into v_uid from auth.users
   where email = v_raw || '@masterclass.com';

  -- Hesaba bağlı futbolcu profili, hesap adı, numarası kayıtlı futbolcu,
  -- sonra davet / takım sorumlusu kayıtları.
  select nullif(trim(concat_ws(' ', p.name, p.surname)), '') into v_name
    from public.players p
   where v_uid is not null and p.auth_uid = v_uid
   limit 1;
  if v_name is null and v_uid is not null then
    select nullif(trim(u.raw_user_meta_data ->> 'name'), '') into v_name
      from auth.users u where u.id = v_uid;
  end if;
  if v_name is null then
    select nullif(trim(concat_ws(' ', p.name, p.surname)), '') into v_name
      from public.players p
     where public.phone_raw10(p.phone) = v_raw
     order by p.created_at
     limit 1;
  end if;
  if v_name is null then
    select nullif(trim(full_name), '') into v_name from (
      select full_name, created_at from public.league_owner_invites
       where phone_raw10 = v_raw
      union all
      select full_name, created_at from public.region_owner_invites
       where phone_raw10 = v_raw
      union all
      select t.manager_name, c.updated_at from public.team_manager_contacts c
        join public.teams t on t.id = c.team_id
       where c.phone_raw10 = v_raw
    ) i
    where nullif(trim(full_name), '') is not null
    order by created_at limit 1;
  end if;

  if v_name is null and v_uid is null then
    return null;
  end if;
  return jsonb_build_object('name', v_name, 'has_account', v_uid is not null);
end;
$$;

revoke all on function public.person_name_by_phone(text) from public, anon;
grant execute on function public.person_name_by_phone(text) to authenticated;
