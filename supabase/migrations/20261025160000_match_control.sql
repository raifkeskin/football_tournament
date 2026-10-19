-- Maç yönetimi (tek yönetici + devir). Aynı maçta olay girişi, devreler ve
-- skor tek kişinin ekranında açıktır; diğer yetkililer kimin yönettiğini
-- görür, devir ister, yöneten onaylar. Yalnız maçı yönetebilenler görür
-- (can_manage_match: admin, turnuva sahibi, bölge sorumlusu, gözlemci);
-- takım sorumlusu, futbolcu ve misafir göremez.
--
-- Kurallar: gözlemci maç ekranına girince yönetim boşsa kendiliğinden ona
-- geçer (istemci take çağırır). Devir isteğine 30 sn içinde cevap gelmezse
-- ya da yöneten 2 dakikadır görünmüyorsa (seen_at) onaysız devralınır.
-- İlk aşamada kilit ekranda; sunucu olay girişini henüz engellemez (eski
-- uygulama sürümleri bozulmasın).

create table if not exists public.match_control (
  match_id uuid primary key references public.matches(id) on delete cascade,
  user_id uuid not null,
  since timestamptz not null default now(),
  seen_at timestamptz not null default now(),
  req_user uuid,
  req_at timestamptz
);
alter table public.match_control enable row level security;

-- Ekranda gösterilecek ad: hesap adı, yoksa oyuncu kaydı, yoksa davet adı.
create or replace function public.person_display_name(p_uid uuid)
returns text
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(
    (select nullif(trim(coalesce(nullif(u.display_name, ''), u.name, '')), '')
       from public.app_users u where u.auth_uid = p_uid::text limit 1),
    (select nullif(trim(coalesce(p.name, '') || ' ' || coalesce(p.surname, '')), '')
       from public.players p where p.auth_uid = p_uid limit 1),
    (select i.full_name from public.league_owner_invites i
       join auth.users au on au.email = i.phone_raw10 || '@masterclass.com'
      where au.id = p_uid limit 1),
    'Yönetici')
$$;
revoke all on function public.person_display_name(uuid) from public, anon, authenticated;

create or replace function public.match_control_state(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  c public.match_control;
  v_me uuid := auth.uid();
  v_online boolean;
  v_req_expired boolean;
begin
  if not public.can_manage_match(p_match_id) then
    raise exception 'Bu maçı yönetme yetkiniz yok.' using errcode = '42501';
  end if;
  -- Yöneten kişi ekrandayken her sorguda "görüldü" damgası yenilenir.
  update public.match_control set seen_at = now()
   where match_id = p_match_id and user_id = v_me
  returning * into c;
  if c.match_id is null then
    select * into c from public.match_control where match_id = p_match_id;
  end if;

  v_online := c.seen_at > now() - interval '2 minutes';
  v_req_expired := c.req_at is not null and c.req_at < now() - interval '30 seconds';
  return jsonb_build_object(
    'controller', c.user_id,
    'controller_name', case when c.user_id is not null then public.person_display_name(c.user_id) end,
    'since', c.since,
    'online', coalesce(v_online, false),
    'mine', c.user_id = v_me,
    'req_user', case when not coalesce(v_req_expired, false) then c.req_user end,
    'req_name', case when c.req_user is not null and not coalesce(v_req_expired, false)
                     then public.person_display_name(c.req_user) end,
    'req_left', case when c.req_at is not null and not coalesce(v_req_expired, false)
                     then greatest(0, 30 - extract(epoch from now() - c.req_at)::int) end,
    'req_mine', c.req_user = v_me and not coalesce(v_req_expired, false),
    -- Onaysız devralma: yöneten 2 dk görünmüyor ya da benim isteğim
    -- cevapsız kaldı.
    'can_force', c.user_id is not null and c.user_id <> v_me
                 and (not v_online or (c.req_user = v_me and v_req_expired)),
    'observer', exists (select 1 from public.matches m
                         where m.id = p_match_id and m.observer_id = v_me),
    'now', now()
  );
end;
$$;

create or replace function public.match_control_take(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  c public.match_control;
  v_me uuid := auth.uid();
begin
  if not public.can_manage_match(p_match_id) then
    raise exception 'Bu maçı yönetme yetkiniz yok.' using errcode = '42501';
  end if;
  select * into c from public.match_control where match_id = p_match_id for update;
  if c.match_id is not null and c.user_id <> v_me
     and c.seen_at > now() - interval '2 minutes'
     and not (c.req_user = v_me and c.req_at < now() - interval '30 seconds') then
    raise exception 'Maçı % yönetiyor; devir isteyin.', public.person_display_name(c.user_id);
  end if;
  insert into public.match_control (match_id, user_id, since, seen_at)
  values (p_match_id, v_me, now(), now())
  on conflict (match_id) do update
    set user_id = v_me,
        since = case when public.match_control.user_id = v_me then public.match_control.since else now() end,
        seen_at = now(), req_user = null, req_at = null;
  return public.match_control_state(p_match_id);
end;
$$;

create or replace function public.match_control_request(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  c public.match_control;
  v_me uuid := auth.uid();
begin
  if not public.can_manage_match(p_match_id) then
    raise exception 'Bu maçı yönetme yetkiniz yok.' using errcode = '42501';
  end if;
  select * into c from public.match_control where match_id = p_match_id for update;
  if c.match_id is null or c.user_id = v_me then
    return public.match_control_take(p_match_id);
  end if;
  if c.req_user is not null and c.req_user <> v_me
     and c.req_at > now() - interval '30 seconds' then
    raise exception '% de devir istedi; biraz sonra tekrar deneyin.', public.person_display_name(c.req_user);
  end if;
  update public.match_control set req_user = v_me, req_at = now() where match_id = p_match_id;
  return public.match_control_state(p_match_id);
end;
$$;

create or replace function public.match_control_answer(p_match_id uuid, p_approve boolean)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  c public.match_control;
begin
  select * into c from public.match_control where match_id = p_match_id for update;
  if c.match_id is null or c.user_id <> auth.uid() then
    raise exception 'Maçı siz yönetmiyorsunuz.';
  end if;
  if p_approve and c.req_user is not null then
    update public.match_control
       set user_id = c.req_user, since = now(), seen_at = now(), req_user = null, req_at = null
     where match_id = p_match_id;
  else
    update public.match_control set req_user = null, req_at = null where match_id = p_match_id;
  end if;
  return public.match_control_state(p_match_id);
end;
$$;

create or replace function public.match_control_cancel(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
begin
  update public.match_control set req_user = null, req_at = null
   where match_id = p_match_id and req_user = auth.uid();
  return public.match_control_state(p_match_id);
end;
$$;

create or replace function public.match_control_release(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
begin
  delete from public.match_control where match_id = p_match_id and user_id = auth.uid();
  return public.match_control_state(p_match_id);
end;
$$;

revoke all on function public.match_control_state(uuid) from public, anon;
revoke all on function public.match_control_take(uuid) from public, anon;
revoke all on function public.match_control_request(uuid) from public, anon;
revoke all on function public.match_control_answer(uuid, boolean) from public, anon;
revoke all on function public.match_control_cancel(uuid) from public, anon;
revoke all on function public.match_control_release(uuid) from public, anon;
grant execute on function public.match_control_state(uuid) to authenticated;
grant execute on function public.match_control_take(uuid) to authenticated;
grant execute on function public.match_control_request(uuid) to authenticated;
grant execute on function public.match_control_answer(uuid, boolean) to authenticated;
grant execute on function public.match_control_cancel(uuid) to authenticated;
grant execute on function public.match_control_release(uuid) to authenticated;
