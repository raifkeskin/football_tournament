# Avukata toplu sorular ve "biz böyle doldurduk" kayıtları (12 Kasım 2026)

Doldurulmuş kopyalar `~/Downloads` altında "- Dolduruldu" ekiyle; orijinallere dokunulmadı.
Her maddede: **Biz böyle doldurduk** → **Avukata soru**.

## Genel
- Veri sorumlusu şahıs: Raif Keskin. "Şirket / MERSİS / tescilli adres" alanları buna göre dolduruldu; adres yerine KEP (raif.keskin.1@hs01.kep.tr), e-posta info@ligmasasi.com, site ligmasasi.com. "Yazılı (ıslak imzalı) başvuru / posta adresi" satırı kaldırıldı.
  - Soru: Şahıs veri sorumlusunda adres yerine KEP yeterli mi, ıslak imzalı başvuru satırını kaldırmak sorun yaratır mı? VERBİS kaydı/muafiyeti? Şirket kurulunca hangi metinler güncellenir?
- Yurt dışı aktarım (Supabase-Frankfurt, Google Firebase/Gemini, OpenWeather, Telegram): "KVKK m.9 kapsamında hizmet sağlayıcı sözleşmeleri ve uygun güvenceler" diye yazdık.
  - Soru: m.9 güncel mekanizması (standart sözleşme bildirimi vb.) ve metin doğru mu? Açık rıza da alınmalı mı?
- Kanun madde numaraları (özellikle m.6/3-a) orijinal şablondaki gibi bırakıldı. Soru: 7499 sayılı değişiklik sonrası numaralar doğru mu?

## 1. Çerez Aydınlatma Metni (docx + web/cerez.html)
- Reklam/analiz çerezi yok diye yazıldı; 9 teknoloji tablolandı; çerez onay penceresi yok; cihaz sayımı (rastgele kod+platform+sürüm) meşru menfaat.
- Soru: Onay penceresi gerekmiyor görüşümüz doğru mu? YouTube/Instagram gömmeleri için "dokununca yükle" şart mı? Cihaz sayımı meşru menfaatle yürütülebilir mi?

## 2. Sporcu Aydınlatma Metni
- Eklenen satırlar: sağlık beyanı (m.6/3-a açık rıza), TC kimlik (yalnızca hash, meşru menfaat), kimlik doğrulama NFC (isteğe bağlı, açık rıza), maç kâğıdı görüntüsü; SMS/bildirim ve yurt dışı aktarım satırları; saklama süreleri dolduruldu.
- Soru: TC hash'i için m.5/2-f yeterli mi? Boy-kilo özel nitelikli sayılır mı (şablonda öyle yazıyordu, öyle bıraktık)? NFC/kimlik doğrulamada açık rıza doğru dayanak mı?

## 3. Sporcu Açık Rıza
- Boşluklar uygulamanın gerçek davranışına göre dolduruldu. Yeni Bölüm 7 "Sağlık Beyanının İşlenmesi" eklendi (beyan = "katılmama engel durum yok"; rapor/teşhis yok; katılım şartı olduğundan rıza verilmezse o turnuvaya katılım mümkün olmayabilir). Eski 7 → 8.
- Soru: Katılım şartı olan sağlık beyanında açık rıza serbest irade sayılır mı, yoksa başka dayanak mı? Boş bırakılan rıza için "rıza verilmemiş sayılır" ile "katılım şartı" çelişmiyor mu?
- Çelişki: Bölüm 6 "herkese açık ad/istatistik yayını" isteğe bağlı rıza gibi yazılı; oysa uygulamada ad ve istatistikler zaten herkese açık yayınlanıyor (temel hizmet). Soru: temel hizmet kapsamında m.5/2-c ile mi yayınlıyoruz, Bölüm 6'yı mı kaldırıyoruz? **Uygulama tarafı da kontrol edilmeli.**

## 4. Sağlık ve Risk Beyanı
- Metin korundu; "rapor/teşhis değildir, yalnızca beyan+tarih+sürüm saklanır", "turnuva/sezon için geçerli", "18 yaş altı için veli/vasi" paragrafları eklendi.
- Soru: Bu beyan özel nitelikli sağlık verisi mi (içerik "engel yok")? 18 yaş altı için veli beyanı yeterli mi?

## 5. Kullanıcı (Ziyaretçi) Aydınlatma Metni
- Başlık "Kullanıcı Aydınlatma Metni" yapıldı (Üye Sözleşmesi bu adla atıf yapıyor). Web Sitesi satırındaki hata düzeltildi. Yorum/tepki/anket, hata kaydı, cihaz sayımı satırları ve yurt dışı aktarım eklendi.
- Soru: Haber yorumları adı+takımla herkese açık; bunun dayanağı m.5/2-c yeterli mi?

