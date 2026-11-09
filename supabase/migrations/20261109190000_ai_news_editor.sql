-- Spor editörü haberi: maç öncesi ve maç sonrası otomatik haberin metnini
-- Gemini yazar (Yapay Zekâ Yönetimi'nden kapalı / Flash / Pro).
--  * ai_news_pre_mode / ai_news_post_mode: off | flash | pro (varsayılan off).
--  * news.deck: spot cümlesi (boş = kurallarla yazılan spot).
--  * news.editor_meta: üretim kaydı (veri özeti, model, yazılan metin); elle
--    düzenlenmiş haberin üzerine yazılmasın ve aynı veriyle yeniden üretim
--    yapılmasın diye kullanılır.
--  * Manşet ve metin mevcut news.headline / news.article alanlarına yazılır
--    (sorumlunun elle düzenlediği alanlar; eski sürümler de görür).
--  * news tetikleyicisi, ayar açıksa news-editor işlevini çağırır.

insert into public.app_private_settings (key, value) values
  ('ai_news_pre_mode', 'off'),
  ('ai_news_post_mode', 'off')
on conflict (key) do nothing;

alter table public.news
  add column if not exists deck text,
  add column if not exists editor_meta jsonb;
alter table public.news drop constraint if exists news_deck_len;
alter table public.news add constraint news_deck_len
  check (deck is null or char_length(deck) between 1 and 600);

-- Admin ayarları ----------------------------------------------------------------
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
                 'ai_clip_scan_limit', 'ai_news_pre_mode',
                 'ai_news_post_mode');
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
    or (p_key in ('ai_news_pre_mode', 'ai_news_post_mode')
        and p_value in ('off', 'flash', 'pro'))
    or (p_key in ('ai_esame_read_limit', 'ai_clip_scan_limit')
        and p_value ~ '^[0-9]{1,2}$' and p_value::int between 1 and 20)
  ) then
    raise exception 'Geçersiz seçim.';
  end if;
  insert into public.app_private_settings (key, value, updated_at)
  values (p_key, p_value, now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
end $$;

-- İşlem listesi: haber yazımı her çağrı ayrı işlem ('news') -----------------------
create or replace function public.ai_usage_list(p_from timestamptz, p_to timestamptz)
returns table (
  at timestamptz,
  kind text,
  model text,
  match_id uuid,
  home_name text,
  away_name text,
  league_name text,
  cost_usd numeric,
  cost_try numeric
)
language plpgsql
stable security definer
set search_path to ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Yetkiniz yok.';
  end if;
  return query
  with ops as (
    select max(l.created_at) as at,
           case when l.purpose = 'esame' then 'esame'
                when l.purpose in ('news_pre', 'news_post') then l.purpose
                else 'clips' end as kind,
           max(l.model) as model,
           l.match_id,
           sum(l.cost_usd) as cost_usd,
           sum(l.cost_try) as cost_try
      from public.ai_usage_log l
     where l.created_at >= p_from and l.created_at < p_to
     group by case when l.purpose in ('esame', 'news_pre', 'news_post')
                   then l.id::text
                   else coalesce(l.match_id::text, '') || '|' ||
                        ((l.created_at at time zone 'Europe/Istanbul')::date)::text
              end,
              case when l.purpose = 'esame' then 'esame'
                   when l.purpose in ('news_pre', 'news_post') then l.purpose
                   else 'clips' end,
              l.match_id
  )
  select o.at, o.kind, o.model, o.match_id,
         th.name::text, ta.name::text, lg.name::text,
         round(o.cost_usd, 5), round(o.cost_try, 2)
    from ops o
    left join public.matches m on m.id = o.match_id
    left join public.teams th on th.id = m.home_team_id
    left join public.teams ta on ta.id = m.away_team_id
    left join public.seasons s on s.id = m.season_id
    left join public.leagues lg on lg.id = s.league_id
   order by o.at desc;
end $$;

-- Tetikleyici: haber oluşunca / verisi değişince news-editor çağrılır ---------------
-- (aynı veriyle yeniden üretimi işlev kendisi engeller; ayar kapalıysa hiçbir şey olmaz)
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
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', v_secret
    )
  );
  return new;
exception when others then
  raise warning 'news_editor_notify: %', sqlerrm;
  return new;
end $$;

drop trigger if exists news_editor_notify on public.news;
create trigger news_editor_notify
  after insert or update of auto_data on public.news
  for each row execute function public.news_editor_notify();

revoke all on function public.news_editor_notify() from public, anon, authenticated;
