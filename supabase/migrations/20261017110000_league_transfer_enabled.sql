-- Turnuvada transfer dönemi açık/kapalı. Varsayılan kapalı; yalnızca admin
-- değiştirir. Transfer tarihleri sezonda kalır (yalnızca admin görür).

alter table public.leagues
  add column if not exists transfer_enabled boolean not null default false;

create or replace function public.guard_league_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.role(), '') in ('authenticated', 'anon')
     and not public.is_admin() then
    if new.status is distinct from old.status then
      raise exception 'Turnuva durumunu yalnızca admin değiştirebilir.'
        using errcode = '42501';
    end if;
    if new.transfer_enabled is distinct from old.transfer_enabled then
      raise exception 'Transfer ayarını yalnızca admin değiştirebilir.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
