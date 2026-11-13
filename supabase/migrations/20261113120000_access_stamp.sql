-- Hız Faz 2A: yetki özeti.
--
-- Cihazdaki önbellek, veri sürümleriyle (data_versions) doğrulanır; ama
-- yetki değişince (sorumlu ataması, gizli turnuvaya kod, kadroya eklenme,
-- turnuvanın gizlenmesi) sürüm artmadığı için saklanan liste eski
-- kalıyordu. my_access_stamp() kişinin gördüğü veriyi belirleyen her şeyin
-- kısa özetidir; erişim kurallarının kullandığı küme fonksiyonlarından
-- hesaplanır (tetikleyici gerekmez, kurallarla hep aynı kalır). Uygulama
-- özeti sürümlerle aynı istekte alır (data_versions_for); özet değişince
-- saklanan veri geçersiz olur ve açık ekranlar yeniden okur.

create or replace function public.my_access_stamp()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select md5(concat_ws('|',
    coalesce((select auth.uid())::text, '-'),
    public.is_admin()::text,
    public.app_flag('video_news_public')::text,
    coalesce((select string_agg(x::text, ',' order by x)
                from public.rls_visible_league_ids() x), ''),
    coalesce((select string_agg(o.league_id::text, ',' order by o.league_id)
                from public.league_owners o
               where o.user_id = (select auth.uid())), ''),
    coalesce((select string_agg(x::text, ',' order by x)
                from public.rls_owned_season_ids() x), ''),
    coalesce((select string_agg(r.region_id::text || ':' || r.season_id::text,
                                ',' order by r.region_id, r.season_id)
                from public.rls_owned_region_pairs() r), ''),
    coalesce((select string_agg(t.season_id::text || ':' || t.team_id::text,
                                ',' order by t.season_id, t.team_id)
                from public.team_managers t
               where t.user_id = (select auth.uid())), '')
  ));
$$;

-- Sürümler + yetki özeti tek istekte: {"v": {kapsam: sürüm}, "a": özet}.
-- Satırı olmayan kapsam (hiç değişmemiş) sonuçta yer almaz: sürüm 0.
create or replace function public.data_versions_for(p_scopes text[])
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'v', coalesce((select jsonb_object_agg(d.scope, d.version)
                     from public.data_versions d
                    where d.scope = any(p_scopes[1:500])), '{}'::jsonb),
    'a', public.my_access_stamp());
$$;

revoke all on function public.my_access_stamp() from public;
revoke all on function public.data_versions_for(text[]) from public;
grant execute on function public.my_access_stamp() to anon, authenticated, service_role;
grant execute on function public.data_versions_for(text[]) to anon, authenticated, service_role;
