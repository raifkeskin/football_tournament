-- Kayıtlar: admin hesapları ve demo başkan (5000000000) listede ve sayılarda yok.
create or replace function public.admin_registrations(p_limit integer default 200)
 returns jsonb language plpgsql stable security definer set search_path to ''
as $function$
begin
  if not public.is_admin() then
    return '[]'::jsonb;
  end if;
  return coalesce((
    select jsonb_agg(r order by (r->>'created_at') desc)
    from (
      select jsonb_build_object(
        'id', u.id,
        'created_at', u.created_at,
        'last_sign_in', u.last_sign_in_at,
        'name', coalesce(
          nullif(trim(concat_ws(' ', pl.name, pl.surname)), ''),
          nullif(u.raw_user_meta_data ->> 'name', ''),
          au.name),
        'phone', case when split_part(u.email, '@', 1) ~ '^5[0-9]{9}$'
                      then split_part(u.email, '@', 1) end,
        'kind', case
          when pl.id is not null then 'player'
          when au.role = 'fan' then 'fan'
          when exists (select 1 from public.league_owners lo where lo.user_id = u.id) then 'organizer'
          when exists (select 1 from public.region_owners ro where ro.user_id = u.id) then 'organizer'
          else coalesce(au.role, 'other') end,
        'verified', case
          when pl.id is null then null
          when exists (select 1 from public.identity_pending ip where ip.player_id = pl.id) then 'pending'
          else (select v.method from public.player_verifications v where v.player_id = pl.id) end
      ) as r
      from auth.users u
      left join public.players pl on pl.auth_uid = u.id
      left join public.app_users au on au.auth_uid = u.id::text
      where split_part(u.email, '@', 2) = 'masterclass.com'
        and split_part(u.email, '@', 1) <> '5000000000'
        and not exists (select 1 from public.admins ad where ad.user_id = u.id)
      order by u.created_at desc
      limit greatest(1, least(coalesce(p_limit, 200), 1000))
    ) t
  ), '[]'::jsonb);
end;
$function$;
grant execute on function public.admin_registrations(integer) to authenticated;
