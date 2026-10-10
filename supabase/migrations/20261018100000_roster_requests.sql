-- Takım sorumlusunun kadro talepleri (pending_actions) için tamamlayıcılar:
--  * Forma numarası silinebilir (null): takım sorumlusu da yapabilir.
--  * Aynı oyuncu için aynı türde ikinci bekleyen talep açılamaz.
--  * Yeni talep onaylayıcılara (kurucu başkan + takımın bölge sorumlusu)
--    bildirim olarak gider; sonuç talebi açana bildirilir.

create or replace function public.set_jersey_number(
  p_season_id uuid,
  p_team_id uuid,
  p_player_id uuid,
  p_number integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (public.owns_season_team(p_season_id, p_team_id)
          or public.manages_team(p_season_id, p_team_id)) then
    raise exception 'Bu takımın forma numaralarını değiştirme yetkiniz yok.'
      using errcode = '42501';
  end if;
  if p_number is not null and (p_number < 1 or p_number > 999) then
    raise exception 'Forma numarası 1 ile 999 arasında olmalı.';
  end if;
  if p_number is not null and exists (
    select 1 from public.season_team_players
    where season_id = p_season_id and team_id = p_team_id
      and jersey_number = p_number and is_active
      and player_id <> p_player_id
  ) then
    raise exception 'Bu forma numarası bu takımda zaten kullanılıyor.';
  end if;
  update public.season_team_players
     set jersey_number = p_number
   where season_id = p_season_id and team_id = p_team_id
     and player_id = p_player_id and is_active;
  if not found then
    raise exception 'Futbolcu bu takımın kadrosunda bulunamadı.';
  end if;
end;
$$;

create unique index if not exists pending_actions_one_open_per_player
  on public.pending_actions (season_id, team_id, action_type, (payload ->> 'player_id'))
  where status = 'pending' and (payload ->> 'player_id') is not null;

-- Talep metni: "Beyaz FK · Ali Veli · kadroya ekleme".
create or replace function public.pending_action_text(a public.pending_actions)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select concat_ws(' · ',
    (select t.name from public.teams t where t.id = a.team_id),
    coalesce(
      (select nullif(trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, '')), '')
         from public.players p
        where p.id = nullif(a.payload ->> 'player_id', '')::uuid),
      nullif(trim(coalesce(a.payload -> 'player' ->> 'name', '') || ' '
                  || coalesce(a.payload -> 'player' ->> 'surname', '')), ''),
      'Futbolcu'
    ),
    case a.action_type
      when 'roster_add' then 'kadroya ekleme'
      when 'roster_remove' then 'kadrodan çıkarma'
      when 'jersey_change' then 'forma numarası'
      else a.action_type
    end
  )
$$;

create or replace function public.pending_actions_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
begin
  if tg_op = 'INSERT' then
    with ids as (
      select lo.user_id as uid from public.league_owners lo
       where lo.league_id = new.league_id
      union
      select ro.user_id from public.season_teams st
        join public.groups g on g.id = st.group_id
        join public.region_owners ro on ro.region_id = g.region_id
       where st.season_id = new.season_id and st.team_id = new.team_id
    )
    select array_agg(distinct uid) into v_ids
      from ids where uid is not null and uid <> new.submitted_by;
    perform public.push_send(
      v_ids,
      'Onay bekleyen kadro talebi',
      public.pending_action_text(new),
      '/',
      'approval-' || new.id
    );
  elsif new.status in ('approved', 'rejected') and old.status = 'pending' then
    perform public.push_send(
      array[new.submitted_by],
      case new.status when 'approved' then 'Talebiniz onaylandı'
                      else 'Talebiniz reddedildi' end,
      public.pending_action_text(new)
        || coalesce(' · ' || nullif(trim(new.review_note), ''), ''),
      '/',
      'roster-' || new.id
    );
  end if;
  return new;
exception when others then
  raise warning 'pending_actions_push: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists pending_actions_push on public.pending_actions;
create trigger pending_actions_push
  after insert or update of status on public.pending_actions
  for each row execute function public.pending_actions_push();
