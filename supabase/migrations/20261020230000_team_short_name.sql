-- Takım kısa adı (opsiyonel): dar ekranlarda tam ad sığmadığında kullanılır.
-- Boşsa uygulama otomatik kısaltmaya (shortTeamName) devam eder.
alter table public.teams
  add column if not exists short_name text
    check (short_name is null or length(short_name) <= 16);
