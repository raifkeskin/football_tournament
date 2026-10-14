-- Sezonda gol/kart dakikası tutuluyor mu? Halısaha turnuvaları çoğunlukla
-- dakika yazmaz: false ise olay girişinde dakika alanı gizlenir, maç
-- detayında zaman çizelgesi yerine takım bazlı golcü listesi gösterilir ve
-- YZ gol kesitleri bölümü kapanır. Mevcut sezonlar etkilenmez (true).
alter table public.seasons
  add column if not exists track_goal_minutes boolean not null default true;
