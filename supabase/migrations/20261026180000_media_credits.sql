-- Medya künyesi: turnuvanın fotoğrafçısı ve maç yayıncısı. Maç detayı
-- Medya sekmesinde "Fotoğraf: …" / "Yayın: …" etiketi çıkar, dokununca
-- kartvizit açılır (telefon, e-posta, Instagram, YouTube).
-- Turnuva başına her türden bir kayıt. Yalnız admin ve kurucu başkan yönetir.
-- Telefon ve e-posta herkese açık gösterilir; bu yüzden kişinin onayı
-- (contact_consent) işaretlenmeden kaydedilemez.

create table if not exists public.media_credits (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  kind text not null check (kind in ('photo', 'broadcast')),
  name text not null check (length(btrim(name)) between 1 and 80),
  title text,
  avatar_url text,
  phone text,
  email text,
  instagram text,
  youtube_url text,
  note text check (note is null or length(note) <= 300),
  contact_consent boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (league_id, kind),
  constraint media_credits_contact_needs_consent check (
    contact_consent
    or (coalesce(btrim(phone), '') = '' and coalesce(btrim(email), '') = '')
  )
);

drop trigger if exists set_updated_at on public.media_credits;
create trigger set_updated_at before update on public.media_credits
  for each row execute function public.set_updated_at();

alter table public.media_credits enable row level security;

drop policy if exists media_credits_read on public.media_credits;
create policy media_credits_read on public.media_credits for select
  using (public.can_view_league(league_id));

drop policy if exists media_credits_insert on public.media_credits;
create policy media_credits_insert on public.media_credits for insert to authenticated
  with check (public.owns_league(league_id));

drop policy if exists media_credits_update on public.media_credits;
create policy media_credits_update on public.media_credits for update to authenticated
  using (public.owns_league(league_id)) with check (public.owns_league(league_id));

drop policy if exists media_credits_delete on public.media_credits;
create policy media_credits_delete on public.media_credits for delete to authenticated
  using (public.owns_league(league_id));

grant select on public.media_credits to anon, authenticated;
grant insert, update, delete on public.media_credits to authenticated;
