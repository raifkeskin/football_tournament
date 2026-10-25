-- Gol kesitleri: maç başı tarama sınırı ve yeniden taramada tam temizlik.
--  * match_highlight_jobs.scan_count: maçta kaç kez tarama başlatıldı
--    (maç bitince yapılan otomatik tarama da sayılır).
--  * ai_clip_scan_limit: kurucu başkan / bölge sorumlusu bir maçı en fazla
--    kaç kez taratabilir (admin hariç). Yapay Zekâ Yönetimi'nden ayarlanır.
--  * highlight_scan_quota(): uygulama onay penceresinde kalan hakkı gösterir.
alter table public.match_highlight_jobs
  add column if not exists scan_count int not null default 0;

-- Mevcut işler en az bir kez taranmış sayılır.
update public.match_highlight_jobs set scan_count = 1 where scan_count = 0;

insert into public.app_private_settings (key, value) values
  ('ai_clip_scan_limit', '3')
on conflict (key) do nothing;

create or replace function public.highlight_scan_quota(p_match_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $$
declare
  v_used int;
  v_limit int;
begin
  if not public.owns_match(p_match_id) then
    raise exception 'Yetkiniz yok.';
  end if;
  select coalesce(scan_count, 0) into v_used
    from public.match_highlight_jobs where match_id = p_match_id;
  select case when value ~ '^[0-9]{1,2}$' then value::int end into v_limit
    from public.app_private_settings where key = 'ai_clip_scan_limit';
  return jsonb_build_object(
    'used', coalesce(v_used, 0),
    'limit', coalesce(nullif(v_limit, 0), 3),
    'unlimited', public.is_admin()
  );
end $$;
revoke all on function public.highlight_scan_quota(uuid) from public, anon;
grant execute on function public.highlight_scan_quota(uuid) to authenticated;

create or replace function public.ai_admin_settings()
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $$
declare
  r jsonb;
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.';
  end if;
  select jsonb_object_agg(key, value) into r
    from public.app_private_settings
   where key in ('ai_model_esame', 'ai_model_clips', 'usd_try',
                 'usd_try_date', 'ai_clip_monthly_usd',
                 'ai_thinking_esame', 'ai_esame_read_limit',
                 'ai_clip_scan_limit');
  return coalesce(r, '{}'::jsonb);
end $$;

create or replace function public.ai_admin_set_option(p_key text, p_value text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.';
  end if;
  if not (
    (p_key = 'ai_thinking_esame' and p_value in ('low', 'high'))
    or (p_key in ('ai_esame_read_limit', 'ai_clip_scan_limit')
        and p_value ~ '^[0-9]{1,2}$' and p_value::int between 1 and 20)
  ) then
    raise exception 'Geçersiz seçim.';
  end if;
  insert into public.app_private_settings (key, value, updated_at)
  values (p_key, p_value, now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
end $$;
revoke all on function public.ai_admin_set_option(text, text) from public, anon;
grant execute on function public.ai_admin_set_option(text, text) to authenticated;
