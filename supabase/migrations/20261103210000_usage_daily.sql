-- Trafik toplama günde bir kez (04:07 İstanbul) ve İstatistikler'deki
-- "Şimdi güncelle" ile; saatlik çağrı gereksizdi.
select cron.unschedule('usage-collect') where exists (select 1 from cron.job where jobname = 'usage-collect');
select cron.schedule('usage-collect', '7 1 * * *', 'select public.usage_collect_tick()');

-- Admin elle tetikler; işlev arka planda çalışır, sonuç birkaç saniyede yazılır.
create or replace function public.usage_collect_now()
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.';
  end if;
  perform public.usage_collect_tick();
end;
$$;

revoke all on function public.usage_collect_now() from public, anon;
grant execute on function public.usage_collect_now() to authenticated;
