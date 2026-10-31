-- Kadro/Diziliş olay ikonları, futbolcu puanlama ve "Olay ekle" (elle girilen
-- puan olayları). Yeni özellikler match_insights_enabled açılana kadar
-- yalnız admin görür.

-- Sezonun puanlama ayarı: {"enabled": bool, "rules": {...}, "moments": {...}}
-- (boşsa puanlama kapalı; değerler uygulamadaki varsayılanlarla tamamlanır).
alter table public.seasons add column if not exists player_rating jsonb;

-- Elle girilen puan olayları (kurtarış, kritik müdahale...). match_events'e
-- yazılmaz: eski sürümler bilinmeyen olay türünü maç akışında göstermesin,
-- gol/kart tetikleyicileri etkilenmesin.
create table if not exists public.match_moments (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches (id) on delete cascade,
  team_id uuid references public.teams (id) on delete cascade,
  player_id uuid not null references public.players (id) on delete cascade,
  kind text not null,
  minute smallint,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists match_moments_match_idx on public.match_moments (match_id);
alter table public.match_moments enable row level security;

drop policy if exists match_moments_read on public.match_moments;
create policy match_moments_read on public.match_moments
  for select using (public.can_view_match(match_id));
drop policy if exists match_moments_insert on public.match_moments;
create policy match_moments_insert on public.match_moments
  for insert to authenticated with check (public.can_manage_match(match_id));
drop policy if exists match_moments_delete on public.match_moments;
create policy match_moments_delete on public.match_moments
  for delete to authenticated using (public.can_manage_match(match_id));

grant select on public.match_moments to anon, authenticated;
grant insert, delete on public.match_moments to authenticated;

insert into public.app_settings (key, value)
values ('match_insights_enabled', 'false'::jsonb)
on conflict (key) do nothing;
