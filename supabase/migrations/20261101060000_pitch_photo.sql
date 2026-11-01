-- Saha fotoğrafı (Saha Yönetimi'nden yüklenir).
alter table public.pitches add column if not exists photo_url text;
