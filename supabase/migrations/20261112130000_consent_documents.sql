-- Onay metinleri veritabanında: metin ve kutu listesi mağaza güncellemesi
-- gerekmeden değişir. Her metin sürümü consent_versions'ta, kutuları
-- consent_items'ta durur. Yeni sürüm eklemek = yeni sürüm satırı + kutuları.
--
-- Geçerlilik: eski sürümle verilen onaylar, o sürüm yürürlükteyken açılmış
-- sezonlar için geçerli kalır. Yeni sürüm yürürlüğe girdikten sonra açılan bir
-- sezonun kadrosundaki oyuncudan yeni metinlerin onayı istenir.

create table if not exists public.consent_versions (
  version text primary key,
  effective_from timestamptz not null,
  note text,
  created_at timestamptz not null default now()
);

create table if not exists public.consent_items (
  version text not null references public.consent_versions(version)
    on delete cascade,
  key text not null,
  sort_order integer not null default 0,
  title text not null,
  checkbox text not null,
  body text not null,
  required boolean not null default false,
  primary key (version, key)
);

-- Onay türleri artık consent_items'tan gelir; sabit liste kısıtı yerine
-- yalnızca biçim denetimi.
alter table public.player_consents
  drop constraint if exists player_consents_consent_type_check;
alter table public.player_consents
  add constraint player_consents_consent_type_check
  check (consent_type ~ '^[a-z][a-z_]{1,40}$');

alter table public.consent_versions enable row level security;
alter table public.consent_items enable row level security;

drop policy if exists consent_versions_read on public.consent_versions;
create policy consent_versions_read on public.consent_versions
  for select to anon, authenticated using (true);

drop policy if exists consent_items_read on public.consent_items;
create policy consent_items_read on public.consent_items
  for select to anon, authenticated using (true);

-- Yürürlükteki sürüm: yürürlük tarihi geçmiş en yeni sürüm.
create or replace function public.current_consent_version()
returns text
language sql
stable
set search_path to ''
as $$
  select coalesce((
    select v.version from public.consent_versions v
     where v.effective_from <= now()
     order by v.effective_from desc
     limit 1), '2026-10-v1')
$$;

-- Oyuncudan istenen en düşük sürüm: kadrosunda olduğu sürüp giden sezonlardan
-- en yenisi hangi sürüm yürürlükteyken açıldıysa o; hiç yoksa ilk sürüm.
create or replace function public.consent_version_required_for(
  p_player_id uuid
)
returns text
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce((
    select v.version
      from public.consent_versions v
     where v.effective_from <= now()
       and exists (
         select 1
           from public.season_team_players stp
           join public.seasons s on s.id = stp.season_id
           join public.leagues l on l.id = s.league_id
          where stp.player_id = p_player_id
            and stp.is_active
            and s.is_active
            and s.deleted_at is null
            and (s.end_date is null or s.end_date >= current_date)
            and not coalesce(l.is_demo, false)
            and s.created_at >= v.effective_from)
     order by v.effective_from desc
     limit 1),
    (select v.version from public.consent_versions v
      order by v.effective_from asc limit 1),
    public.current_consent_version())
$$;

