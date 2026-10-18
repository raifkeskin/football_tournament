-- Instagram → Haberler seçmeli aktarım: #ligmasasi etiketi olmayan gönderi
-- yayınlanmadan kaydedilir (instagram_sync.ts). Kurucu başkan(lar)a "onay
-- bekliyor" bildirimi gider; karar Bekleyen Onaylar > Haber'de verilir.
-- Eski sürümler etkilenmez: yayınlanmamış haber yalnız yetkiliye görünür.

create or replace function public.news_ig_pending_push()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_ids uuid[];
begin
  if new.auto_kind is distinct from 'instagram'
     or coalesce(new.is_published, false) then
    return new;
  end if;
  select array_agg(distinct lo.user_id) into v_ids
    from public.seasons s
    join public.league_owners lo on lo.league_id = s.league_id
   where s.id = new.season_id;
  if v_ids is null then
    return new;
  end if;
  perform public.push_send(
    v_ids,
    'Instagram gönderisi onay bekliyor',
    'Yeni gönderi #ligmasasi etiketi olmadığı için Haberler''e alınmadı. '
      || 'Bekleyen Onaylar''dan yayınlayabilirsiniz.',
    '/',
    'approval-ig' || new.id
  );
  return new;
exception when others then
  raise warning 'news_ig_pending_push: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists news_ig_pending_push on public.news;
create trigger news_ig_pending_push
  after insert on public.news
  for each row execute function public.news_ig_pending_push();
