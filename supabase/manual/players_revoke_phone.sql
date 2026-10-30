-- players gizliliği (2. aşama): telefon ve kimlik no sütunlarının okuma
-- yetkisi kaldırılır.
--
-- ÇALIŞTIRMA ZAMANI: 1.0.5 (telefonu tablodan okumayan sürüm) mağazalarda
-- yayınlanıp kullanıcıların çoğu güncelledikten ve web yeni sürüme
-- geçtikten SONRA. Eski sürümler oyuncuları tüm sütunlarla okuduğu için
-- erken çalıştırılırsa onlarda oyuncu ekranları hata verir.
--
-- Çalıştırma: psql "$(cat ~/.config/football_tournament/db.env)" -f supabase/manual/players_revoke_phone.sql

begin;

-- Admin şifre talepleri görünümü oyuncu adını telefonla buluyordu
-- (sorgulayanın yetkisiyle). Ad, yalnız admine dönen fonksiyonla gelir.
create or replace function public._player_name_by_phone(p_raw text)
returns text
language sql
stable
security definer
set search_path to ''
as $function$
  select nullif(trim(concat_ws(' ', p.name, p.surname)), '')
  from public.players p
  where public.is_admin() and public.phone_raw10(p.phone) = p_raw
  limit 1
$function$;
revoke all on function public._player_name_by_phone(text) from public, anon;
grant execute on function public._player_name_by_phone(text) to authenticated;

create or replace view public.account_requests_view
with (security_invoker = true) as
select r.id, r.phone_raw10, r.kind, r.full_name, r.status, r.created_at,
       r.reviewed_at, public._player_name_by_phone(r.phone_raw10) as player_name
from public.account_requests r;

-- Sütun düzeyinde okuma: telefon ve kimlik no hariç.
revoke select on public.players from anon, authenticated;
grant select (id, name, surname, birth_date, preferred_foot, main_position,
              sub_position, other_positions, photo_url, height, weight,
              auth_uid, created_at, updated_at)
  on public.players to anon, authenticated;

-- Realtime satırın tamamını (telefon dahil) yayıyordu.
alter publication supabase_realtime drop table public.players;

commit;
