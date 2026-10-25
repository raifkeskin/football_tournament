-- "Maçın yönetimi boşta" uyarısı her maç için bir kez gider.
insert into public.match_push_log (match_id, kind)
select distinct n.ref_id, 'idle'
  from public.notifications n
  join public.matches m on m.id = n.ref_id
 where n.title = 'Maçın yönetimi boşta'
on conflict do nothing;

CREATE OR REPLACE FUNCTION public.match_control_watch()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r record;
  v_uids uuid[];
begin
  for r in
    select c.match_id, c.user_id
      from public.match_control c
      join public.matches m on m.id = c.match_id
     where c.seen_at < now() - interval '2 minutes'
       and c.offline_notified_at is null
       and m.status in ('live', 'halftime')
       and m.deleted_at is null
  loop
    v_uids := array(
      select u from unnest(public.match_managers(r.match_id)) u where u <> r.user_id
    );
    -- Her maça bir kez (sorumlu bağlanıp kopsa da tekrar gitmez).
    if cardinality(v_uids) > 0
       and public.match_push_once(r.match_id, 'idle') then
      -- "Canlı" bildirimleri kapalı olsa da gider.
      perform public.push_send(
        v_uids,
        'Maçın yönetimi boşta',
        coalesce(public.match_label(r.match_id), 'Maç') || ': '
          || public.person_display_name(r.user_id)
          || ' 2 dakikadır bağlı değil. Devralmak için dokunun.',
        '/',
        'live-' || r.match_id,
        true
      );
    end if;
    update public.match_control set offline_notified_at = now() where match_id = r.match_id;
  end loop;
end;
$function$;
