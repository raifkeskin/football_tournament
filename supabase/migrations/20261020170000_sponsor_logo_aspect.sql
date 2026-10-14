-- Sponsor logosunun en/boy oranı (standart PNG'den). Şerit logoyu sabit
-- yükseklikte bu orana göre genişlikte çizer; resim yüklenmeden yer ayrılır.
-- Eski kayıtlarda null (576×216 tuval varsayılır).
alter table public.sponsors
  add column if not exists logo_aspect real;
