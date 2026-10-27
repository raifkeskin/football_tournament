-- 1) Futbolcu asıl mevkisini Mevki sekmesinden onaysız değiştirir (oynayabildiği
--    mevkiler gibi). Yöneten (admin / kurucu başkan / bölge sorumlusu) yine
--    doğrudan değiştirir. Eski sürümlerin submit_profile_change ile gönderdiği
--    mevki talepleri onaya gitmeye devam eder.
-- 2) Maç bilgisi: hakem adı (Maçı Düzenle'den girilir, maç detayında görünür).

create or replace function public.set_player_main_position(
  p_player_id uuid,
  p_position text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_main text;
begin
  if auth.uid() is null then
    raise exception 'Giriş yapmalısınız.' using errcode = '42501';
  end if;
  if not public.positions_tab_allowed() then
    raise exception 'Bu özellik henüz açık değil.' using errcode = '42501';
  end if;
  if not (exists (select 1 from public.players p
                   where p.id = p_player_id and p.auth_uid = auth.uid())
          or public.owns_player(p_player_id)) then
    raise exception 'Bu futbolcunun mevkisini değiştiremezsiniz.'
      using errcode = '42501';
  end if;

  v_main := case
    when p_position = 'Kaleci' then 'Kaleci'
    when p_position in ('Stoper', 'Sol Bek', 'Sağ Bek') then 'Defans'
    when p_position in ('Defansif', 'Merkez', 'Ofansif', 'Sol Kanat',
                        'Sağ Kanat') then 'Orta Saha'
    when p_position in ('Santrfor', 'Sol Kanat Forvet',
                        'Sağ Kanat Forvet') then 'Forvet'
  end;
  if v_main is null then
    raise exception 'Mevki geçersiz.';
  end if;

  update public.players
     set main_position = v_main,
         sub_position = case when v_main = 'Kaleci' then null else p_position end,
         other_positions = array_remove(other_positions, p_position)
   where id = p_player_id;
end;
$$;

revoke all on function public.set_player_main_position(uuid, text) from public, anon;
grant execute on function public.set_player_main_position(uuid, text) to authenticated;

alter table public.matches add column if not exists referee_name text;
