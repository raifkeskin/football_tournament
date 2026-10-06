-- Kullanıcının kendi hesabını silmesi (App Store / Google Play şartı).
--
-- Silinen / koparılan:
--   * auth.users satırı (oturumlar, yöneticilik, beğeni, takip, bildirim
--     abonelikleri ve profil talepleri FK ile birlikte silinir)
--   * app_users satırı ve hesap başvuruları
--   * oyuncu kaydındaki iletişim/kimlik verileri: telefon, TC kimlik no,
--     fotoğraf, boy, kilo; kaydın hesapla bağı
--   * onay kayıtlarının kullanıcıyla bağı (kanıt kaydı oyuncu kaydında kalır)
--
-- Kalan: oyuncunun ad-soyadı ve doğum tarihi (turnuva geçmişi ve yaş
-- sınırı organizatörün kaydıdır; gizlilik politikasında yazılıdır).
--
-- Turnuvanın tek kurucu başkanı hesabını silemez: önce başka bir yönetici
-- atanmalıdır (turnuva sahipsiz kalmasın).

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_leagues text;
begin
  if v_uid is null then
    raise exception 'Giriş yapılmamış.';
  end if;

  select string_agg(l.name, ', ' order by l.name) into v_leagues
  from public.league_owners o
  join public.leagues l on l.id = o.league_id
  where o.user_id = v_uid
    and not exists (
      select 1 from public.league_owners x
      where x.league_id = o.league_id and x.user_id <> v_uid
    );
  if v_leagues is not null then
    raise exception 'SOLE_OWNER: %', v_leagues;
  end if;

  update public.player_consents set user_id = null where user_id = v_uid;

  update public.players
  set phone = null,
      national_id = null,
      photo_url = null,
      height = null,
      weight = null,
      auth_uid = null
  where auth_uid = v_uid;

  delete from public.app_users
  where auth_uid = v_uid::text or uid = v_uid::text;

  delete from public.account_requests where user_id = v_uid;

  delete from auth.users where id = v_uid;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
