-- Oynayabildiği mevkiler sol / sağ ayrımıyla (FIFA ve menajerlik oyunları
-- gibi): Bek, Kanat ve Kanat Forvet yerine Sol/Sağ Bek, Sol/Sağ Kanat,
-- Sol/Sağ Kanat Forvet. Asıl mevki bugünkü main/sub alanlarından gelir ve
-- tarafsız kalabilir; tarafsız asıl mevkinin iki yanı da asıl sayılır.

alter table public.players drop constraint if exists players_other_positions_check;

-- Taraf bilinmeyen eski değerler bırakılmaz (özellik yalnız admin'deydi).
update public.players
   set other_positions = array(
     select x from unnest(other_positions) x
      where x not in ('Bek', 'Kanat', 'Kanat Forvet'))
 where other_positions && array['Bek', 'Kanat', 'Kanat Forvet']::text[];

alter table public.players add constraint players_other_positions_check check (
  cardinality(other_positions) <= 3
  and other_positions <@ array['Kaleci', 'Stoper', 'Sol Bek', 'Sağ Bek',
                               'Defansif', 'Merkez', 'Ofansif', 'Sol Kanat',
                               'Sağ Kanat', 'Santrfor', 'Sol Kanat Forvet',
                               'Sağ Kanat Forvet']::text[]
);

create or replace function public.set_player_other_positions(
  p_player_id uuid,
  p_positions text[]
)
returns text[]
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_main text;
  v_main_spots text[];
  v_clean text[];
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
    raise exception 'Bu futbolcunun mevkilerini değiştiremezsiniz.'
      using errcode = '42501';
  end if;

  select coalesce(nullif(trim(p.sub_position), ''), nullif(trim(p.main_position), ''))
    into v_main
    from public.players p where p.id = p_player_id;

  -- Asıl mevki tarafsızsa (Bek, Kanat, Kanat Forvet) iki yanı da asıldır.
  v_main_spots := case
    when v_main in ('Bek', 'Kanat', 'Kanat Forvet')
      then array['Sol ' || v_main, 'Sağ ' || v_main]
    else array[v_main]
  end;

  -- Tekrar ve asıl mevki ayıklanır, seçim sırası korunur.
  select coalesce(array_agg(x order by i), '{}')
    into v_clean
    from (
      select x, min(i) i
        from unnest(coalesce(p_positions, '{}')) with ordinality as u(x, i)
       where nullif(trim(x), '') is not null
         and not (x = any (v_main_spots))
       group by x
    ) d;

  if not v_clean <@ array['Kaleci', 'Stoper', 'Sol Bek', 'Sağ Bek',
                          'Defansif', 'Merkez', 'Ofansif', 'Sol Kanat',
                          'Sağ Kanat', 'Santrfor', 'Sol Kanat Forvet',
                          'Sağ Kanat Forvet']::text[] then
    raise exception 'Mevki geçersiz.';
  end if;
  if cardinality(v_clean) > 3 then
    raise exception 'Asıl mevki dışında en çok 3 mevki seçilebilir.';
  end if;

  update public.players set other_positions = v_clean where id = p_player_id;
  return v_clean;
end;
$$;
