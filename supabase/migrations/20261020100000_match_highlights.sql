-- YZ ile maç videosundan önemli anlar (ilk aşama: goller).
--
-- Video indirilmez/kesilmez: YouTube yayınındaki başlangıç–bitiş saniyeleri
-- saklanır, uygulama yalnızca o aralığı oynatır. Kesitleri `video-highlights`
-- Edge Function'ı (Gemini) "onay bekliyor" olarak yazar; admin, kurucu başkan
-- ve bölge sorumlusu (owns_match) onaylar. Onaylananları maçı görebilen
-- herkes görür.

create table if not exists public.match_highlights (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  -- goal | chance | save | card (şimdilik yalnız goal üretiliyor)
  kind text not null default 'goal'
    check (kind in ('goal', 'chance', 'save', 'card')),
  -- Maç detayındaki gol olayı (varsa); gol satırındaki video ikonu buna bağlı.
  match_event_id uuid references public.match_events(id) on delete set null,
  team_id uuid references public.teams(id) on delete set null,
  minute int,
  -- YouTube video kimliği (kesit hangi yayından).
  video_id text not null,
  start_sec int not null check (start_sec >= 0),
  end_sec int not null,
  description text,
  confidence text check (confidence in ('high', 'medium', 'low')),
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  source text not null default 'ai' check (source in ('ai', 'manual')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (end_sec > start_sec)
);

create index if not exists match_highlights_match_idx
  on public.match_highlights (match_id, status);

alter table public.match_highlights enable row level security;

drop policy if exists match_highlights_select on public.match_highlights;
create policy match_highlights_select on public.match_highlights
  for select to anon, authenticated
  using (
    (status = 'approved' and public.can_view_match(match_id))
    or public.owns_match(match_id)
  );

drop policy if exists match_highlights_insert on public.match_highlights;
create policy match_highlights_insert on public.match_highlights
  for insert to authenticated
  with check (public.owns_match(match_id));

drop policy if exists match_highlights_update on public.match_highlights;
create policy match_highlights_update on public.match_highlights
  for update to authenticated
  using (public.owns_match(match_id))
  with check (public.owns_match(match_id));

drop policy if exists match_highlights_delete on public.match_highlights;
create policy match_highlights_delete on public.match_highlights
  for delete to authenticated
  using (public.owns_match(match_id));

grant select on public.match_highlights to anon, authenticated;
grant insert, update, delete on public.match_highlights to authenticated;

-- Maç başına son analiz işi (aynı anda tek iş; uygulama durumunu buradan okur).
create table if not exists public.match_highlight_jobs (
  match_id uuid primary key references public.matches(id) on delete cascade,
  status text not null default 'running'
    check (status in ('running', 'done', 'error')),
  video_id text,
  -- 'events': maç detayındaki gol dakikalarının çevresi; 'full': tüm video.
  mode text,
  model text,
  found int,
  error text,
  requested_by uuid references auth.users(id) on delete set null,
  started_at timestamptz not null default now(),
  finished_at timestamptz
);

alter table public.match_highlight_jobs enable row level security;

drop policy if exists match_highlight_jobs_select on public.match_highlight_jobs;
create policy match_highlight_jobs_select on public.match_highlight_jobs
  for select to authenticated
  using (public.owns_match(match_id));

-- Yazma yalnızca Edge Function (service role) üzerinden.
grant select on public.match_highlight_jobs to authenticated;
