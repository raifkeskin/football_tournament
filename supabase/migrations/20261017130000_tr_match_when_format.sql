-- Bildirimlerdeki maç zamanı: "11 Ekim 2026 Pazar / 18:30" (saat yoksa
-- "11 Ekim 2026 Pazar").
create or replace function public.tr_match_when(p_date date, p_time text)
returns text
language sql
immutable
as $$
  select extract(day from p_date)::int || ' ' ||
    (array['Ocak','Şubat','Mart','Nisan','Mayıs','Haziran','Temmuz',
           'Ağustos','Eylül','Ekim','Kasım','Aralık'])[extract(month from p_date)::int] ||
    ' ' || extract(year from p_date)::int || ' ' ||
    (array['Pazartesi','Salı','Çarşamba','Perşembe','Cuma','Cumartesi',
           'Pazar'])[extract(isodow from p_date)::int] ||
    coalesce(' / ' || nullif(left(coalesce(p_time, ''), 5), ''), '')
$$;
