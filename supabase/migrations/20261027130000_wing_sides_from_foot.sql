-- Tarafı bilinmeyen eski kanat kayıtları kullandığı ayağa göre ayrılır:
-- sol ayak → Sol Kanat / Sol Kanat Forvet, sağ ayak → Sağ. Ana mevkisi
-- doğrudan "Kanat" yazılmış eski kayıtlar Orta Saha olur. "Her İkisi" ve
-- ayağı girilmemiş olanlar olduğu gibi kalır (form tarafı seçtirir).

update public.players
   set main_position = 'Orta Saha',
       sub_position = preferred_foot || ' Kanat'
 where main_position = 'Kanat'
   and coalesce(nullif(trim(sub_position), ''), 'Kanat') = 'Kanat'
   and preferred_foot in ('Sağ', 'Sol');

update public.players
   set sub_position = preferred_foot || ' ' || sub_position
 where sub_position in ('Kanat', 'Kanat Forvet')
   and preferred_foot in ('Sağ', 'Sol');
