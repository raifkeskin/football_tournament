-- Tam doğum tarihi artık yalnız admine (ve oyuncunun kendisine) gösteriliyor:
-- düzenleyen kişi tarihi görmeden kaydederse (boş) mevcut tarih korunur.
CREATE OR REPLACE FUNCTION public.player_edit_basic(p_player uuid, p_name text, p_surname text, p_birth date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not public.can_edit_player_basic(p_player) then
    raise exception 'Bu futbolcunun bilgilerini düzenleme yetkiniz yok (kimliği doğrulanmış olabilir).'
      using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_name, ''))) < 2 or length(btrim(coalesce(p_surname, ''))) < 2 then
    raise exception 'Ad ve soyad en az 2 harf olmalı.';
  end if;
  if p_birth is not null and (p_birth > current_date - interval '5 years' or p_birth < date '1930-01-01') then
    raise exception 'Doğum tarihi geçersiz.';
  end if;
  update public.players
     set name = btrim(p_name), surname = btrim(p_surname), birth_date = coalesce(p_birth, birth_date)
   where id = p_player;
end;
$function$

;
