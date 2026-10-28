-- Fotoğraf yayın izni (photo_publish) vermemiş futbolcunun fotoğrafı hiçbir
-- ekranda görünmez: players.photo_url boşaltılır, fotoğraf gizli tabloda
-- bekler. İzin verilince geri gelir, geri alınınca yine gizlenir.

create table if not exists public.player_photo_hold (
  player_id uuid primary key references public.players(id) on delete cascade,
  photo_url text not null,
  held_at timestamptz not null default now()
);
alter table public.player_photo_hold enable row level security;
revoke all on public.player_photo_hold from public, anon, authenticated;

create or replace function public.player_photo_ok(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce((
    select c.granted from public.player_consents c
     where c.player_id = p_player_id and c.consent_type = 'photo_publish'
     order by c.created_at desc
     limit 1), false)
$$;
revoke all on function public.player_photo_ok(uuid) from public, anon;

-- players: izinsiz yeni fotoğraf gizli tabloya; fotoğraf silinirse bekleyen
-- de silinir (izin akışının kendi boşaltması hariç).
create or replace function public.players_photo_consent_guard()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if coalesce(trim(new.photo_url), '') <> '' then
    if not public.player_photo_ok(new.id) then
      insert into public.player_photo_hold (player_id, photo_url)
      values (new.id, new.photo_url)
      on conflict (player_id) do update
        set photo_url = excluded.photo_url, held_at = now();
      new.photo_url := null;
    end if;
  elsif tg_op = 'UPDATE'
    and coalesce(current_setting('app.photo_hold', true), '') <> '1' then
    delete from public.player_photo_hold where player_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists players_photo_consent_guard on public.players;
create trigger players_photo_consent_guard
  before insert or update of photo_url on public.players
  for each row execute function public.players_photo_consent_guard();

-- player_consents: izin verilince fotoğraf geri gelir, geri alınınca gizlenir.
create or replace function public.player_consents_photo_sync()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_url text;
begin
  if new.consent_type <> 'photo_publish' then
    return null;
  end if;
  if new.granted then
    select photo_url into v_url
      from public.player_photo_hold where player_id = new.player_id;
    if v_url is not null then
      update public.players set photo_url = v_url
       where id = new.player_id and coalesce(photo_url, '') = '';
      delete from public.player_photo_hold where player_id = new.player_id;
    end if;
  else
    select photo_url into v_url from public.players where id = new.player_id;
    if coalesce(trim(v_url), '') <> '' then
      insert into public.player_photo_hold (player_id, photo_url)
      values (new.player_id, v_url)
      on conflict (player_id) do update
        set photo_url = excluded.photo_url, held_at = now();
      perform set_config('app.photo_hold', '1', true);
      update public.players set photo_url = null where id = new.player_id;
      perform set_config('app.photo_hold', '', true);
    end if;
  end if;
  return null;
end;
$$;

drop trigger if exists player_consents_photo_sync on public.player_consents;
create trigger player_consents_photo_sync
  after insert on public.player_consents
  for each row execute function public.player_consents_photo_sync();

-- Futbolcunun kendi bekleyen fotoğrafı ("Yalnız sen görüyorsun").
create or replace function public.my_held_photo()
returns text
language sql
stable
security definer
set search_path to ''
as $$
  select h.photo_url
    from public.player_photo_hold h
    join public.players p on p.id = h.player_id
   where p.auth_uid = auth.uid()
   limit 1
$$;
revoke all on function public.my_held_photo() from public, anon;
grant execute on function public.my_held_photo() to authenticated;

-- Mevcut izinsiz fotoğraflar gizlenir.
insert into public.player_photo_hold (player_id, photo_url)
select p.id, p.photo_url from public.players p
 where coalesce(trim(p.photo_url), '') <> ''
   and not public.player_photo_ok(p.id)
on conflict (player_id) do nothing;

select set_config('app.photo_hold', '1', true);
update public.players p set photo_url = null
 where coalesce(trim(p.photo_url), '') <> ''
   and not public.player_photo_ok(p.id);
select set_config('app.photo_hold', '', true);
