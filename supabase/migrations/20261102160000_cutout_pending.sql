-- Dekupe bekleyenler: fotoğrafı olup dekupesi olmayan oyuncular. Dekupe Mac'te
-- betikle üretilir (scripts/make_cutouts.py); betiğin üretemediği fotoğraflar
-- (yüz yok / düşük çözünürlük) sebebiyle buraya yazılır, listede ayrı görünür.
create table if not exists public.player_photo_cutout_skips (
  photo_url text primary key,
  reason text not null,
  created_at timestamptz not null default now()
);
alter table public.player_photo_cutout_skips enable row level security;

drop policy if exists player_photo_cutout_skips_admin on public.player_photo_cutout_skips;
create policy player_photo_cutout_skips_admin on public.player_photo_cutout_skips
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

grant select, insert, update, delete on public.player_photo_cutout_skips to authenticated;

create or replace function public.admin_cutout_pending()
returns table (
  player_id uuid,
  full_name text,
  team_name text,
  photo_url text,
  photo_changed_at timestamptz,
  skip_reason text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'yetki yok';
  end if;
  return query
  select p.id,
         trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, '')),
         (select t.name
            from season_team_players stp
            join teams t on t.id = stp.team_id
           where stp.player_id = p.id and stp.is_active
           order by stp.created_at desc nulls last
           limit 1),
         p.photo_url,
         p.updated_at,
         s.reason
    from players p
    left join player_photo_cutout_skips s on s.photo_url = p.photo_url
   where coalesce(trim(p.photo_url), '') <> ''
     and not exists (
       select 1 from player_photo_cutouts c where c.photo_url = p.photo_url
     )
   order by (s.reason is not null), p.updated_at desc nulls last;
end;
$$;

revoke all on function public.admin_cutout_pending() from public, anon;
grant execute on function public.admin_cutout_pending() to authenticated;
