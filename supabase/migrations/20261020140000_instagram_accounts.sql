-- Instagram bağlantısı (1. aşama): her turnuva kendi Instagram profesyonel
-- hesabını "Instagram API with Instagram Login" ile bir kez yetkilendirir.
--
-- * league_instagram_accounts: uzun ömürlü erişim belirteci (60 gün). Yalnız
--   sunucu (Edge Function, service role) okur/yazar; RLS açık, politika yok,
--   anon/authenticated için hiçbir yetki yok — admin dahil kimse uygulamadan
--   belirteci göremez.
-- * instagram_oauth_states: bağlama akışının tek kullanımlık "state" değeri
--   (CSRF koruması). instagram-connect üretir, instagram-oauth-callback siler.
-- * league_instagram_status / disconnect_league_instagram: turnuva sahibi ve
--   admin (owns_league) için durum ve bağlantıyı kaldırma.

create table if not exists public.league_instagram_accounts (
  league_id uuid primary key references public.leagues(id) on delete cascade,
  ig_user_id text not null,
  username text,
  access_token text not null,
  expires_at timestamptz,
  permissions text[] not null default '{}',
  connected_by uuid references auth.users(id) on delete set null,
  connected_at timestamptz not null default now(),
  refreshed_at timestamptz
);

alter table public.league_instagram_accounts enable row level security;
revoke all on public.league_instagram_accounts from anon, authenticated;

create table if not exists public.instagram_oauth_states (
  state text primary key default encode(extensions.gen_random_bytes(24), 'hex'),
  league_id uuid not null references public.leagues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.instagram_oauth_states enable row level security;
revoke all on public.instagram_oauth_states from anon, authenticated;

-- Bağlı hesabın özeti (belirteç dönmez). Yetkisiz kişiye boş döner.
create or replace function public.league_instagram_status(p_league_id uuid)
returns table (
  username text,
  connected_at timestamptz,
  expires_at timestamptz,
  can_publish boolean
)
language sql
stable
security definer
set search_path to ''
as $$
  select a.username, a.connected_at, a.expires_at,
         'instagram_business_content_publish' = any (a.permissions)
  from public.league_instagram_accounts a
  where a.league_id = p_league_id
    and public.owns_league(p_league_id)
$$;

create or replace function public.disconnect_league_instagram(p_league_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not public.owns_league(p_league_id) then
    raise exception 'Bu turnuva için yetkiniz yok.';
  end if;
  delete from public.league_instagram_accounts where league_id = p_league_id;
end;
$$;

revoke all on function public.league_instagram_status(uuid) from public, anon;
revoke all on function public.disconnect_league_instagram(uuid) from public, anon;
grant execute on function public.league_instagram_status(uuid) to authenticated;
grant execute on function public.disconnect_league_instagram(uuid) to authenticated;
