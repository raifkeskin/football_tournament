-- Penaltıdan atılan goller ayrı işaretlenir (maç detayında farklı ikon).
alter table public.match_events
  add column if not exists is_penalty boolean not null default false;
