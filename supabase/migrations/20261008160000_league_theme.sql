-- Turnuva teması: uygulama kişinin turnuvasıyla açıldığında üst bant,
-- açılış ve menü bu renklerle boyanır (logo leagues.logo_url).
-- Yalnızca yeni, boş bırakılabilir kolonlar; mevcut sürüm etkilenmez.

alter table public.leagues
  add column if not exists theme_primary text
    check (theme_primary is null or theme_primary ~ '^#[0-9A-Fa-f]{6}$'),
  add column if not exists theme_secondary text
    check (theme_secondary is null or theme_secondary ~ '^#[0-9A-Fa-f]{6}$'),
  add column if not exists short_name text
    check (short_name is null or length(short_name) <= 24);

-- Logolardan seçilen başlangıç renkleri (kurucu başkan değiştirebilir).
update public.leagues set theme_primary = '#0B2A6B', theme_secondary = '#D4A017',
  short_name = coalesce(short_name, 'Bosphorus Legends')
  where name = 'Master Bosphorus Legends' and theme_primary is null;
update public.leagues set theme_primary = '#13223F', theme_secondary = '#C0C7D1',
  short_name = coalesce(short_name, 'Champions Master')
  where name = 'Champions Master Lig' and theme_primary is null;
update public.leagues set theme_primary = '#3A3F44', theme_secondary = '#F26B1D'
  where name = 'Hürriyet Gençlik Ligi' and theme_primary is null;
