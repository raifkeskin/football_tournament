-- Gol özeti taraması hata aldığında kullanıcı "Admin'e bildir" der:
-- adminlere Telegram'dan maç bilgisiyle bildirim gider (kullanıcı başına
-- maç başına saatte 1).
create or replace function public.report_highlight_problem(p_match_id uuid)
 returns text language plpgsql security definer set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_info text;
  v_who text;
  v_job text;
begin
  if v_uid is null then
    return 'login';
  end if;
  if exists (select 1 from public.app_feedback f
              where f.user_id = v_uid
                and f.role = 'gol-ozet'
                and f.message like '%' || p_match_id::text || '%'
                and f.created_at > now() - interval '1 hour') then
    return 'already';
  end if;

  select concat_ws(' · ',
           l.name,
           case when m.week is not null then m.week || '. hafta' end,
           th.name || ' - ' || ta.name,
           to_char(m.match_date at time zone 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI'))
    into v_info
    from public.matches m
    join public.seasons s on s.id = m.season_id
    join public.leagues l on l.id = s.league_id
    join public.teams th on th.id = m.home_team_id
    join public.teams ta on ta.id = m.away_team_id
   where m.id = p_match_id;
  if v_info is null then
    return 'not_found';
  end if;

  select j.status || coalesce(' · ' || left(j.error, 200), '')
    into v_job
    from public.match_highlight_jobs j where j.match_id = p_match_id limit 1;

  select coalesce(
           nullif(trim(concat_ws(' ', p.name, p.surname)), ''),
           (select au.name from public.app_users au where au.auth_uid = v_uid::text limit 1),
           'Adsız hesap')
    into v_who
    from (select 1) x
    left join public.players p on p.auth_uid = v_uid;

  insert into public.app_feedback (user_id, message, role)
  values (v_uid, 'Gol özeti sorunu: ' || v_info || E'\nmaç: ' || p_match_id::text
                 || coalesce(E'\nanaliz: ' || v_job, ''), 'gol-ozet');

  begin
    perform public.telegram_notify(
      array(select user_id from public.admins where user_id is not null),
      '⚠️ Gol özeti taraması hata aldı'
        || E'\n' || v_info
        || coalesce(E'\nAnaliz: ' || v_job, '')
        || E'\nBildiren: ' || v_who
    );
  exception when others then
    raise warning 'report_highlight_problem telegram: %', sqlerrm;
  end;
  return 'ok';
end;
$function$;
grant execute on function public.report_highlight_problem(uuid) to authenticated;
