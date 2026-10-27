-- Tarafsız alt mevki (Bek, Kanat, Kanat Forvet) kalmaz: sol ayak → Sol,
-- diğerleri (sağ, her ikisi, girilmemiş) → Sağ.

update public.players
   set sub_position = case when preferred_foot = 'Sol' then 'Sol ' else 'Sağ ' end
                      || sub_position
 where sub_position in ('Bek', 'Kanat', 'Kanat Forvet');
