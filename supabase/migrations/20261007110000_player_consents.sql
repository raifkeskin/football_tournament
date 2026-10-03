-- KVKK ve sağlık onayları. Kayıtlar silinmez/güncellenmez (ispat için
-- değişmez kayıt defteri); oyuncunun güncel durumu her onay türünün en son
-- kaydıdır. Onayı yalnızca oyuncunun kendisi (giriş yapmış hesabı) verir.

create table if not exists public.player_consents (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players(id) on delete cascade,
  user_id uuid not null,
  consent_type text not null check (consent_type in (
    'privacy_notice',     -- aydınlatma metni okundu
    'health_data',        -- sağlık verisi işlenmesine açık rıza
    'health_declaration', -- sağlık beyanı + risk kabulü
    'photo_publish'       -- fotoğraf/isim yayın izni (isteğe bağlı)
  )),
  version text not null,
  granted boolean not null,
  user_agent text,
  created_at timestamptz not null default now()
);

create index if not exists player_consents_player_type_idx
  on public.player_consents (player_id, consent_type, created_at desc);

alter table public.player_consents enable row level security;

-- Doğrudan yazma yok; yalnızca give_player_consents ile.
drop policy if exists player_consents_read on public.player_consents;
create policy player_consents_read on public.player_consents
  for select to authenticated
  using (
    public.is_admin() or exists (
      select 1 from public.players p
      where p.id = player_id and p.auth_uid = auth.uid()
    )
  );

revoke insert, update, delete on public.player_consents from anon, authenticated;

-- Metinler değişince artırılır; eski versiyona verilen onay geçersiz sayılır
-- ve oyuncudan yeniden istenir. Uygulamadaki kConsentVersion ile aynı olmalı.
create or replace function public.current_consent_version()
returns text
language sql
immutable
as $$ select '2026-10-v1' $$;

-- Oyuncu kendi onaylarını verir / geri çeker. Her çağrıda dört türün de
-- durumu kayda geçer.
create or replace function public.give_player_consents(
  p_player_id uuid,
  p_privacy boolean,
  p_health boolean,
  p_declaration boolean,
  p_photo boolean,
  p_version text,
  p_user_agent text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Giriş yapmalısınız.';
  end if;
  if not exists (
    select 1 from public.players
    where id = p_player_id and auth_uid = auth.uid()
  ) then
    raise exception 'Bu oyuncu kaydı hesabınıza bağlı değil.';
  end if;
  if p_version is distinct from public.current_consent_version() then
    raise exception 'Onay metni güncellendi; sayfayı yenileyip tekrar deneyin.';
  end if;

  insert into public.player_consents
    (player_id, user_id, consent_type, version, granted, user_agent)
  values
    (p_player_id, auth.uid(), 'privacy_notice', p_version, p_privacy, p_user_agent),
    (p_player_id, auth.uid(), 'health_data', p_version, p_health, p_user_agent),
    (p_player_id, auth.uid(), 'health_declaration', p_version, p_declaration, p_user_agent),
    (p_player_id, auth.uid(), 'photo_publish', p_version, p_photo, p_user_agent);
end;
$$;

revoke all on function public.give_player_consents(uuid, boolean, boolean, boolean, boolean, text, text) from public, anon;
grant execute on function public.give_player_consents(uuid, boolean, boolean, boolean, boolean, text, text) to authenticated;

-- Oyuncuların onay durumu (kadro / lisans ekranları). Yalnızca admin, turnuva
-- sahibi, takım sorumlusu ve oyuncunun kendisi görür; diğerleri için satır
-- dönmez. complete: zorunlu üç onay güncel versiyonla verilmiş.
create or replace function public.player_consent_status(p_player_ids uuid[])
returns table (
  player_id uuid,
  has_account boolean,
  complete boolean,
  photo_allowed boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with latest as (
    select distinct on (c.player_id, c.consent_type)
      c.player_id, c.consent_type, c.granted, c.version
    from public.player_consents c
    where c.player_id = any (p_player_ids)
    order by c.player_id, c.consent_type, c.created_at desc
  )
  select
    p.id,
    p.auth_uid is not null,
    (
      select count(*) = 3 from latest l
      where l.player_id = p.id
        and l.consent_type in ('privacy_notice', 'health_data', 'health_declaration')
        and l.granted
        and l.version = public.current_consent_version()
    ),
    coalesce((
      select l.granted from latest l
      where l.player_id = p.id and l.consent_type = 'photo_publish'
    ), false)
  from public.players p
  where p.id = any (p_player_ids)
    and (
      public.is_admin()
      or p.auth_uid = auth.uid()
      or public.owns_player(p.id)
      or public.manages_player(p.id)
    )
$$;

revoke all on function public.player_consent_status(uuid[]) from public, anon;
grant execute on function public.player_consent_status(uuid[]) to authenticated;
