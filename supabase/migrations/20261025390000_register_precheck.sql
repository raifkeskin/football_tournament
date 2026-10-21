-- Kayıt Ol / Futbolcu: kimlik okunur okunmaz bu kişinin zaten hesabı olan
-- bir profili var mı bakılır (register_player ile aynı eşleşme kuralı).
-- Dönüş: ok | disabled | invalid_tc | profile_has_account | ambiguous.
create or replace function public.register_player_precheck(
  p_first text, p_last text, p_birth date, p_tc text
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_hash text;
  v_player uuid;
  v_auth uuid;
  v_count int;
begin
  if not public.self_registration_enabled() then
    return 'disabled';
  end if;
  if not public.tc_valid(p_tc) then
    return 'invalid_tc';
  end if;
  v_hash := public._identity_hash(p_tc);

  select v.player_id, p.auth_uid into v_player, v_auth
    from public.player_verifications v
    join public.players p on p.id = v.player_id
   where v.tc_hash = v_hash;
  if v_player is null then
    select count(*), min(p.id::text)::uuid into v_count, v_player
      from public.players p
     where p.birth_date = p_birth
       and public.tr_fold(p.surname) = public.tr_fold(btrim(p_last))
       and (public.tr_fold(p.name) = public.tr_fold(btrim(p_first))
            or public.tr_fold(btrim(p_first)) like public.tr_fold(p.name) || ' %'
            or public.tr_fold(p.name) like public.tr_fold(btrim(p_first)) || ' %')
       and not exists (select 1 from public.player_verifications v
                        where v.player_id = p.id);
    if v_count > 1 then
      return 'ambiguous';
    end if;
    if v_player is not null then
      select auth_uid into v_auth from public.players where id = v_player;
    end if;
  end if;
  insert into public.identity_events (player_id, action, user_id)
  values (v_player, 'register_check', null);
  return case when v_auth is not null then 'profile_has_account' else 'ok' end;
end;
$function$;
revoke all on function public.register_player_precheck(text, text, date, text) from public;
grant execute on function public.register_player_precheck(text, text, date, text) to anon, authenticated;
