-- Esame okuma: düşünme seviyesi (kısa / uzun) ve takım başına okuma sınırı
-- Yapay Zekâ Yönetimi'nden ayarlanır; sunucu her okumada okur.
--  * ai_thinking_esame: low (kısa, hızlı ve ucuz; varsayılan) | high (uzun)
--  * ai_esame_read_limit: bir maçta bir takımın esamesi en fazla kaç kez
--    okutulabilir (admin hariç).
alter table public.ai_usage_log add column if not exists team_id uuid;

insert into public.app_private_settings (key, value) values
  ('ai_thinking_esame', 'low'),
  ('ai_esame_read_limit', '3')
on conflict (key) do nothing;

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
                 'ai_thinking_esame', 'ai_esame_read_limit');
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
    or (p_key = 'ai_esame_read_limit' and p_value ~ '^[0-9]{1,2}$'
        and p_value::int between 1 and 20)
  ) then
    raise exception 'Geçersiz seçim.';
  end if;
  insert into public.app_private_settings (key, value, updated_at)
  values (p_key, p_value, now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
end $$;
revoke all on function public.ai_admin_set_option(text, text) from public, anon;
grant execute on function public.ai_admin_set_option(text, text) to authenticated;
