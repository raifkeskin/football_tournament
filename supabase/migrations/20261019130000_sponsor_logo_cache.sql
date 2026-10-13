-- Örnek sponsor logoları "no-cache" ile yüklenmişti; her açılışta yeniden
-- iniyordu. Aynı dosyalar 1 yıl önbellek ayarıyla sponsors/ornek/v2/ altına
-- yüklendi (storage RLS üzerine yazmaya izin vermiyor); adresler oraya çevrilir.
update public.sponsors
set logo_url = replace(logo_url, '/sponsors/ornek/', '/sponsors/ornek/v2/')
where logo_url like '%/sponsors/ornek/%'
  and logo_url not like '%/sponsors/ornek/v2/%';
