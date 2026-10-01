-- Gözlemci atama: admin / turnuva sahibi kayıtlı kullanıcıları seçebilsin.
-- auth.users istemciden okunamaz; ad, bağlı oyuncudan (players.auth_uid)
-- yoksa e-posta / telefondan gelir.

create or replace function public.list_observer_candidates()
returns table (user_id uuid, label text)
language sql
stable
security definer
set search_path to ''
as $$
  select u.id,
         coalesce(
           nullif(trim(p.name), ''),
           nullif(trim(u.raw_user_meta_data->>'name'), ''),
           nullif(u.email, ''),
           u.phone
         ) as label
  from auth.users u
  left join lateral (
    select pl.name from public.players pl
    where pl.auth_uid = u.id
    limit 1
  ) p on true
  where public.is_admin() or public.is_any_league_owner()
  order by 2
$$;

revoke all on function public.list_observer_candidates() from public;
grant execute on function public.list_observer_candidates() to authenticated;
