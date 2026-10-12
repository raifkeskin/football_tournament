-- Canlı maç verisi Broadcast ile dağıtılır (ölçek: binlerce izleyici).
--
-- postgres_changes'te her değişiklik her abone için ayrı yetki sorgusundan
-- geçer (1 gol × 2.000 izleyici = 2.000 sorgu). Broadcast'te tetikleyici tek
-- mesaj üretir; Realtime sunucusu veritabanına dokunmadan konuya bağlı herkese
-- dağıtır. Yetki yalnızca konuya katılırken bir kez kontrol edilir.
--
-- Konular (özel kanal; realtime.messages RLS):
--   match:<maç id>    matches, match_events, match_rosters  (maç detayı)
--   season:<sezon id> matches, match_events                 (fikstür, puan
--                                                            durumu, istatistik)
--   league:<turnuva>  matches                               (ana sayfa: günün
--                                                            maçları)
-- Esame yalnız maç konusuna gider (toplu kayıt binlerce kişiye mesaj olmasın).
-- Eski uygulama sürümleri için postgres_changes yayını olduğu gibi kalır.

create or replace function public.broadcast_match_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_match uuid;
  v_season uuid;
  v_league uuid;
  v_topics text[] := '{}';
  t text;
begin
  if tg_op = 'DELETE' then r := old; else r := new; end if;

  if tg_table_name = 'matches' then
    v_match := r.id;
    v_season := r.season_id;
    v_league := coalesce(
      r.league_id,
      (select s.league_id from public.seasons s where s.id = r.season_id)
    );
  elsif tg_table_name = 'match_events' then
    v_match := r.match_id;
    v_season := r.season_id;
  else
    v_match := r.match_id;
  end if;

  if v_match is not null then v_topics := v_topics || ('match:' || v_match); end if;
  if v_season is not null then v_topics := v_topics || ('season:' || v_season); end if;
  if v_league is not null then v_topics := v_topics || ('league:' || v_league); end if;

  foreach t in array v_topics loop
    -- Yayın hatası asıl kaydı (skor, olay) asla bozmasın.
    begin
      perform realtime.broadcast_changes(
        t, tg_table_name, tg_op, tg_table_name, tg_table_schema, new, old
      );
    exception when others then
      raise warning 'broadcast %: %', t, sqlerrm;
    end;
  end loop;
  return null;
end;
$$;

drop trigger if exists broadcast_change on public.matches;
create trigger broadcast_change after insert or update or delete on public.matches
  for each row execute function public.broadcast_match_change();
drop trigger if exists broadcast_change on public.match_events;
create trigger broadcast_change after insert or update or delete on public.match_events
  for each row execute function public.broadcast_match_change();
drop trigger if exists broadcast_change on public.match_rosters;
create trigger broadcast_change after insert or update or delete on public.match_rosters
  for each row execute function public.broadcast_match_change();

-- Konuya katılma (dinleme) yetkisi: verinin kendisini görebilen herkes.
-- İstemciler bu konulara mesaj gönderemez (insert politikası yok).
drop policy if exists match_topics_read on realtime.messages;
create policy match_topics_read on realtime.messages
  for select to anon, authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and (
      (realtime.topic() ~ '^match:[0-9a-f-]{36}$'
        and public.can_view_match(substr(realtime.topic(), 7)::uuid))
      or (realtime.topic() ~ '^season:[0-9a-f-]{36}$'
        and public.can_view_season(substr(realtime.topic(), 8)::uuid))
      or (realtime.topic() ~ '^league:[0-9a-f-]{36}$'
        and public.can_view_league(substr(realtime.topic(), 8)::uuid))
    )
  );
