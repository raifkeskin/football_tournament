-- Demo turnuvalara örnek sponsorlar: ana sayfadaki sponsor şeridi tanıtımda
-- görünsün. Logolar diğer turnuvalardaki örnek sponsorlarla aynı
-- (storage media/sponsors/ornek/); adlar " (Örnek)" ile biter.
-- Tekrar çalıştırılabilir: önce demo turnuvalardaki örnek sponsorları siler.
-- Not: demo_reset() turnuvaları silip yeniden kurar; sponsorlar cascade ile
-- gider, sonra bu dosya yeniden çalıştırılmalı.

delete from public.sponsors
where league_id in ('d0000000-0000-4000-8000-000000000001',
                    'd0000000-0000-4000-8000-000000000002',
                    'd0000000-0000-4000-8000-000000000003')
  and logo_url like '%/sponsors/ornek/%';

insert into public.sponsors (league_id, name, logo_url, link_url, tier, sort_order, is_active)
select l.id, o.name, o.logo_url, o.link_url, o.tier, o.sort_order, true
from public.leagues l
cross join (
  select distinct on (tier, name) name, logo_url, link_url, tier, sort_order
  from public.sponsors
  where logo_url like '%/sponsors/ornek/%'
    and league_id not in ('d0000000-0000-4000-8000-000000000001',
                          'd0000000-0000-4000-8000-000000000002',
                          'd0000000-0000-4000-8000-000000000003')
  order by tier, name, created_at
) o
where l.id in ('d0000000-0000-4000-8000-000000000001',
               'd0000000-0000-4000-8000-000000000002',
               'd0000000-0000-4000-8000-000000000003');
