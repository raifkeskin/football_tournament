-- Uygulama içi bildirimler (zil): push_send ile giden her bildirim alıcının
-- kutusuna da yazılır; telefon bildirimini açmamış kişi de zilde görür.
-- Tür ve ilgili kayıt etiketten çıkarılır (result-/schedule-/reminder-
-- <maç>, news-<haber>, penalty-<ceza>).

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text,
  kind text,
  ref_id uuid,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);
create index if not exists notifications_user_unread_idx
  on public.notifications (user_id) where read_at is null;

alter table public.notifications enable row level security;

drop policy if exists notifications_own_read on public.notifications;
create policy notifications_own_read on public.notifications
  for select to authenticated using (user_id = auth.uid());

-- Okundu: verilenler ya da (boşsa) hepsi.
create or replace function public.mark_notifications_read(p_ids uuid[] default null)
returns void
language sql
security definer
set search_path to ''
as $$
  update public.notifications
     set read_at = now()
   where user_id = auth.uid()
     and read_at is null
     and (p_ids is null or id = any (p_ids));
$$;

create or replace function public.my_unread_notification_count()
returns integer
language sql
stable
security definer
set search_path to ''
as $$
  select count(*)::integer from public.notifications
   where user_id = auth.uid() and read_at is null;
$$;

revoke all on function public.mark_notifications_read(uuid[]) from public, anon;
revoke all on function public.my_unread_notification_count() from public, anon;
grant execute on function public.mark_notifications_read(uuid[]) to authenticated;
grant execute on function public.my_unread_notification_count() to authenticated;

-- Gönderim: önce kutulara yazar, sonra (aboneliği olan varsa) telefona.
create or replace function public.push_send(
  p_user_ids uuid[],
  p_title text,
  p_body text,
  p_url text default '/',
  p_tag text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret text;
  v_kind text := nullif(split_part(coalesce(p_tag, ''), '-', 1), '');
  v_ref text := nullif(substr(coalesce(p_tag, ''), length(coalesce(v_kind, '')) + 2), '');
begin
  if p_user_ids is null then
    return;
  end if;

  begin
    insert into public.notifications (user_id, title, body, kind, ref_id)
    select distinct u, p_title, p_body, v_kind,
           case when v_ref ~* '^[0-9a-f-]{36}$' then v_ref::uuid end
      from unnest(p_user_ids) u
     where u is not null
       and exists (select 1 from auth.users au where au.id = u);
  exception when others then
    raise warning 'push_send notifications: %', sqlerrm;
  end;

  if not exists (
    select 1 from public.push_subscriptions where user_id = any (p_user_ids)
  ) then
    return;
  end if;
  select value into v_secret from public.app_private_settings where key = 'push_secret';
  if coalesce(v_secret, '') = '' then
    return;
  end if;
  perform net.http_post(
    url := 'https://qxdjebzszikeslobrozf.supabase.co/functions/v1/send-push',
    body := jsonb_build_object(
      'user_ids', to_jsonb(p_user_ids),
      'title', p_title,
      'body', p_body,
      'url', coalesce(p_url, '/'),
      'tag', p_tag
    ),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    )
  );
exception when others then
  raise warning 'push_send: %', sqlerrm;
end;
$$;

revoke all on function public.push_send(uuid[], text, text, text, text) from public, anon, authenticated;

-- 60 günden eski bildirimler her gece silinir.
select cron.schedule('notifications-cleanup', '30 3 * * *',
  $$delete from public.notifications where created_at < now() - interval '60 days'$$);
