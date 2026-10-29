-- Drive'dan maç fotoğrafı alma: LigMasasi klasöründe adında maç kodu
-- (#LM + maç kimliğinin ilk 6 hanesi) geçen klasörlerdeki fotoğraflar
-- 15 dakikada bir o maçın Medya'sına "Maçtan Fotoğraflar" olarak eklenir
-- (edge function drive-sync). Alınan dosya bir daha alınmaz; uygulamada
-- silinen fotoğraf geri gelmez.

create table if not exists public.drive_media_seen (
  file_id text primary key,
  match_id uuid,
  media_id uuid,
  folder_name text,
  created_at timestamptz not null default now()
);
alter table public.drive_media_seen enable row level security;
revoke all on public.drive_media_seen from public, anon, authenticated;

-- Maç kodundan maç: tek eşleşme yoksa null.
create or replace function public.drive_match_by_code(p_code text)
returns uuid
language sql
stable
security definer
set search_path to ''
as $function$
  select case when count(*) = 1 then min(id::text)::uuid end
    from public.matches
   where deleted_at is null
     and length(p_code) = 6
     and replace(id::text, '-', '') like lower(p_code) || '%'
$function$;
revoke all on function public.drive_match_by_code(text) from public, anon, authenticated;

insert into public.app_private_settings (key, value) values
  ('drive_root_folder_id', '1IZwTvn9pHuC5qMRfnX08-y5YlsJ9Y1jl'),
  ('drive_sync_secret', replace(gen_random_uuid()::text, '-', ''))
on conflict (key) do nothing;

create or replace function public.drive_sync_tick()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_secret text;
begin
  select value into v_secret from public.app_private_settings
   where key = 'drive_sync_secret';
  if v_secret is null then
    return;
  end if;
  perform net.http_post(
    url := 'https://qxdjebzszikeslobrozf.supabase.co/functions/v1/drive-sync',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-sync-secret', v_secret
    ),
    timeout_milliseconds := 120000
  );
exception when others then
  raise warning 'drive_sync_tick: %', sqlerrm;
end;
$$;
revoke all on function public.drive_sync_tick() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'drive-sync';
select cron.schedule('drive-sync', '*/15 * * * *', 'select public.drive_sync_tick()');
