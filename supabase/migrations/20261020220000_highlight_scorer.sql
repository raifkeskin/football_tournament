-- Gol kesitinde golü atan oyuncu. YZ spikerin söylediği adı / forma
-- numarasını esameyle eşleştirirse doldurur; eşleşmezse yetkili onaylarken
-- esameden seçer. Boşsa kesit maç detayındaki gole bağlıysa o golün oyuncusu
-- gösterilir. Yalnız ekleme: eski sürümler bu sütunu okumaz.

alter table public.match_highlights
  add column if not exists player_id uuid
    references public.players(id) on delete set null;
