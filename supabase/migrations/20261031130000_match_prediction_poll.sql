-- Maç önü tahmin anketi: "Kim kazanır?" (ev / berabere / deplasman).
-- Kişi başı tek oy; maç başlayana kadar değiştirilebilir. Sayılar maçın
-- maç önü ve maç sonucu haberlerinin news.poll alanına yazılır
-- ({"home":n,"draw":n,"away":n}); boşsa ankette oy yok demektir.
-- Kapı: news_comments_on() (tepki/yorumla aynı).

alter table public.news
  add column if not exists poll jsonb not null default '{}'::jsonb;

create table if not exists public.match_predictions (
  match_id uuid not null references public.matches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  pick text not null check (pick in ('home', 'draw', 'away')),
  created_at timestamptz not null default now(),
  primary key (match_id, user_id)
);
create index if not exists match_predictions_user_idx
  on public.match_predictions (user_id);
alter table public.match_predictions enable row level security;

drop policy if exists match_predictions_read on public.match_predictions;
create policy match_predictions_read on public.match_predictions
  for select to authenticated using (user_id = auth.uid());

create or replace function public.match_poll_counts(p_match_id uuid)
returns jsonb
language sql
stable security definer
set search_path to ''
as $$
  select coalesce(jsonb_object_agg(pick, c), '{}'::jsonb) from (
    select pick, count(*) c from public.match_predictions
     where match_id = p_match_id group by pick) x
$$;

create or replace function public.match_predictions_sync()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_match uuid := coalesce(new.match_id, old.match_id);
begin
  update public.news n
     set poll = public.match_poll_counts(v_match)
   where n.match_id = v_match
     and n.auto_kind in ('match_preview', 'match_result');
  return null;
end;
$$;

drop trigger if exists match_predictions_sync on public.match_predictions;
create trigger match_predictions_sync
  after insert or update or delete on public.match_predictions
  for each row execute function public.match_predictions_sync();

-- Maç sonucu haberi oluşurken anketin (donmuş) sonucunu taşır.
create or replace function public.news_poll_fill()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.match_id is not null
     and new.auto_kind in ('match_preview', 'match_result') then
    new.poll := public.match_poll_counts(new.match_id);
  end if;
  return new;
end;
$$;

drop trigger if exists news_poll_fill on public.news;
create trigger news_poll_fill
  before insert on public.news
  for each row execute function public.news_poll_fill();

-- Oylama açık mı: maç başlamadı ve başlama saati gelmedi (İstanbul saati).
create or replace function public.match_poll_open(p_match_id uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $$
  select exists (
    select 1 from public.matches m
     where m.id = p_match_id
       and m.status = 'notStarted'
       and m.match_date is not null
       and case
             when coalesce(m.match_time, '') ~ '^\d{1,2}:\d{2}$' then
               (m.match_date + m.match_time::time)
                 at time zone 'Europe/Istanbul' > now()
             else m.match_date >= (now() at time zone 'Europe/Istanbul')::date
           end)
$$;

-- Oy ver / değiştir. Aynı seçim: değişiklik yok.
create or replace function public.match_predict(p_match_id uuid, p_pick text)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Oy vermek için giriş yapın.';
  end if;
  if not public.news_comments_on() then
    raise exception 'Bu özellik henüz açık değil.';
  end if;
  if p_pick not in ('home', 'draw', 'away') then
    raise exception 'Geçersiz seçim.';
  end if;
  if not public.match_poll_open(p_match_id) then
    raise exception 'Maç başladı, oylama kapandı.';
  end if;
  insert into public.match_predictions (match_id, user_id, pick)
  values (p_match_id, v_uid, p_pick)
  on conflict (match_id, user_id)
  do update set pick = excluded.pick, created_at = now()
  where public.match_predictions.pick <> excluded.pick;
  return p_pick;
end;
$$;

revoke all on function public.match_predict(uuid, text) from public, anon;
grant execute on function public.match_predict(uuid, text) to authenticated;
revoke all on function public.match_poll_counts(uuid) from public, anon;
grant execute on function public.match_poll_open(uuid) to anon, authenticated;
grant select on public.match_predictions to authenticated;
