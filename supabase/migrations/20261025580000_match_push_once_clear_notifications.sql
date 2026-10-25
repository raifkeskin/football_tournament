-- Maç başladı / Maç sonucu bildirimi her maç için bir kez gider: maç
-- bitirildikten sonra yeniden açılıp kapatılırsa tekrar gönderilmez.
create table if not exists public.match_push_log (
  match_id uuid not null references public.matches(id) on delete cascade,
  kind text not null,
  sent_at timestamptz not null default now(),
  primary key (match_id, kind)
);
alter table public.match_push_log enable row level security;
revoke all on public.match_push_log from anon, authenticated;

-- Önceden gönderilmiş olanlar (bildirim listesinden).
insert into public.match_push_log (match_id, kind, sent_at)
select n.ref_id, n.kind, min(n.created_at)
  from public.notifications n
  join public.matches m on m.id = n.ref_id
 where (n.kind = 'result' and n.title = 'Maç sonucu')
    or (n.kind = 'live' and n.title = 'Maç başladı')
 group by 1, 2
on conflict do nothing;

-- İlk çağrıda true (gönder), sonrakilerde false.
create or replace function public.match_push_once(p_match uuid, p_kind text)
returns boolean
language plpgsql
security definer
set search_path to ''
as $$
begin
  insert into public.match_push_log (match_id, kind) values (p_match, p_kind);
  return true;
exception when unique_violation then
  return false;
end;
$$;
revoke all on function public.match_push_once(uuid, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.matches_push_notify()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- Sonuç
  if tg_op = 'UPDATE' and new.status = 'finished'
     and old.status is distinct from 'finished' then
    -- Her maça bir kez: bitir → düzelt → yeniden bitir tekrar göndermez.
    if not public.match_push_once(new.id, 'result') then
      return new;
    end if;
    perform public.push_send(
      public.match_audience(new.id, true),
      'Maç sonucu',
      public.match_score_text(new.id, coalesce(new.home_score, 0), coalesce(new.away_score, 0)),
      '/',
      'result-' || new.id
    );
    return new;
  end if;

  -- Maç başladı
  if tg_op = 'UPDATE' and new.status = 'live'
     and old.status = 'notStarted' then
    if not public.match_push_once(new.id, 'live') then
      return new;
    end if;
    perform public.push_send(
      public.match_audience(new.id, false),
      'Maç başladı',
      public.match_title(new.id),
      '/',
      'live-' || new.id
    );
    return new;
  end if;

  -- İlk yarı sonucu
  if tg_op = 'UPDATE' and new.status = 'halftime'
     and old.status is distinct from 'halftime' then
    perform public.push_send(
      public.match_audience(new.id, false),
      'İlk yarı sonucu',
      public.match_score_text(new.id, coalesce(new.home_score, 0), coalesce(new.away_score, 0)),
      '/',
      'live-' || new.id
    );
    return new;
  end if;

  -- Tarih / saat belirlendi ya da değişti (yalnızca oynanmamış maç).
  -- Yeni eklenen maçta yalnızca 7 gün içindekiler bildirilir (toplu
  -- fikstür girişinde onlarca bildirim gitmesin).
  if new.status = 'notStarted' and new.match_date is not null
     and coalesce(new.match_time, '') <> ''
     and (
       (tg_op = 'INSERT' and new.match_date <= current_date + 7)
       or (tg_op = 'UPDATE' and (
         new.match_date is distinct from old.match_date
         or new.match_time is distinct from old.match_time))
     ) then
    perform public.push_send(
      public.match_audience(new.id, false),
      case
        when tg_op = 'UPDATE' and old.match_date is not null
          then 'Maç saati değişti'
        else 'Maç planlandı'
      end,
      public.match_title(new.id) || E'\n' ||
        public.tr_match_when(new.match_date, new.match_time),
      '/',
      'schedule-' || new.id
    );
  end if;
  return new;
end;
$function$;


-- Kullanıcı kendi uygulama içi bildirimlerinin hepsini siler.
create or replace function public.clear_my_notifications()
returns void
language sql
security definer
set search_path to ''
as $$
  delete from public.notifications where user_id = auth.uid();
$$;
revoke all on function public.clear_my_notifications() from public, anon;
grant execute on function public.clear_my_notifications() to authenticated;

-- Bildirimi listeden silinmiş eski maçlar da gönderilmiş sayılır.
insert into public.match_push_log (match_id, kind)
select id, 'result' from public.matches where status = 'finished'
on conflict do nothing;
insert into public.match_push_log (match_id, kind)
select id, 'live' from public.matches where status <> 'notStarted'
on conflict do nothing;
