-- Elle yazılan habere ayrı başlık (headline) ve tür etiketi (kicker).
-- Eski sürümler content'ten okumaya devam eder (content = başlık + boş satır + metin).
alter table public.news add column if not exists kicker text;
alter table public.news drop constraint if exists news_kicker_chk;
alter table public.news add constraint news_kicker_chk
  check (kicker is null or kicker in ('DUYURU','TRANSFER','MAÇ GÜNÜ','GENEL'));
alter table public.news drop constraint if exists news_manual_headline_len_chk;
alter table public.news add constraint news_manual_headline_len_chk
  check (auto_kind is not null or headline is null or char_length(headline) <= 90) not valid;

-- Bildirim başlığı: haberin başlığı varsa o; yoksa eski metin.
do $$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'news_push_notify';
  v_def := replace(v_def,
    $a$coalesce(v_name, 'Turnuva') || ' · Yeni haber',
    left(regexp_replace(coalesce(new.content, ''), '\s+', ' ', 'g'), 120),$a$,
    $b$coalesce(v_name, 'Turnuva') || ' · ' || coalesce(nullif(btrim(new.headline), ''), 'Yeni haber'),
    left(regexp_replace(case
         when nullif(btrim(new.headline), '') is null then coalesce(new.content, '')
         else coalesce(nullif(regexp_replace(coalesce(new.content, ''), '^[^\n]*\n+', ''), ''), new.content, '')
       end, '\s+', ' ', 'g'), 120),$b$);
  execute v_def;
end $$;
