-- Eski "On Numara" mevkisi Orta Saha · Ofansif olur.

update public.players
   set main_position = 'Orta Saha',
       sub_position = 'Ofansif'
 where main_position = 'On Numara' or sub_position = 'On Numara';
