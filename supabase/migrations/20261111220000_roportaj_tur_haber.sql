-- Röportajın türü değişince haberi de değişsin (maç sonrası → maç öncesi vb.).
-- Eski haber yalnız bu videoyu içeriyorsa aynı haber yeni türe çevrilir
-- (tarih, tepki, yorum ve sabitleme korunur); değilse video yeni türün
-- haberine taşınır, boşalan eski haber silinir.
create or replace function public._interview_news_move(
  p_match uuid, p_old text, p_new text)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_news uuid;
  v_old_label text := case p_old when 'pre' then 'maç öncesi'
                                 when 'live' then 'maç anı' else 'maç sonrası' end;
  v_new_label text := case p_new when 'pre' then 'maç öncesi'
                                 when 'live' then 'maç anı' else 'maç sonrası' end;
begin
  if p_old is null or p_old = p_new then return; end if;
  select id into v_news from public.news
   where auto_kind = 'interviews' and match_id = p_match
     and auto_data ->> 'kind' = p_old
   limit 1;
  if v_news is not null
     and not exists (select 1 from public.videos
                      where match_id = p_match and kind = p_old)
     and not exists (select 1 from public.news
                      where auto_kind = 'interviews' and match_id = p_match
                        and auto_data ->> 'kind' = p_new) then
    update public.news set
      auto_data = coalesce(auto_data, '{}'::jsonb) || jsonb_build_object('kind', p_new),
      content = replace(content, v_old_label, v_new_label)
     where id = v_news;
  end if;
  -- Yeni türün haberini oluştur / güncelle, sonra eskisini yenile ya da sil.
  perform public._interview_news_sync(p_match, p_new);
  perform public._interview_news_sync(p_match, p_old);
end;
$$;
revoke all on function public._interview_news_move(uuid, text, text) from public, anon, authenticated;

create or replace function public.video_set_kind(p_id uuid, p_kind text)
 returns void language plpgsql security definer set search_path to ''
as $function$
declare
  v_season uuid;
  v_match uuid;
  v_old text;
begin
  if p_kind not in ('pre', 'live', 'post') then
    raise exception 'Geçersiz tür.';
  end if;
  select season_id, match_id, kind into v_season, v_match, v_old
    from public.videos where id = p_id;
  if v_season is null or v_match is null
     or not public.can_manage_season_media(v_season) then
    raise exception 'Yetkiniz yok.';
  end if;
  update public.videos set kind = p_kind where id = p_id;
  perform public._interview_news_move(v_match, v_old, p_kind);
end;
$function$;
grant execute on function public.video_set_kind(uuid, text) to authenticated;

-- Düzeltme: türü önceden değiştirilmiş ama haberi eski kalmış röportajlar.
do $$
declare r record;
begin
  for r in
    select distinct n.match_id, n.auto_data ->> 'kind' as old_kind, v.kind as new_kind
      from public.news n
      join public.videos v on v.match_id = n.match_id and v.news_id = n.id
     where n.auto_kind = 'interviews' and n.auto_data ->> 'kind' is distinct from v.kind
  loop
    perform public._interview_news_move(r.match_id, r.old_kind, r.new_kind);
  end loop;
end $$;
