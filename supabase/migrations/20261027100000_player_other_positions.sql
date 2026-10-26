-- Oyuncu kartı "Mevki" sekmesi: asıl mevki bugünkü main_position /
-- sub_position'dan gelir; oynayabildiği diğer mevkiler (en çok 3) burada
-- tutulur. Değerler alt mevki listesiyle aynıdır.
--
-- Görünürlük ve yazma app_settings `positions_tab_enabled` ile açılır;
-- kapalıyken yalnız admin. Futbolcu kendi kaydını, admin / kurucu başkan /
-- bölge sorumlusu (owns_player) yönettiği oyuncuyu doğrudan günceller.

alter table public.players
  add column if not exists other_positions text[] not null default '{}';

alter table public.players drop constraint if exists players_other_positions_check;
alter table public.players add constraint players_other_positions_check check (
  cardinality(other_positions) <= 3
  and other_positions <@ array['Kaleci', 'Stoper', 'Bek', 'Defansif', 'Merkez',
                               'Ofansif', 'Kanat', 'Santrfor', 'Kanat Forvet']::text[]
);

insert into public.app_settings (key, value)
values ('positions_tab_enabled', 'false'::jsonb)
on conflict (key) do nothing;

create or replace function public.positions_tab_allowed()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_admin()
      or coalesce((select s.value = 'true'::jsonb from public.app_settings s
                    where s.key = 'positions_tab_enabled'), false)
$$;

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

  -- Tekrar ve asıl mevki ayıklanır, seçim sırası korunur.
  select coalesce(array_agg(x order by i), '{}')
    into v_clean
    from (
      select x, min(i) i
        from unnest(coalesce(p_positions, '{}')) with ordinality as u(x, i)
       where nullif(trim(x), '') is not null
         and x is distinct from v_main
       group by x
    ) d;

  if not v_clean <@ array['Kaleci', 'Stoper', 'Bek', 'Defansif', 'Merkez',
                          'Ofansif', 'Kanat', 'Santrfor', 'Kanat Forvet']::text[] then
    raise exception 'Mevki geçersiz.';
  end if;
  if cardinality(v_clean) > 3 then
    raise exception 'Asıl mevki dışında en çok 3 mevki seçilebilir.';
  end if;

  update public.players set other_positions = v_clean where id = p_player_id;
  return v_clean;
end;
$$;

revoke all on function public.set_player_other_positions(uuid, text[]) from public, anon;
grant execute on function public.set_player_other_positions(uuid, text[]) to authenticated;
grant execute on function public.positions_tab_allowed() to anon, authenticated;
