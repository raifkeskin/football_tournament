-- Esame yayını: satır başına değil, kayıt (deyim) başına tek mesaj.
--
-- Esame kaydı eski satırları silip yenilerini ekler: 2 takım × ~15 oyuncu ×
-- (silme + ekleme) ≈ 60 satır. Satır tetikleyicisi her satır için maç
-- konusuna ayrı mesaj gönderiyordu; başlama düdüğünden hemen önce, maçı 400
-- kişi açıkken bu ~24.000 mesaj demekti (17 Ekim yük testi).
--
-- Uygulama esame mesajının içeriğini kullanmaz; yalnızca tablo adına ve
-- match_id'ye bakıp listeyi yeniden okur (realtimeChangeSignal, 300 ms
-- birleştirme). Bu yüzden her deyimde, etkilenen her maç için bir "UPDATE"
-- mesajı yeter; yük biçimi broadcast_changes ile aynıdır (eski sürümler de
-- anlar). postgres_changes yayınına (eski APK'lar) dokunulmaz.

create or replace function public.broadcast_roster_statement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_match uuid;
begin
  for v_match in
    select match_id from changed_rows where match_id is not null
    group by match_id
  loop
    -- Yayın hatası esame kaydını asla bozmasın.
    begin
      perform realtime.send(
        jsonb_build_object(
          'operation', 'UPDATE',
          'table', 'match_rosters',
          'schema', 'public',
          'record', jsonb_build_object('match_id', v_match),
          'old_record', jsonb_build_object('match_id', v_match)
        ),
        'match_rosters',
        'match:' || v_match,
        true
      );
    exception when others then
      raise warning 'broadcast match:%: %', v_match, sqlerrm;
    end;
  end loop;
  return null;
end;
$$;

drop trigger if exists broadcast_change on public.match_rosters;

drop trigger if exists broadcast_roster_insert on public.match_rosters;
create trigger broadcast_roster_insert after insert on public.match_rosters
  referencing new table as changed_rows
  for each statement execute function public.broadcast_roster_statement();

drop trigger if exists broadcast_roster_update on public.match_rosters;
create trigger broadcast_roster_update after update on public.match_rosters
  referencing new table as changed_rows
  for each statement execute function public.broadcast_roster_statement();

drop trigger if exists broadcast_roster_delete on public.match_rosters;
create trigger broadcast_roster_delete after delete on public.match_rosters
  referencing old table as changed_rows
  for each statement execute function public.broadcast_roster_statement();
