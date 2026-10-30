-- Onaya düşen haber: admin, turnuvanın kurucu başkanları ve haberin bölge
-- sorumluları bildirim alır (Bildirimler listesi + telefon). Dokununca
-- onay bekleyen haberler açılır (etiket newsreview-<haber>).
create or replace function public.news_review_notify()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_league uuid;
  v_name text;
  v_ids uuid[];
  v_title text;
begin
  if new.pending_until is null or coalesce(new.is_published, false) then
    return new;
  end if;
  select s.league_id, l.name into v_league, v_name
    from public.seasons s join public.leagues l on l.id = s.league_id
   where s.id = new.season_id;
  if v_league is null or public.league_push_muted(v_league) then
    return new;
  end if;
  select array_agg(distinct u) into v_ids from (
    select a.user_id as u from public.admins a
    union select o.user_id from public.league_owners o
      where o.league_id = v_league
    union select ro.user_id from public.region_owners ro
      join public.season_regions r on r.id = ro.region_id
     where r.season_id = new.season_id
       and (new.region_id is null or r.id = new.region_id)
  ) x where u is not null;
  v_title := case new.auto_kind
    when 'week_results' then 'Hafta özeti onayını bekliyor'
    else 'Maç sonucu haberi onayını bekliyor' end;
  perform public.push_send(
    v_ids,
    coalesce(v_name, 'Turnuva') || ' · ' || v_title,
    left(split_part(coalesce(new.content, ''), E'\n', 1), 90)
      || ' · Manşeti düzenleyip yayınla. Onaylanmazsa saat '
      || to_char(new.pending_until at time zone 'Europe/Istanbul', 'HH24:MI')
      || ' olunca kendiliğinden yayınlanır.',
    '/',
    'newsreview-' || new.id
  );
  return new;
end;
$$;

drop trigger if exists news_review_notify on public.news;
create trigger news_review_notify
  after insert on public.news
  for each row execute function public.news_review_notify();
