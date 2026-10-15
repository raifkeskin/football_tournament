-- Lig formatı: puan tablosu bölgeleri ve play-off kupaları (sezon başına).
-- Örnek: {"cups":[{"name":"Şampiyonluk Play-Off","from":1,"to":4,"legs":1,
--          "third":false}], "rest":"out", "show_if_now":true}
-- Boşsa uygulama eski görünümü (ilk 4 / son 4) kullanır. Yalnız ekleme: eski
-- sürümler sütunu okumaz.
alter table public.seasons
  add column if not exists league_format jsonb;
