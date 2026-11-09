-- Spor editörü haberi zamanlaması:
--  * Maç sonrası yazı, haber oluştuktan 7 saat sonra başlar (veriler
--    düzelsin diye); tetikleyici erken çağrıyı atlar, 15 dakikalık
--    zamanlayıcı süresi dolanları işler. Maç öncesi yazı hemen başlar.
--  * Yazı gelince haber onaya düşer (news-editor işlevi 1 saat bekleme
--    koyar); onay bekleyen haber bildirimi güncellemede de gönderilir.
create or replace function public.news_editor_notify()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_mode text;
  v_secret text;
begin
  if new.match_id is null or new.auto_kind not in ('match_result', 'match_preview') then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.auto_data is not distinct from old.auto_data then
    return new;
  end if;
  -- Maç sonrası: 7 saat dolmadan çağrılmaz (zamanlayıcı yapar).
  if new.auto_kind = 'match_result' and new.created_at > now() - interval '7 hours' then
    return new;
  end if;
  select value into v_mode from public.app_private_settings
   where key = case new.auto_kind when 'match_result' then 'ai_news_post_mode'
                                  else 'ai_news_pre_mode' end;
  if coalesce(v_mode, 'off') not in ('flash', 'pro') then
    return new;
  end if;
  select value into v_secret from public.app_private_settings where key = 'push_secret';
  if coalesce(v_secret, '') = '' then
    return new;
  end if;
  perform net.http_post(
    url := 'https://qxdjebzszikeslobrozf.supabase.co/functions/v1/news-editor',
    body := jsonb_build_object('news_id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret)
  );
  return new;
exception when others then
  raise warning 'news_editor_notify: %', sqlerrm;
  return new;
end $$;

create or replace function public.news_editor_tick()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_mode text;
  v_secret text;
  r record;
begin
  select value into v_mode from public.app_private_settings where key = 'ai_news_post_mode';
  if coalesce(v_mode, 'off') not in ('flash', 'pro') then
    return;
  end if;
  select value into v_secret from public.app_private_settings where key = 'push_secret';
  if coalesce(v_secret, '') = '' then
    return;
  end if;
  for r in
    select n.id
      from public.news n
      join public.matches m on m.id = n.match_id
     where n.auto_kind = 'match_result'
       and n.editor_meta is null
       and not n.auto_hidden
       and m.status = 'finished' and m.deleted_at is null
       and n.created_at <= now() - interval '7 hours'
       and n.created_at >= now() - interval '3 days'
     order by n.created_at
     limit 8
  loop
    perform net.http_post(
      url := 'https://qxdjebzszikeslobrozf.supabase.co/functions/v1/news-editor',
      body := jsonb_build_object('news_id', r.id),
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret)
    );
  end loop;
exception when others then
  raise warning 'news_editor_tick: %', sqlerrm;
end $$;
revoke all on function public.news_editor_tick() from public, anon, authenticated;

select cron.unschedule('news-editor-tick')
 where exists (select 1 from cron.job where jobname = 'news-editor-tick');
select cron.schedule('news-editor-tick', '*/15 * * * *', 'select public.news_editor_tick()');

-- Onay bildirimi: haber sonradan onaya düşünce de gider (aynı işlev).
drop trigger if exists news_review_notify_upd on public.news;
create trigger news_review_notify_upd
  after update of pending_until on public.news
  for each row
  when (old.pending_until is null and new.pending_until is not null
        and not coalesce(new.is_published, false))
  execute function public.news_review_notify();
