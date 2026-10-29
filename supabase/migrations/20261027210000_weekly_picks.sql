-- Haftanın Seçimi: kurucu başkan / bölge sorumlusunun seçtiği haftanın golü,
-- oyuncusu ve takımı haber olarak yayınlanır. Kart verisi auto_data'da;
-- eski sürümler content + image_url'i düz haber olarak gösterir.
-- Herkese açılana dek (weekly_picks_enabled) yalnız admin yayınlayabilir.

alter table public.news drop constraint if exists news_auto_kind_check;
alter table public.news add constraint news_auto_kind_check check (
  auto_kind = any (array[
    'match_result', 'week_results', 'instagram', 'match_preview',
    'day_preview', 'goal_of_week', 'player_of_week', 'team_of_week'
  ]::text[])
);

-- Her hafta (sezon, bölge) için her türden tek seçim.
create unique index if not exists news_weekly_pick_uq on public.news (
  season_id,
  coalesce(region_id, '00000000-0000-0000-0000-000000000000'::uuid),
  week,
  auto_kind
) where auto_kind in ('goal_of_week', 'player_of_week', 'team_of_week');

insert into public.app_settings (key, value)
values ('weekly_picks_enabled', 'false'::jsonb)
on conflict (key) do nothing;

create or replace function public.publish_weekly_pick(
  p_season_id uuid,
  p_region_id uuid,
  p_week int,
  p_kind text,
  p_match_id uuid,
  p_content text,
  p_image_url text,
  p_data jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_img text := nullif(trim(coalesce(p_image_url, '')), '');
begin
  if p_kind not in ('goal_of_week', 'player_of_week', 'team_of_week') then
    raise exception 'Geçersiz seçim türü.';
  end if;
  if not (public.is_admin() or coalesce((
    select s.value = 'true'::jsonb from public.app_settings s
    where s.key = 'weekly_picks_enabled'), false)) then
    raise exception 'Haftanın Seçimi henüz açık değil.';
  end if;
  if not public.owns_news(p_season_id, p_region_id) then
    raise exception 'Bu turnuvada seçim yapma yetkiniz yok.';
  end if;
  if p_week is null or p_week < 1 then
    raise exception 'Hafta seçilmeli.';
  end if;
  if length(trim(coalesce(p_content, ''))) = 0 then
    raise exception 'Haber metni boş olamaz.';
  end if;

  select id into v_id from public.news
  where season_id = p_season_id
    and region_id is not distinct from p_region_id
    and week = p_week
    and auto_kind = p_kind;

  if v_id is null then
    insert into public.news (
      season_id, region_id, week, auto_kind, match_id, content,
      image_url, image_urls, auto_data, is_published
    ) values (
      p_season_id, p_region_id, p_week, p_kind, p_match_id, trim(p_content),
      v_img, case when v_img is null then '{}' else array[v_img] end,
      p_data, true
    ) returning id into v_id;
  else
    -- Yeniden seçim haberi günceller ve akışta yeniden üste taşır.
    update public.news set
      match_id = p_match_id,
      content = trim(p_content),
      image_url = v_img,
      image_urls = case when v_img is null then '{}' else array[v_img] end,
      auto_data = p_data,
      is_published = true,
      created_at = now()
    where id = v_id;
  end if;
  return v_id;
end;
$$;

revoke all on function public.publish_weekly_pick(uuid, uuid, int, text, uuid, text, text, jsonb) from public, anon;
grant execute on function public.publish_weekly_pick(uuid, uuid, int, text, uuid, text, text, jsonb) to authenticated;
