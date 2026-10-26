-- Talebi açanın adı talep satırında saklanır; Bekleyen Onaylar kartı ve
-- onaylayıcı bildirimi bunu gösterir: "Bünyamin Gökçe (takım sorumlusu)".
-- İstemci değeri yazamaz; ekleme öncesi tetikleyici her seferinde doldurur.

alter table public.pending_actions add column if not exists submitter_label text;

create or replace function public.pending_action_submitter_text(a public.pending_actions)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
      (select nullif(trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, '')), '')
         from public.players p
        where p.auth_uid::text = a.submitted_by::text
        limit 1),
      (select coalesce(nullif(trim(u.display_name), ''), nullif(trim(u.name), ''))
         from public.app_users u
        where u.auth_uid = a.submitted_by::text
        limit 1),
      (select coalesce(nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
                       nullif(trim(u.raw_user_meta_data ->> 'name'), ''))
         from auth.users u
        where u.id::text = a.submitted_by::text),
      'Bilinmeyen kullanıcı'
    )
    || case
         when exists (select 1 from public.team_managers tm
                       where tm.user_id::text = a.submitted_by::text
                         and tm.team_id = a.team_id
                         and tm.season_id = a.season_id)
           then ' (takım sorumlusu)'
         else ''
       end
$$;

create or replace function public.pending_actions_set_submitter_label()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.submitter_label := public.pending_action_submitter_text(new);
  return new;
exception when others then
  raise warning 'pending_actions_set_submitter_label: %', sqlerrm;
  new.submitter_label := null;
  return new;
end;
$$;

drop trigger if exists pending_actions_set_submitter_label on public.pending_actions;
create trigger pending_actions_set_submitter_label
  before insert on public.pending_actions
  for each row execute function public.pending_actions_set_submitter_label();

update public.pending_actions pa
   set submitter_label = public.pending_action_submitter_text(pa)
 where pa.submitter_label is null;

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
      public.pending_action_text(new)
        || coalesce(' · Talep eden: ' || new.submitter_label, ''),
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
