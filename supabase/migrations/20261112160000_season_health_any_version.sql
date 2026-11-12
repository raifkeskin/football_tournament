-- Sezon sağlık beyanı: o sezon için verilmiş beyan, onay metninin sürümü
-- sonradan değişse de geçerli kalır (beyan sezona özeldir; yeni metin yeni
-- sezonlarda istenir). Önceki hâli yalnız yürürlükteki sürümü sayıyordu ve
-- her metin güncellemesinde herkesten yeniden beyan isterdi.
create or replace function public.season_health_declared(
  p_player_id uuid,
  p_season_id uuid
)
returns boolean
language sql
stable security definer
set search_path to ''
as $$
  select exists (
      select 1 from public.player_season_declarations d
       where d.player_id = p_player_id
         and d.season_id = p_season_id
    )
    or (
      (select s.created_at < timestamptz '2026-11-13 00:00:00+03'
         from public.seasons s where s.id = p_season_id)
      and coalesce((
        select c.granted
          from public.player_consents c
         where c.player_id = p_player_id
           and c.consent_type = 'health_declaration'
         order by c.created_at desc
         limit 1
      ), false)
    )
$$;

revoke all on function public.season_health_declared(uuid, uuid)
  from public, anon, authenticated;
