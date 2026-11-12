-- Kişisel Verileri Saklama ve İmha Politikası: periyodik imha (ayda bir).
-- Kullanıcının profil/turnuva verilerine dokunmaz (goller, kadrolar,
-- istatistikler, onay kayıtları kalır). Yalnız zamanla biriken teknik ve
-- geçici kayıtlar silinir:
--   * hata kayıtları (app_errors)            son görülme > 1 yıl
--   * sorun bildirimi / öneri (app_feedback)  > 1 yıl
--   * yorum şikâyetleri                       > 1 yıl
--   * sonuçlanmış hesap başvuruları            > 1 yıl
--   * kimlik işlem kayıtları (identity_events) > 1 yıl
--   * sonuçlanmış kimlik eşleşme talepleri     > 30 gün (kart ad/soyad/doğum)
--   * bekleyen kimlik ibrazı (açık TC)         > 90 gün
--   * kullanılmayan bildirim abonelikleri      güncellenmeme > 1 yıl
--   * cihaz sayımı kayıtları (app_clients)     son görülme > 1 yıl
-- Her çalışma retention_log'a yazılır (imha kaydı).

create table if not exists public.retention_log (
  id bigint generated always as identity primary key,
  ran_at timestamptz not null default now(),
  counts jsonb not null
);
alter table public.retention_log enable row level security;
revoke all on public.retention_log from anon, authenticated;

create or replace function public.retention_purge()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v jsonb := '{}'::jsonb;
  n integer;
begin
  delete from public.app_errors where last_seen < now() - interval '1 year';
  get diagnostics n = row_count; v := v || jsonb_build_object('app_errors', n);

  delete from public.app_feedback where created_at < now() - interval '1 year';
  get diagnostics n = row_count; v := v || jsonb_build_object('app_feedback', n);

  delete from public.news_comment_reports where created_at < now() - interval '1 year';
  get diagnostics n = row_count; v := v || jsonb_build_object('news_comment_reports', n);

  delete from public.account_requests
   where status in ('approved', 'rejected')
     and coalesce(reviewed_at, updated_at, created_at) < now() - interval '1 year';
  get diagnostics n = row_count; v := v || jsonb_build_object('account_requests', n);

  delete from public.identity_events where created_at < now() - interval '1 year';
  get diagnostics n = row_count; v := v || jsonb_build_object('identity_events', n);

  delete from public.identity_verify_requests
   where status is distinct from 'pending'
     and coalesce(decided_at, created_at) < now() - interval '30 days';
  get diagnostics n = row_count; v := v || jsonb_build_object('identity_verify_requests', n);

  delete from public.identity_pending where requested_at < now() - interval '90 days';
  get diagnostics n = row_count; v := v || jsonb_build_object('identity_pending', n);

  delete from public.push_subscriptions
   where coalesce(updated_at, created_at) < now() - interval '1 year';
  get diagnostics n = row_count; v := v || jsonb_build_object('push_subscriptions', n);

  delete from public.app_clients where last_seen < now() - interval '1 year';
  get diagnostics n = row_count; v := v || jsonb_build_object('app_clients', n);

  insert into public.retention_log (counts) values (v);
  return v;
end;
$$;

revoke all on function public.retention_purge() from public, anon, authenticated;

-- Her ayın 1'i 04:23 (UTC).
select cron.schedule(
  'retention-purge',
  '23 4 1 * *',
  $cron$select public.retention_purge()$cron$
);
