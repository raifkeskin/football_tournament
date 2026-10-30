-- Haberlere tepki (tribün) ve yorum.
-- Tepki: haber başına kişi başı tek tepki; 3 yuva (1-3), etiketleri haber
-- türüne göre uygulamada. Sayılar news.reactions'ta ({"1": 18, ...}).
-- Yorum: gönderilirken denetlenir. Açık küfür kaydedilmez; şüpheli olan
-- sorumlunun (admin, kurucu başkan, bölge sorumlusu) onayına düşer; temiz
-- olan hemen yayınlanır. 3 şikâyet alan yorum yeniden onaya döner.
-- Kapalıyken (app_settings.news_comments_enabled) yalnız admin kullanır.

alter table public.news
  add column if not exists reactions jsonb not null default '{}'::jsonb,
  add column if not exists comment_count integer not null default 0;

create or replace function public.news_comments_on()
returns boolean
language sql
stable security definer
set search_path to ''
as $$
  select public.is_admin() or coalesce((
    select value = 'true'::jsonb from public.app_settings
     where key = 'news_comments_enabled'), false)
$$;

-- ── Tepkiler ────────────────────────────────────────────────────────────

create table if not exists public.news_reactions (
  news_id uuid not null references public.news(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  slot smallint not null check (slot between 1 and 3),
  created_at timestamptz not null default now(),
  primary key (news_id, user_id)
);
create index if not exists news_reactions_user_idx
  on public.news_reactions (user_id);
alter table public.news_reactions enable row level security;

drop policy if exists news_reactions_read on public.news_reactions;
create policy news_reactions_read on public.news_reactions
  for select to authenticated using (user_id = auth.uid());

create or replace function public.news_reactions_sync()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_news uuid := coalesce(new.news_id, old.news_id);
begin
  update public.news n
     set reactions = coalesce((
       select jsonb_object_agg(slot::text, c) from (
         select slot, count(*) c from public.news_reactions
          where news_id = v_news group by slot) x), '{}'::jsonb)
   where n.id = v_news;
  return null;
end;
$$;

drop trigger if exists news_reactions_sync on public.news_reactions;
create trigger news_reactions_sync
  after insert or update or delete on public.news_reactions
  for each row execute function public.news_reactions_sync();

-- Tepki ver / değiştir; p_slot null ya da aynı tepki: geri al.
create or replace function public.news_react(p_news_id uuid, p_slot int)
returns int
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_old int;
begin
  if v_uid is null then
    raise exception 'Tepki vermek için giriş yapın.';
  end if;
  if not public.news_comments_on() then
    raise exception 'Bu özellik henüz açık değil.';
  end if;
  if not exists (select 1 from public.news where id = p_news_id
                   and is_published) then
    raise exception 'Haber bulunamadı.';
  end if;
  select slot into v_old from public.news_reactions
   where news_id = p_news_id and user_id = v_uid;
  if p_slot is null or v_old = p_slot then
    delete from public.news_reactions
     where news_id = p_news_id and user_id = v_uid;
    return null;
  end if;
  if p_slot not between 1 and 3 then
    raise exception 'Geçersiz tepki.';
  end if;
  insert into public.news_reactions (news_id, user_id, slot)
  values (p_news_id, v_uid, p_slot)
  on conflict (news_id, user_id)
  do update set slot = excluded.slot, created_at = now();
  return p_slot;
end;
$$;

-- ── Yorumlar ────────────────────────────────────────────────────────────

create table if not exists public.news_comments (
  id uuid primary key default gen_random_uuid(),
  news_id uuid not null references public.news(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  author_name text not null,
  author_team text,
  body text not null check (char_length(body) between 1 and 500),
  status text not null default 'published'
    check (status in ('published', 'pending', 'rejected')),
  flag_reason text,
  report_count integer not null default 0,
  created_at timestamptz not null default now(),
  reviewed_by uuid,
  reviewed_at timestamptz
);
create index if not exists news_comments_news_idx
  on public.news_comments (news_id, created_at desc);
create index if not exists news_comments_pending_idx
  on public.news_comments (status) where status = 'pending';
create index if not exists news_comments_user_idx
  on public.news_comments (user_id, created_at desc);
alter table public.news_comments enable row level security;

-- Yayındaki yorumu haberi görebilen herkes; kendi yorumunu yazan;
-- tümünü haberin sorumlusu görür. Yazma yalnız fonksiyonlarla.
drop policy if exists news_comments_read on public.news_comments;
create policy news_comments_read on public.news_comments
  for select using (
    (status = 'published' and exists (
      select 1 from public.news n where n.id = news_id))
    or user_id = auth.uid()
    or exists (
      select 1 from public.news n
       where n.id = news_id and public.owns_news(n.season_id, n.region_id))
  );

create table if not exists public.news_comment_reports (
  comment_id uuid not null references public.news_comments(id)
    on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);
alter table public.news_comment_reports enable row level security;

create table if not exists public.news_comment_bans (
  user_id uuid primary key references auth.users(id) on delete cascade,
  banned_by uuid,
  created_at timestamptz not null default now()
);
alter table public.news_comment_bans enable row level security;

create or replace function public.news_comments_sync_count()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_news uuid := coalesce(new.news_id, old.news_id);
begin
  update public.news n
     set comment_count = (select count(*) from public.news_comments
                           where news_id = v_news and status = 'published')
   where n.id = v_news;
  return null;
end;
$$;

drop trigger if exists news_comments_sync_count on public.news_comments;
create trigger news_comments_sync_count
  after insert or delete or update of status on public.news_comments
  for each row execute function public.news_comments_sync_count();

-- Metni denetime hazırlar: Türkçe küçük harf, rakam/simge benzerleri
-- harfe (4→a, 0→o, $→s…), tekrar eden harfler teke ("amkkk" → "amk").
create or replace function public.comment_fold(p text)
returns text
language sql
immutable
set search_path to ''
as $$
  select regexp_replace(
    translate(
      lower(replace(replace(coalesce(p, ''), 'İ', 'i'), 'I', 'ı')),
      '4@013$5!7',
      'aaoiessit'),
    '(.)\1+', '\1', 'g')
$$;

-- 'blocked': açık küfür/hakaret; 'pending:<sebep>': onaya; 'ok'.
create or replace function public.comment_moderate(p_body text)
returns text
language plpgsql
stable
set search_path to ''
as $$
declare
  v_fold text := public.comment_fold(p_body);
  -- Kelime içi nokta/yıldız/tire atılır ("a.q", "s*k" → "aq", "sk").
  v_tokens text[] := regexp_split_to_array(
    regexp_replace(v_fold, '[.*_\-]', '', 'g'), '[^a-zçğıöşü]+');
  -- Yalnız harfler, bitişik: boşlukla bölünmüş küfrü yakalar.
  v_flat text := regexp_replace(v_fold, '[^a-zçğıöşü]', '', 'g');
  v_tok text;
  v_letters int;
  v_upper int;
  -- Tam kelime eşleşmesi.
  c_exact constant text[] := array[
    'aq', 'amk', 'amq', 'mk', 'sg', 'sk', 'oç', 'oc', 'piç', 'pic',
    'sik', 'göt', 'got', 'sktr', 'sktir', 'aw', 'awk', 'amcık', 'amcik', 'yarak',
    'yarrak', 'ibne', 'ipne', 'gavat', 'kahpe', 'pezo', 'yavşak', 'yavsak',
    'şerefsiz', 'serefsiz', 'orosbu', 'oruspu', 'kaltak', 'puşt', 'pust'];
  -- Bu köklerle başlayan kelime (tekrar eden harfler teke indiği için
  -- "yarrak" → "yarak"; "sıkıntı"yı Türkçe karaktersiz yazan takılmasın
  -- diye "sik" yalnız tam kelime).
  c_prefix constant text[] := array[
    'siktir', 'sikt', 'siker', 'sikey', 'sikiy', 'sikim', 'sikik', 'sikiş',
    'sikis', 'amına', 'amina', 'amını', 'amini', 'amcığ', 'amcig',
    'orospu', 'orosbu', 'yarak', 'yarağ', 'pezeven', 'göte',
    'götün', 'götveren', 'gotveren', 'ibneler', 'kahpe', 'piçler', 'yavşa',
    'yavsa', 'şerefsi', 'serefsi', 'gavatl', 'puşt', 'dalyarak', 'fahişe', 'fahise', 'sürtük', 'surtuk'];
  -- Bitişik metinde geçerse onaya (yanlış alarm olabilir).
  c_flat constant text[] := array[
    'amına', 'amina', 'siktir', 'orospu', 'yarak', 'pezeven', 'sikerim',
    'sikiyim', 'anani', 'ananı', 'bacını', 'bacini'];
  -- Hakaret olabilecek kelimeler: onaya.
  c_soft constant text[] := array[
    'salak', 'aptal', 'gerizekalı', 'gerizekali', 'mal', 'dangalak',
    'ahmak', 'haysiyetsiz', 'onursuz', 'şike', 'sike', 'şikeci', 'hırsız',
    'hirsiz', 'satıldı', 'satildi', 'rüşvet', 'rusvet', 'köpek', 'kopek',
    'eşek', 'esek', 'hayvan', 'ayı', 'öküz', 'okuz', 'lavuk', 'hıyar',
    'hiyar', 'beyinsiz', 'aşağılık', 'asagilik', 'kaşar', 'kasar'];
begin
  foreach v_tok in array v_tokens loop
    continue when v_tok = '';
    if v_tok = any (c_exact)
       or exists (select 1 from unnest(c_prefix) p
                   where v_tok like p || '%') then
      return 'blocked';
    end if;
  end loop;
  if exists (select 1 from unnest(c_flat) f where v_flat like '%' || f || '%')
  then
    return 'pending:Küfür olabilir';
  end if;
  foreach v_tok in array v_tokens loop
    if v_tok = any (c_soft) then
      return 'pending:"' || v_tok || '"';
    end if;
  end loop;
  if p_body ~* '(https?://|www\.|\.com|\.net|\.org|t\.me/)' then
    return 'pending:Bağlantı';
  end if;
  if regexp_replace(p_body, '\D', '', 'g') ~ '\d{7,}' then
    return 'pending:Telefon numarası';
  end if;
  if p_body ~ '\*' then
    return 'pending:Gizlenmiş kelime';
  end if;
  v_letters := char_length(regexp_replace(p_body, '[^[:alpha:]]', '', 'g'));
  v_upper := char_length(regexp_replace(p_body, '[^A-ZÇĞİÖŞÜ]', '', 'g'));
  if v_letters >= 10 and v_upper::numeric / v_letters > 0.7 then
    return 'pending:Tamamı büyük harf';
  end if;
  return 'ok';
end;
$$;

-- Haberin sorumlularına bildirim (onay bekleyen yorum).
create or replace function public.news_comment_notify(p_comment uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  c record;
  v_league uuid;
  v_name text;
  v_ids uuid[];
begin
  select nc.*, n.season_id, n.region_id into c
    from public.news_comments nc join public.news n on n.id = nc.news_id
   where nc.id = p_comment;
  if c.id is null then return; end if;
  select s.league_id, l.name into v_league, v_name
    from public.seasons s join public.leagues l on l.id = s.league_id
   where s.id = c.season_id;
  if v_league is null or public.league_push_muted(v_league) then
    return;
  end if;
  select array_agg(distinct u) into v_ids from (
    select a.user_id as u from public.admins a
    union select o.user_id from public.league_owners o
      where o.league_id = v_league
    union select ro.user_id from public.region_owners ro
      join public.season_regions r on r.id = ro.region_id
     where r.season_id = c.season_id
       and (c.region_id is null or r.id = c.region_id)
  ) x where u is not null and u <> c.user_id;
  perform public.push_send(
    v_ids,
    coalesce(v_name, 'Turnuva') || ' · Yorum onayını bekliyor',
    c.author_name || ': ' || left(c.body, 90),
    '/',
    'newscomment-' || v_league
  );
end;
$$;

-- Yorum yaz. Döner: 'published' | 'pending'. Açık küfürde hata.
create or replace function public.news_comment_add(p_news_id uuid, p_body text)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_body text := btrim(regexp_replace(coalesce(p_body, ''), '\s+\n', E'\n', 'g'));
  v_news record;
  v_player uuid;
  v_name text;
  v_team text;
  v_mod text;
  v_status text := 'published';
  v_reason text;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'Yorum yazmak için giriş yapın.';
  end if;
  if not public.news_comments_on() then
    raise exception 'Bu özellik henüz açık değil.';
  end if;
  if exists (select 1 from public.news_comment_bans where user_id = v_uid)
  then
    raise exception 'Yorum yazma izniniz kaldırıldı.';
  end if;
  if char_length(v_body) = 0 then
    raise exception 'Yorum boş olamaz.';
  end if;
  if char_length(v_body) > 500 then
    raise exception 'Yorum en fazla 500 karakter olabilir.';
  end if;
  select id, season_id into v_news from public.news
   where id = p_news_id and is_published;
  if v_news.id is null then
    raise exception 'Haber bulunamadı.';
  end if;

  v_mod := public.comment_moderate(v_body);
  if v_mod = 'blocked' then
    raise exception 'Bu yorum kurallara uymuyor; küfür ve hakaret içeren yorumlar yayınlanmaz.';
  end if;
  if v_mod like 'pending:%' then
    v_status := 'pending';
    v_reason := substr(v_mod, 9);
  elsif (select count(*) from public.news_comments
          where user_id = v_uid and created_at > now() - interval '10 minutes'
        ) >= 5 then
    v_status := 'pending';
    v_reason := 'Kısa sürede çok yorum';
  end if;

  -- Ad soyad: futbolcu profili; yoksa hesap adı.
  v_player := public.my_player_id();
  select nullif(btrim(coalesce(p.name, '') || ' ' || coalesce(p.surname, '')), '')
    into v_name from public.players p where p.id = v_player;
  v_name := coalesce(v_name, public.person_display_name(v_uid));
  if v_player is not null then
    select t.name into v_team
      from public.season_team_players stp
      join public.teams t on t.id = stp.team_id
     where stp.player_id = v_player and stp.season_id = v_news.season_id
       and stp.is_active is not false
     limit 1;
  end if;

  insert into public.news_comments
    (news_id, user_id, author_name, author_team, body, status, flag_reason)
  values (p_news_id, v_uid, v_name, v_team, v_body, v_status, v_reason)
  returning id into v_id;
  if v_status = 'pending' then
    perform public.news_comment_notify(v_id);
  end if;
  return v_status;
end;
$$;

-- Kendi yorumunu siler (sorumlu da silebilir).
create or replace function public.news_comment_delete(p_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  delete from public.news_comments c
   using public.news n
   where c.id = p_id and n.id = c.news_id
     and (c.user_id = auth.uid() or public.owns_news(n.season_id, n.region_id));
end;
$$;

-- Şikâyet: 3 farklı kişi şikâyet edince yorum onaya döner.
create or replace function public.news_comment_report(p_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_count int;
begin
  if v_uid is null then
    raise exception 'Şikâyet için giriş yapın.';
  end if;
  insert into public.news_comment_reports (comment_id, user_id)
  select id, v_uid from public.news_comments
   where id = p_id and status = 'published' and user_id <> v_uid
  on conflict do nothing;
  if not found then return; end if;
  update public.news_comments
     set report_count = report_count + 1
   where id = p_id
  returning report_count into v_count;
  if v_count >= 3 then
    update public.news_comments
       set status = 'pending', flag_reason = 'Şikâyet (' || v_count || ' kişi)'
     where id = p_id and status = 'published';
    if found then
      perform public.news_comment_notify(p_id);
    end if;
  end if;
end;
$$;

-- Sorumlu kararı: 'publish' | 'reject' | 'ban' (reddet + yorum yasağı).
create or replace function public.news_comment_review(p_id uuid, p_action text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  c record;
begin
  select nc.id, nc.user_id, n.season_id, n.region_id into c
    from public.news_comments nc join public.news n on n.id = nc.news_id
   where nc.id = p_id;
  if c.id is null then
    raise exception 'Yorum bulunamadı.';
  end if;
  if not public.owns_news(c.season_id, c.region_id) then
    raise exception 'Bu yorumu onaylama yetkiniz yok.';
  end if;
  if p_action not in ('publish', 'reject', 'ban') then
    raise exception 'Geçersiz işlem.';
  end if;
  update public.news_comments
     set status = case p_action when 'publish' then 'published'
                                else 'rejected' end,
         reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_id;
  if p_action = 'ban' then
    insert into public.news_comment_bans (user_id, banned_by)
    values (c.user_id, auth.uid())
    on conflict (user_id) do nothing;
  end if;
end;
$$;

revoke all on function public.news_react(uuid, int) from public, anon;
revoke all on function public.news_comment_add(uuid, text) from public, anon;
revoke all on function public.news_comment_delete(uuid) from public, anon;
revoke all on function public.news_comment_report(uuid) from public, anon;
revoke all on function public.news_comment_review(uuid, text) from public, anon;
revoke all on function public.news_comment_notify(uuid) from public, anon, authenticated;
grant execute on function public.news_react(uuid, int) to authenticated;
grant execute on function public.news_comment_add(uuid, text) to authenticated;
grant execute on function public.news_comment_delete(uuid) to authenticated;
grant execute on function public.news_comment_report(uuid) to authenticated;
grant execute on function public.news_comment_review(uuid, text) to authenticated;
grant select on public.news_comments to anon, authenticated;
grant select on public.news_reactions to authenticated;
