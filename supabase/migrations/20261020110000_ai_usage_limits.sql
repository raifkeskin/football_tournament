-- YZ (Gemini) harcama kaydı ve sınırları.
--
-- Her Gemini çağrısı token sayısı ve tahmini maliyetiyle ai_usage_log'a
-- yazılır. `video-highlights` çalışmadan önce tahmini maliyeti sınırlarla
-- karşılaştırır; aşıyorsa Gemini'ye hiç gidilmez:
--   ai_clip_max_usd_per_match : tek maç analizinin üst sınırı (USD)
--   ai_clip_monthly_usd       : bu ayki toplam YZ harcamasının üst sınırı (USD)

create table if not exists public.ai_usage_log (
  id bigint generated always as identity primary key,
  match_id uuid references public.matches(id) on delete set null,
  model text,
  -- kickoff | second_half | goals | full
  purpose text,
  text_tokens int,
  video_tokens int,
  audio_tokens int,
  output_tokens int,
  cost_usd numeric(10, 5) not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists ai_usage_log_created_idx
  on public.ai_usage_log (created_at);

alter table public.ai_usage_log enable row level security;

drop policy if exists ai_usage_log_admin_read on public.ai_usage_log;
create policy ai_usage_log_admin_read on public.ai_usage_log
  for select to authenticated
  using (public.is_admin());

grant select on public.ai_usage_log to authenticated;

alter table public.match_highlight_jobs
  add column if not exists cost_usd numeric(10, 5),
  add column if not exists kickoff_sec int,
  add column if not exists second_half_sec int;

insert into public.app_private_settings (key, value) values
  ('ai_clip_max_usd_per_match', '0.50'),
  ('ai_clip_monthly_usd', '5')
on conflict (key) do nothing;
