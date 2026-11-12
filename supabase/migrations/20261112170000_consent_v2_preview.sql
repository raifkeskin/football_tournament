-- Onay metinleri v2 (12 Kasım dökümanları) avukat onayına kadar TASLAK:
-- yalnız admin ve deneme listesindeki hesaplar (consent_preview_users) görür
-- ve onaylayabilir; diğer herkes 2026-10-v1 metinlerini görmeye devam eder.
--
-- YAYINA ALMAK (uygulama sürümü gerekmez):
--   update public.consent_versions set effective_from = now()
--    where version = '2026-11-v2';
-- Sezon sağlık beyanı kartı da aynı deneme listesine açıktır
-- (season_health_enabled kapalıyken).

insert into public.app_settings (key, value)
values ('consent_preview_users', '["a1da69df-7398-4bd9-9080-fa65ed873fb0"]'::jsonb)
on conflict (key) do nothing;

create or replace function public.consent_preview_on()
returns boolean
language sql
stable security definer
set search_path to ''
as $$
  select public.is_admin() or coalesce((
    select s.value ? auth.uid()::text from public.app_settings s
     where s.key = 'consent_preview_users'), false)
$$;

grant execute on function public.consent_preview_on() to anon, authenticated;

-- v2 taslak: yürürlük tarihi ileriye alınır (yayında now() yapılır).
update public.consent_versions
   set effective_from = timestamptz '2099-01-01 00:00:00+03',
       note = '12 Kasım 2026 dökümanları — TASLAK, avukat onayı bekliyor'
 where version = '2026-11-v2';

-- Yürürlükteki sürüm; deneme hesapları taslak dahil en yeni sürümü görür.
create or replace function public.current_consent_version()
returns text
language sql
stable
set search_path to ''
as $$
  select coalesce((
    select v.version from public.consent_versions v
     where v.effective_from <= now() or public.consent_preview_on()
     order by v.effective_from desc
     limit 1), '2026-10-v1')
$$;

create or replace function public.season_health_on()
returns boolean
language sql
stable security definer
set search_path to ''
as $$
  select public.consent_preview_on() or coalesce((
    select value = 'true'::jsonb from public.app_settings
     where key = 'season_health_enabled'), false)
$$;

-- v1 kutuları: yeni uygulama metni sunucudan okur; uygulamanın gösterdiği
-- tam v1 metinleri (önceki hâli yalnız özet yer tutucuydu).
update public.consent_items set body = $t$6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") kapsamında, turnuvaya katılımınız için kişisel verileriniz aşağıda açıklandığı şekilde işlenir.

İşlenen veriler: Ad, soyad, doğum tarihi, cep telefonu, fotoğraf, mevki ve fiziksel bilgiler (boy, kilo — isteğe bağlı), takım ve maç bilgileri (gol, kart, maç kadrosu), sağlık beyanı (yalnızca "oynamaya engel durumum yok" beyanı ve tarihi; sağlık durumunuzun ayrıntısı tutulmaz).

Amaçlar: Turnuvanın düzenlenmesi, kadro ve lisans işlemleri, fikstür, maç sonuçları ve istatistiklerin tutulup yayınlanması, yaş ve kontenjan kurallarının uygulanması, sizinle iletişim kurulması.

Hukuki sebepler: Turnuvaya katılım sözleşmesinin kurulması ve ifası (KVKK m.5/2-c), veri sorumlusunun meşru menfaati (m.5/2-f); sağlık beyanı ve fotoğrafınızın yayınlanması için açık rızanız (m.6 ve m.5/1).

Aktarım: Verileriniz turnuva sahibi, takım sorumlunuz ve maç görevlileriyle paylaşılır. Maç sonuçları, kadrolar ve istatistikler uygulamada herkese açık yayınlanabilir (doğum tarihinizin tamamı, telefonunuz ve sağlık beyanınız yayınlanmaz). Uygulamanın barındırma ve veritabanı hizmetleri yurt dışında bulunan hizmet sağlayıcılar üzerinden yürütülür.

Saklama süresi: Verileriniz turnuva süresince ve sonrasında yasal yükümlülükler ile olası uyuşmazlıklar için gereken süre boyunca saklanır, ardından silinir veya anonim hâle getirilir.

Haklarınız (KVKK m.11): Verilerinizin işlenip işlenmediğini öğrenme, bilgi talep etme, düzeltilmesini veya silinmesini isteme, aktarıldığı kişileri öğrenme, itiraz etme ve zararın giderilmesini talep etme haklarına sahipsiniz. Başvurularınızı turnuva sahibine veya uygulama yöneticisine iletebilirsiniz.$t$
 where version = '2026-10-v1' and key = 'privacy_notice';
update public.consent_items set body = $t$Turnuvada oynamanıza engel bir sağlık durumu bulunmadığına ilişkin beyanınız, KVKK m.6 kapsamında özel nitelikli kişisel veri (sağlık verisi) sayılır.

Bu beyan yalnızca "beyan verildi / verilmedi" ve tarih bilgisi olarak saklanır; hastalık, ilaç veya rapor gibi ayrıntılar istenmez ve tutulmaz. Beyan yalnızca turnuva sahibi ve yetkili görevlilerce görülebilir, herkese açık yayınlanmaz.

Bu rızayı dilediğiniz zaman profilinizden geri alabilirsiniz. Rızanın geri alınması, geri alma tarihine kadar yapılan işlemleri etkilemez; ancak turnuva kurallarına göre maçlarda oynamanız kısıtlanabilir.$t$
 where version = '2026-10-v1' and key = 'health_data';
update public.consent_items set body = $t$Futbol oynamama engel olabilecek bir sağlık sorunum (kalp, tansiyon, solunum rahatsızlığı, yakın tarihli ameliyat veya sakatlık vb.) bulunmadığını, gerekli gördüğüm durumlarda doktor kontrolünden geçtiğimi beyan ederim.

Futbolun doğası gereği sakatlanma ve yaralanma riskleri taşıdığını biliyor ve bu riskleri kabul ediyorum. Sağlık durumumda oynamama engel olabilecek bir değişiklik olursa turnuva sahibini bilgilendireceğimi ve maçlara katılmayacağımı taahhüt ederim.

Bu beyan; turnuva sahibinin, organizatörlerin veya uygulama sahibinin kast veya ağır kusurundan doğan sorumluluğunu kaldırmaz.$t$
 where version = '2026-10-v1' and key = 'health_declaration';
update public.consent_items set body = $t$Fotoğrafınız ve adınız; kadro afişlerinde, maç ve turnuva haberlerinde, oyuncu profilinizde ve turnuvanın sosyal medya paylaşımlarında kullanılabilir.

Bu izin isteğe bağlıdır. İzin vermemeniz turnuvaya katılımınızı etkilemez. İzninizi dilediğiniz zaman profilinizden geri alabilirsiniz; geri alma öncesinde yapılmış paylaşımlar için turnuva sahibinden kaldırılmasını talep edebilirsiniz.$t$
 where version = '2026-10-v1' and key = 'photo_publish';