## 6. Üye Sözleşmesi
- "Şirket" → "Hizmet Sağlayıcı" (şahıs olduğu için); 3.6 (18 yaş altı), 6.7/6.8 (beyan rapor değil, sezon başına), 11.4 (çerez), 15.2 (tüketici hakları saklı) eklendi.
- Soru: 15.2 İstanbul yetki maddesi tüketicide geçersiz olabilir, eklediğimiz saklı tutma cümlesi yeterli mi? "Hizmet Sağlayıcı" tanımı şahıs için uygun mu? Sorumluluk sınırlama maddeleri (13) yeterli mi?
- **Uygulama boşluğu:** 6.8 sezon bazlı sağlık beyanı istiyor; uygulama şu an oyuncu başına tek seferlik alıyor. Geliştirme gerekli (yeni özellik → önce admin kapısı).

## 7. Kişisel Verileri Saklama ve İmha Politikası (yeni taslak)
- Hesap silme akışı koddan doğrulandı (telefon, TC, foto, boy-kilo silinir; ad-soyad+doğum tarihi turnuva geçmişinde kalır; onay kayıtları hesapla bağı koparılarak kalır).
- Bizim önerdiğimiz süreler: onay/sağlık kaydı 10 yıl, hata/destek/log en fazla 1 yıl, periyodik imha 6 ayda bir.
- Soru: Süreler uygun mu? Ad-soyad+doğum tarihini hesap silince anonimleştirmek gerekir mi? Log saklama için yasal asgari süre var mı (5651)?
- **Uygulama boşluğu:** "1 yıl" ve "6 ayda bir imha" için otomatik silme işi yok; kurulması gerekir.

## Yayın bekleyen
- web/cerez.html yayınlanmadı. Diğer metinlerin web sayfaları (kullanıcı/sporcu aydınlatma, açık rıza, üyelik sözleşmesi) ve uygulamadaki onay ekranı metinleri (consent_texts.dart, sürüm 2026-10-v1) avukat onayından sonra güncellenecek.

## Son gözden geçirme (12 Kasım 2026)
- Avukata gidecek nihai soru listesi: `~/Downloads/Avukata Sorular - Lig Masası Hukuki Metinler.docx` (8 başlık, 36 soru + uyumsuzluklar).
- Düzeltilen: "veri sorumlusu ... veri sorumlusu tarafından" tekrarı; yurt dışı satırındaki "yukarıdaki açıklama" → "tablonun altındaki açıklama".
- Koddan doğrulanan: sağlık beyanı durumunu turnuva sahibi lisans listesinde görüyor (detay değil); yorumlar hesap silinince siliniyor (FK cascade).
- **Yeni uygulama boşluğu:** boy/kilo oyuncu profilinde (player_card Künye) herkese görünüyor, players tablosu herkese okunabilir ve ayrı rıza yok; Açık Rıza 5. bölüm "yalnız yetkililer" diyor.

## Boy-kilo kararı (12 Kasım 2026)
- Kullanıcı kararı: boy-kilo tamamen isteğe bağlı; girilirse profilde herkese açık, girilmezse kimseye gösterilmez.
- Açık Rıza 4+5 birleştirildi (yeni numaralar: 5 herkese açık yayın, 6 sağlık, 7 geri alma); Sporcu Aydınlatma veri/aktarım/saklama satırları güncellendi; avukat dosyasına 4.3 sorusu eklendi, uyumsuzluk maddesi kaldırıldı.
- Uygulamada yapılacak küçük iş: profil düzenlemede boy-kilo altına "Girersen profilinde herkese görünür" notu.

## Uygulamaya geçenler (12 Kasım 2026, feat/kvkk-onaylar → release)
- Boy-kilo alanlarına "girersen profilinde herkese görünür" notu (profil düzenleme + futbolcu kaydı).
- Sezon bazlı sağlık beyanı: `player_season_declarations` + `my_pending_health_seasons` + `give_season_health_declarations`; Ana Sayfa kartı (SeasonHealthCard); kadroya eklenince push (yalnız anahtar herkese açıkken). Anahtar `season_health_enabled` = false (yalnız admin). 2026-11-13 öncesi sezonlarda eski profil beyanı geçerli sayılır. Açılırsa beyanı olmayan ~35/60 hesaplı futbolcu kart görür.
  - Açmak: `update app_settings set value='true' where key='season_health_enabled';`
  - Henüz yok: lisans listesinde sezon bazlı beyan sütunu; hesabı olmayan oyuncular için kâğıt beyan.
- Periyodik imha: `retention_purge()` + cron `retention-purge` her ayın 1'i 04:23 UTC; `retention_log`'a yazar. İlk çalıştırma (deneme): silinecek kayıt yok.
- Metinler buna göre güncellendi: Saklama politikası tablosu (30 gün kimlik eşleşme, 90 gün bekleyen ibraz TC, aylık imha), Sporcu Aydınlatma NFC satırı, avukat dosyası.
