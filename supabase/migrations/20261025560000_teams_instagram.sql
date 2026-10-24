-- Takımın Instagram adresi (maç önü videosu açıklamasında @etiket olarak).
-- Boş bırakılabilir; eski sürümler bu kolonu okumaz/yazmaz.
alter table public.teams add column if not exists instagram_url text;