-- Zorunlu onaylar tamam mı: istenen sürümün zorunlu kutularının her biri için
-- son kayıt "verildi" ve o sürüm ya da daha yenisiyle verilmiş olmalı.
create or replace function public.player_consent_complete(p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  with req as (
    select v.version, v.effective_from
      from public.consent_versions v
     where v.version = public.consent_version_required_for(p_player_id)
  ),
  latest as (
    select distinct on (c.consent_type)
           c.consent_type, c.granted, c.version
      from public.player_consents c
     where c.player_id = p_player_id
     order by c.consent_type, c.created_at desc
  )
  select exists (select 1 from req)
     and not exists (
       select 1
         from public.consent_items i
         join req on req.version = i.version
        where i.required
          and not exists (
            select 1
              from latest l
              join public.consent_versions cv on cv.version = l.version
             where l.consent_type = i.key
               and l.granted
               and cv.effective_from >= req.effective_from))
$$;

revoke all on function public.consent_version_required_for(uuid)
  from public, anon, authenticated;
revoke all on function public.player_consent_complete(uuid)
  from public, anon, authenticated;

-- Durum listesi (kadro rozetleri, profil): sürüm kuralı yukarıdaki işlevde.
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
set search_path to ''
as $$
  select
    p.id,
    p.auth_uid is not null,
    public.player_consent_complete(p.id),
    public.player_photo_ok(p.id)
  from public.players p
  where p.id = any (p_player_ids)
    and (
      public.is_admin()
      or p.auth_uid = auth.uid()
      or public.owns_player(p.id)
      or public.manages_player(p.id)
    )
$$;

-- Eski uygulama sürümleri (metinleri içinde gömülü) eski sürüm numarasını
-- gönderir: bilinen her sürüm kabul edilir ve o sürümle kaydedilir.
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
set search_path to ''
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
  if not exists (
    select 1 from public.consent_versions where version = p_version
  ) then
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

-- Yeni uygulama: kutular sürümün consent_items listesinden gelir; her kutu
-- için bir kayıt yazılır (işaretlenmeyen = verilmedi).
create or replace function public.give_player_consents_v2(
  p_player_id uuid,
  p_version text,
  p_choices jsonb,
  p_user_agent text default null
)
returns void
language plpgsql
security definer
set search_path to ''
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
  select p_player_id, auth.uid(), i.key, p_version,
         coalesce((p_choices ->> i.key)::boolean, false), p_user_agent
    from public.consent_items i
   where i.version = p_version
   order by i.sort_order;
end;
$$;

revoke all on function public.give_player_consents_v2(uuid, text, jsonb, text)
  from public, anon;
grant execute on function public.give_player_consents_v2(uuid, text, jsonb, text)
  to authenticated;

-- Sürüm 1: uygulamanın Ekim 2026'dan beri gösterdiği metinler (kayıt için).
insert into public.consent_versions (version, effective_from, note)
values ('2026-10-v1', timestamptz '2026-10-01 00:00:00+03',
        'İlk taslak metinler (uygulamaya gömülü)')
on conflict (version) do nothing;

insert into public.consent_items
  (version, key, sort_order, title, checkbox, body, required)
values
('2026-10-v1', 'privacy_notice', 10, 'Aydınlatma Metni',
 'Aydınlatma metnini okudum, bilgilendirildim.',
 'Uygulamanın 2026-10-v1 sürümündeki kısa aydınlatma metni.', true),
('2026-10-v1', 'health_data', 20, 'Sağlık Verisi Açık Rızası',
 'Sağlık beyanımın turnuva güvenliği amacıyla işlenmesine açık rıza veriyorum.',
 'Uygulamanın 2026-10-v1 sürümündeki kısa sağlık verisi açık rıza metni.', true),
('2026-10-v1', 'health_declaration', 30, 'Sağlık Beyanı ve Risk Kabulü',
 'Futbol oynamama engel bir sağlık sorunum olmadığını beyan ediyor, riskleri kabul ediyorum.',
 'Uygulamanın 2026-10-v1 sürümündeki kısa sağlık beyanı metni.', true),
('2026-10-v1', 'photo_publish', 40, 'Fotoğraf ve İsim Yayın İzni',
 'Fotoğrafımın ve adımın kadro afişlerinde, haberlerde ve profilimde yayınlanmasına izin veriyorum.',
 'Uygulamanın 2026-10-v1 sürümündeki kısa fotoğraf yayın izni metni.', false)
on conflict (version, key) do nothing;

-- Sürüm 2: 12 Kasım 2026'da doldurulan Sporcu Aydınlatma, Sporcu Açık Rıza
-- ve Sağlık ve Risk Beyanı dökümanları. Bu migration çalıştığı anda yürürlüğe
-- girer.
insert into public.consent_versions (version, effective_from, note)
values ('2026-11-v2', now(),
        '12 Kasım 2026 dökümanları (avukat onayı bekliyor)')
on conflict (version) do nothing;

insert into public.consent_items
  (version, key, sort_order, title, checkbox, body, required)
values
('2026-11-v2', 'privacy_notice', 10, 'Sporcu Aydınlatma Metni',
 'Sporcu Aydınlatma Metni''ni okudum, bilgilendirildim.',
$t$Son güncelleme: 12 Kasım 2026

## Veri sorumlusu
Kişisel verileriniz, veri sorumlusu sıfatıyla Raif Keskin tarafından 6698 sayılı Kişisel Verilerin Korunması Kanunu (KVKK) kapsamında işlenmektedir.
• E-posta: info@ligmasasi.com
• KEP: raif.keskin.1@hs01.kep.tr
• Web: ligmasasi.com
• İletişim KEP ve e-posta üzerinden yürütülür; ayrı posta adresi yoktur.

## İşlenen veriler, amaçlar ve hukuki dayanaklar
Bu metin sporcu verilerine özgüdür. Tüm kullanıcılara ait ortak veriler ile yorum, hata kaydı ve cihaz sayımı verileri Kullanıcı Aydınlatma Metni'nde açıklanmıştır.
• Kimlik bilgileri (ad, soyad, doğum tarihi): sporcu kaydı, yaş ve kontenjan kuralları, kayıt doğrulama. Dayanak: KVKK m.5/2-c; yaş ve kontenjan kontrolü için m.5/2-f.
• İletişim bilgileri (telefon; isteğe bağlı e-posta): hesap oluşturma, doğrulama, sporcu ve organizasyon iletişimi. Dayanak: m.5/2-c; bildirimler için m.5/2-f.
• Sporcu profili ve organizasyon bilgileri (takım, lig, forma numarası, mevki, müsabaka katılımı): profil, kadro ve fikstür yönetimi. Dayanak: m.5/2-c.
• Maç ve performans bilgileri (tarih, yer, takımlar, skor, gol, asist, kart ve ilgili istatistikler): maç sonuçlarının kaydı, skor ve istatistik hizmetleri. Dayanak: m.5/2-c.
• Profil fotoğrafı (isteğe bağlı): profilin görselleştirilmesi, isteğe bağlı görüntüleme ve paylaşım. Dayanak: m.5/1 (açık rıza).
• Boy ve kilo (isteğe bağlı): girilirse profilde herkese açık gösterilir; girilmezse kimseye gösterilmez. Dayanak: m.6/3-a (açık rıza).
• İşlem güvenliği bilgileri (IP adresi, giriş-çıkış ve log kayıtları): bilgi güvenliği ve yetkisiz erişimin önlenmesi. Dayanak: m.5/2-f.
• Başvuru ve destek kayıtları: taleplerin karşılanması, hukuki yükümlülükler. Dayanak: m.5/2-c, ç veya e.
• Sağlık beyanı ("katılmama engel bir sağlık durumum bulunmamaktadır" beyanı, tarihi ve metin sürümü; rapor, teşhis, hastalık veya ilaç bilgisi alınmaz): katılım güvenliği ve beyanın ispatı. Dayanak: m.6/3-a (açık rıza).
• TC kimlik numarası (yalnızca turnuva kuralı gerektiriyorsa; açık olarak saklanmaz, yalnızca geri çevrilemez özeti tutulur): mükerrer kaydın önlenmesi, kayıt doğrulama. Dayanak: m.5/2-f.
• Kimlik doğrulama (isteğe bağlı; kimlik çipinden NFC ile okunan ad, soyad, doğum tarihi ve kartın arka yüz fotoğrafı): fotoğraf yalnızca telefonda işlenip hemen silinir; bilgiler profille eşleşirse saklanmaz, eşleşmezse yalnızca yetkili onayı için tutulur ve talep sonuçlandıktan 30 gün sonra silinir. Saklanan: "onaylı" işareti, tarihi ve yöntemi. Yüz tanıma yapılmaz. Dayanak: m.5/1; turnuva kuralı gerektirdiğinde m.5/2-c ve f.
• Maç kâğıdı (esame) görüntüsü (oyuncu adı ve forma numaraları): kadro ve maç kayıtlarının hızlı ve doğru girilmesi. Dayanak: m.5/2-f.

## Toplanma yöntemi
Verileriniz uygulamadaki kayıt, profil, maç ve istatistik ekranları ile destek kanalları üzerinden elektronik ortamda toplanır. Bilgileri siz girebileceğiniz gibi turnuva sahibi, organizatör, takım sorumlusu veya maç görevlileri de girebilir; başkalarının girdiği bilgiler için düzeltme isteyebilirsiniz.

## Aktarım
• Turnuva sahibi, organizatör, takım yetkilileri ve maç görevlileri: kadro, maç ve istatistik yönetimi.
• Uygulama kullanıcıları ve ziyaretçiler: ad-soyad, takım, maç sonucu ve istatistikler; rıza verilmişse profil fotoğrafı, girilmişse boy ve kilo.
• Barındırma, veritabanı, yazılım ve teknik destek sağlayıcıları: uygulamanın işletilmesi ve güvenliği.
• Yetkili kamu kurumları ve yargı mercileri: hukuken geçerli talepler.
• SMS ve bildirim sağlayıcıları (İletiMerkezi – Türkiye; Google Firebase): doğrulama kodu ve bildirim.
• Yurt dışındaki sağlayıcılar (Supabase – AB/Frankfurt; Google Firebase ve Gemini; OpenWeather; Telegram): barındırma, bildirim, maç kâğıdı okuma, hava durumu (kişisel veri iletilmez), yönetici bildirimleri. Aktarım KVKK m.9 kapsamında veri işleme sözleşmeleri ve uygun güvencelerle yapılır.

## Saklama süreleri
• Profil, kimlik ve iletişim bilgileri: hesap silinene kadar. Hesap silinince telefon, TC özeti, kimlik onayı ve oturum kayıtları silinir; ad-soyad ve doğum tarihi turnuva geçmişinde kalır.
• Maç ve performans istatistikleri: turnuva geçmişinin korunması için ad-soyadla birlikte kalır; talep hâlinde turnuva sahibiyle silme veya anonimleştirme değerlendirilir.
• Profil fotoğrafı: kaldırılana, rıza geri alınana veya hesap silinene kadar.
• Boy ve kilo: silinene, rıza geri alınana veya hesap silinene kadar.
• Destek, hata ve güvenlik kayıtları: en fazla 1 yıl.
• Sağlık beyanı ve onay kayıtları: hesap silinince hesapla bağı koparılarak ispat amacıyla 10 yıl.

## Haklarınız (KVKK m.11)
Verilerinizin işlenip işlenmediğini öğrenme, bilgi isteme, amacını ve alıcılarını öğrenme, düzeltme, silme veya yok edilmesini isteme, bunların alıcılara bildirilmesini isteme, otomatik analiz sonucuna itiraz etme ve zararın giderilmesini isteme haklarına sahipsiniz.

## Başvuru
info@ligmasasi.com (sistemde kayıtlı e-postanızla), KEP (raif.keskin.1@hs01.kep.tr) veya güvenli elektronik/mobil imza ile başvurabilirsiniz. Başvurular en geç 30 gün içinde ücretsiz sonuçlandırılır; Kurula şikâyet hakkınız saklıdır. Açık rızaya dayalı tercihlerinizi uygulamadaki tercih ekranlarından veya e-postayla geri alabilirsiniz.

## Çerezler
Çerez bilgilendirmesi Çerez Aydınlatma Metni'ndedir (ligmasasi.com/cerez). Reklam amaçlı çerez kullanılmaz.$t$, true),

('2026-11-v2', 'health_data', 20, 'Sağlık Beyanının İşlenmesi (Açık Rıza)',
 'Sağlık beyanımın bu metinde belirtilen şekilde işlenmesine açık rıza veriyorum.',
$t$Sporcu Kişisel Verilerinin İşlenmesine İlişkin Açık Rıza Metni — Bölüm 6
Veri sorumlusu: Raif Keskin · info@ligmasasi.com · KEP: raif.keskin.1@hs01.kep.tr

Katıldığım turnuvada futbol veya diğer spor müsabakalarını oynamama engel bir sağlık durumum bulunmadığına ilişkin beyanımın kaydedilmesine ve saklanmasına açık rıza veriyorum. Bu beyan bir sağlık raporu değildir; hastalık, ilaç, teşhis veya rapor bilgisi istenmez ve kaydedilmez.

• İşlenecek veri: "Katılmama engel bir sağlık durumum bulunmamaktadır" beyanım, tarihi ve metin sürümü.
• Amaç: Turnuva katılımının güvenliği; beyanın verildiğinin ve riskin bilinçli kabulünün ispatı.
• Erişebilecekler: Sistem yöneticisi, turnuva sahibi ve yetkili turnuva görevlileri (yalnızca beyanın verilip verilmediği; içerik herkese açık yayımlanmaz).
• Saklama: Hesabım silinene kadar; silindiğinde hesapla bağı koparılarak ispat amacıyla 10 yıl.

Sağlık beyanı turnuvaya katılımın şartı olduğundan, rıza vermemem hâlinde ilgili turnuvalara katılımım mümkün olmayabilir; üyeliğim ve diğer hizmetler bundan etkilenmez. Beyan, katıldığım turnuva ve sezon için geçerlidir ve yeni turnuva/sezonda yeniden alınır.

## Rızanın geri alınması
Açık rızamı gerekçe göstermeden, her işlem için ayrı ayrı, uygulamadaki tercih ekranlarından veya info@ligmasasi.com üzerinden geri alabilirim. Geri alma, önceki hukuka uygun işlemleri geçersiz kılmaz; başka işleme sebebi kalmayan verilerim silinir, yok edilir veya anonim hâle getirilir.$t$, true),

('2026-11-v2', 'health_declaration', 30, 'Sağlık ve Risk Beyanı',
 'Sağlık ve Risk Beyanı''nı okudum; katılmama engel bir sağlık durumum olmadığını beyan ediyor, riskleri kabul ediyorum.',
$t$Katılmak üzere başvuruda bulunduğum spor müsabakası veya turnuvanın fiziksel efor gerektirdiğini ve spor faaliyetlerinin doğası gereği yaralanma, sakatlanma, düşme, çarpışma ve benzeri riskler barındırabileceğini bildiğimi; mevcut sağlık durumumu değerlendirdiğimi ve bilgim dâhilinde söz konusu müsabaka veya turnuvaya katılmama engel teşkil eden herhangi bir hastalık, sakatlık, sağlık sorunu veya fiziksel kısıtlılığımın bulunmadığını beyan ederim.

Sağlık durumumda katılımımı etkileyebilecek herhangi bir değişiklik meydana gelmesi hâlinde müsabakaya katılmamam gerektiğini bildiğimi; sağlık durumuma ilişkin gerçeğe aykırı veya eksik beyanda bulunmamdan ya da bilinen sağlık sorunlarımı dikkate almaksızın müsabakaya katılmamdan kaynaklanan zarar ve olumsuz sonuçlardan kendi kusurum ve hukuki sorumluluğum ölçüsünde sorumlu olduğumu kabul ve taahhüt ederim.

Bu beyan bir sağlık raporu veya tıbbi teşhis niteliği taşımaz; hastalık, ilaç, rapor veya tıbbi geçmiş bilgisi istenmez ve kaydedilmez. Yalnızca beyanım, beyanın tarihi ve metin sürümü kaydedilir; bu bilgiler Sporcu Aydınlatma Metni ve Sporcu Açık Rıza Metni kapsamında işlenir.

Bu beyan, katıldığım turnuva ve sezon için geçerlidir; yeni bir turnuva veya sezona katılımda yeniden verilir. 18 yaşından küçük sporcular adına beyan, velisi veya vasisi tarafından verilir.

İşbu beyanın Lig Masası'nın, turnuva organizatörlerinin veya diğer sorumlu kişilerin kendi kusurlarından ve emredici mevzuattan kaynaklanan sorumluluklarını ortadan kaldırmadığını biliyorum.$t$, true),

('2026-11-v2', 'photo_publish', 40, 'Profil Fotoğrafının Uygulamada Gösterilmesi',
 'Profil fotoğrafımın uygulamada (profil, kadro ve maç ekranları) gösterilmesine açık rıza veriyorum.',
$t$Açık Rıza Metni — Bölüm 2

Yüklediğim veya profilim için iletilen profil fotoğrafımın; profilimin tanınması, takım kadrolarında ve maç ekranlarında diğer sporculardan ayırt edilmem amacıyla kaydedilmesine, saklanmasına ve Lig Masası uygulamasında gösterilmesine ilişkin tercihimdir.

• İşlenecek veri: Profil fotoğrafı.
• Gösterileceği yerler: Sporcu profili, takım kadrosu ve maç ekranları.
• Erişebilecekler: Uygulamayı (mobil ve web) kullanan üyeler ve turnuvaları görüntüleyen ziyaretçiler.
• Saklama: Rızamı geri alana, fotoğrafımı kaldırana veya hesabımı silene kadar.

Bu rıza; fotoğrafımın reklam, sponsor tanıtımı, sosyal medya paylaşımı veya diğer tanıtım faaliyetlerinde kullanılmasını kapsamaz (bkz. sosyal medya ve tanıtım izni). Rıza vermezsem fotoğrafım yalnızca bana görünür.$t$, false),

('2026-11-v2', 'photo_social', 50, 'Fotoğrafın Sosyal Medya ve Tanıtımda Kullanılması',
 'Profil fotoğrafımın Lig Masası''nın sosyal medya hesaplarında ve tanıtım içeriklerinde kullanılmasına açık rıza veriyorum.',
$t$Açık Rıza Metni — Bölüm 3

Profil fotoğrafımın; turnuva ve organizasyonların tanıtılması, duyuruların yapılması, sporcu ve takım başarılarının paylaşılması amacıyla Lig Masası'nın sosyal medya hesaplarında, internet sitesinde ve dijital tanıtım içeriklerinde kullanılmasına ilişkin tercihimdir.

• İşlenecek veri: Profil fotoğrafı.
• Yayın ortamları: Lig Masası'nın Instagram ve diğer sosyal medya hesapları, ligmasasi.com ve dijital tanıtım içerikleri (maç afişi, haftanın enleri, gol kesiti vb.).
• Erişebilecekler: Bu ortamlara erişebilen herkes.
• Süre: Rızamı geri alana kadar. Geri alma sonrasında yeni içeriklerde kullanılmaz; önceden yayımlanmış içerikler makul sürede kaldırılır.

Bu izni vermemem, fotoğrafımın uygulama içinde gösterilmesine ilişkin ayrı tercihimi etkilemez. Sosyal medyada yayımlanan içeriklerin başkalarınca kaydedilebileceği veya yeniden paylaşılabileceği konusunda bilgilendirildim.$t$, false),

('2026-11-v2', 'height_weight', 60, 'Boy ve Kilo Bilgilerinin Profilde Gösterilmesi',
 'Girdiğim boy ve kilo bilgilerimin profilimde herkese açık gösterilmesine açık rıza veriyorum.',
$t$Açık Rıza Metni — Bölüm 4

İsteğe bağlı olarak girdiğim boy ve kilo bilgilerimin kaydedilmesine ve sporcu profilimde herkese açık gösterilmesine ilişkin tercihimdir.

• İşlenecek veriler: Boy ve kilo.
• Amaç: Sporcu profilinin kişiselleştirilmesi ve bu bilgilerin profilde gösterilmesi.
• Gösterileceği yer ve erişebilecekler: Profilimin künye bölümü; uygulamayı (mobil ve web) kullanan tüm üyeler ve ziyaretçiler.
• Saklama: Bilgileri silene, rızamı geri alana veya hesabımı silene kadar.

Bu bilgileri girmek tamamen isteğe bağlıdır. Girmediğim sürece boy ve kilo bilgilerim hiçbir kullanıcıya gösterilmez; girdiğim bilgileri profil düzenleme ekranından istediğim zaman silebilirim.$t$, false)
on conflict (version, key) do nothing;

-- Lisans listesi: onay tamamlığı sürüm kuralıyla (player_consent_complete).
CREATE OR REPLACE FUNCTION public.license_list(p_filter jsonb DEFAULT '{}'::jsonb, p_q text DEFAULT ''::text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_admin boolean := public.is_admin();
  v_roster text := coalesce(p_filter->>'roster', 'in');
  v_staff boolean := false;
  v_league text := coalesce(p_filter->>'league', 'all');
  v_profile text := coalesce(p_filter->>'profile', 'all');
  v_account text := coalesce(p_filter->>'account', 'all');
  v_kvkk text := coalesce(p_filter->>'kvkk', 'all');
  v_q text := public.tr_fold(trim(coalesce(p_q, '')));
  v_out jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('total', 0, 'rows', '[]'::jsonb);
  end if;
  -- Kurucu başkan / bölge sorumlusu: kendi kadroları + boştaki oyuncular
  -- (hiçbir etkin kadroda olmayan; başka turnuvadan gelebilecek).
  v_staff := exists (select 1 from public.league_owners where user_id = v_uid)
          or exists (select 1 from public.region_owners where user_id = v_uid);

  with act as (
    select s.id as season_id, l.id as league_id
      from public.seasons s
      join public.leagues l on l.id = s.league_id
     where s.deleted_at is null
       and coalesce(l.status, '') <> 'passive'
       and l.is_active is not false
  ),
  roster as (
    select stp.player_id, act.league_id, st.group_id
      from public.season_team_players stp
      join act on act.season_id = stp.season_id
      left join public.season_teams st
        on st.season_id = stp.season_id and st.team_id = stp.team_id
     where stp.player_id is not null
       and stp.is_active is not false
  ),
  vis as (
    select r.* from roster r
     where v_admin
        or exists (select 1 from public.league_owners lo
                    where lo.league_id = r.league_id and lo.user_id = v_uid)
        or exists (select 1 from public.groups g
                     join public.region_owners ro on ro.region_id = g.region_id
                    where g.id = r.group_id and ro.user_id = v_uid)
  ),
  kv as (
    select x.player_id, public.player_consent_complete(x.player_id) as complete
      from (select distinct c.player_id from public.player_consents c) x
  ),
  base as (
    select p.id, p.name, p.surname, p.birth_date, p.preferred_foot,
           p.main_position, p.sub_position, p.photo_url,
           case when v_admin or exists (select 1 from vis v where v.player_id = p.id)
                then p.phone end as phone,
           p.height,
           p.weight, p.created_at, p.updated_at,
           exists (select 1 from roster r where r.player_id = p.id) as in_roster,
           coalesce((select array_agg(distinct v.league_id) from vis v
                      where v.player_id = p.id), '{}') as leagues,
           exists (select 1 from public.player_verifications pv
                    where pv.player_id = p.id) as verified,
           p.auth_uid is not null as has_account,
           coalesce(kv.complete, false) as kvkk,
           public.tr_fold(concat_ws(' ', p.name, p.surname)) as folded
      from public.players p
      left join kv on kv.player_id = p.id
     where v_admin or exists (select 1 from vis v where v.player_id = p.id)
        or (v_staff and not exists (select 1 from roster r where r.player_id = p.id))
  ),
  f as (
    select b.*,
      (v_roster = 'all' or (v_roster = 'in') = b.in_roster) as pr,
      (v_league = 'all' or v_league = any (b.leagues::text[])) as pl,
      (v_profile = 'all' or (v_profile = 'ver') = b.verified) as pp,
      (v_account = 'all' or (v_account = 'yes') = b.has_account) as pa,
      (v_kvkk = 'all' or (v_kvkk = 'ok') = b.kvkk) as pk,
      (v_q = '' or strpos(b.folded, v_q) > 0) as pq
    from base b
  )
  select jsonb_build_object(
    'total', (select count(*) from f where pr and pl and pp and pa and pk and pq),
    'rows', coalesce((
      select jsonb_agg(to_jsonb(x) - 'folded' - 'pr' - 'pl' - 'pp' - 'pa' - 'pk' - 'pq'
                       order by x.folded)
        from (select * from f where pr and pl and pp and pa and pk and pq
               order by folded offset greatest(p_offset, 0)
               limit least(greatest(p_limit, 0), 200)) x), '[]'::jsonb),
    'banner', (select jsonb_build_object(
                 'missing', count(*) filter (where not kvkk),
                 'no_account', count(*) filter (where not kvkk and not has_account))
               from base where in_roster),
    'leagues', coalesce((
      select jsonb_object_agg(l.id, l.name)
        from public.leagues l
       where l.id in (select distinct league_id from vis)), '{}'::jsonb),
    'facets', jsonb_build_object(
      'roster', (select jsonb_build_object(
          'in', count(*) filter (where in_roster),
          'free', count(*) filter (where not in_roster),
          'all', count(*))
        from f where pl and pp and pa and pk and pq),
      'league', coalesce((
          select jsonb_object_agg(k, n) from (
            select 'all' as k, count(*) as n from f where pr and pp and pa and pk and pq
            union all
            select lid::text, count(*) from f, unnest(f.leagues) lid
             where pr and pp and pa and pk and pq group by lid) z), '{}'::jsonb),
      'profile', (select jsonb_build_object(
          'all', count(*), 'ver', count(*) filter (where verified),
          'unv', count(*) filter (where not verified))
        from f where pr and pl and pa and pk and pq),
      'account', (select jsonb_build_object(
          'all', count(*), 'yes', count(*) filter (where has_account),
          'no', count(*) filter (where not has_account))
        from f where pr and pl and pp and pk and pq),
      'kvkk', (select jsonb_build_object(
          'all', count(*), 'ok', count(*) filter (where kvkk),
          'wait', count(*) filter (where not kvkk))
        from f where pr and pl and pp and pa and pq)
    )
  ) into v_out;
  return v_out;
end;
$function$;
