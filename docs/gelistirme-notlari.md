# Yapılacak Geliştirme Notları

Konuşmalarda "nota ekleyelim" denilen fikirler. Her madde geliştirmeden önce ayrıca planlanır.

---

## 1. Yaş sınırı ve yaş kontenjanı (turnuva kuralları)
_Eklendi: 2026-10-03_

- Turnuvalar genelde **35+** yaş grubunda oynanıyor. Yaş sınırı turnuva kurallarında tanımlanacak.
- **Kontenjan kuralı:** Yaş sınırının altındaki belirli doğum yıllarından sınırlı sayıda oyuncu oynatılabilecek.
  - Örnek: 40 yaş altı için **1989-1990-1991** doğumlu en fazla **3 oyuncu**.
- Turnuva (sezon) ayarlarında tanımlanabilir olmalı:
  - Alt yaş sınırı (ya da en geç doğum yılı)
  - Kontenjan doğum yılları (aralık)
  - Kontenjan oyuncu sayısı
- Sistem kuralı aşan kadro eklemesini uyarmalı ya da engellemeli.
- **Netleşecek:** Kontenjan **kadrodaki** oyuncu sayısını mı, **sahada aynı anda** oynayan oyuncu sayısını mı sınırlıyor? (Sahadaki sınır maç içi takip gerektirir.)
- Not: 18 yaş altı oyuncu yok, bu yüzden KVKK'da veli onayı gerekmiyor.

## 2. Turnuva düzenleme başvurusu ve fiyatlandırma akışı
_Eklendi: 2026-10-03_

Uygulama içinden turnuva düzenlemek isteyenler için başvuru akışı:

1. **Tanıtım:** Uygulamanın neler sunduğunu anlatan kısa bir bilgilendirme.
2. **Ücret bilgisi:** Fiyatlandırmanın nasıl işlediğine dair kısa açıklama.
3. **Sorular:** Kullanıcıdan şu bilgiler alınır:
   - Takım sayısı
   - Grup sayısı
   - Toplam oynanacak maç sayısı
4. **Fiyat görseli:** Cevaplara göre hesaplanan fiyatlandırma görsel olarak gösterilir.
5. **Başvuru gönderimi:** Başvuru yöneticiye iletilir (mevcut Telegram bildirimine bağlanabilir).
6. **Turnuva Sahibi Sözleşmesi kabulü:** Başvurunun son adımında alınır (KVKK planıyla bağlantılı). Organizatör sorumluluğu, sigorta ve veri sorumlusu rolleri bu sözleşmede yer alır.

- **Netleşecek:** Fiyatlandırma modeli (maç başı, takım başı, sabit paket?).

## 3. Fikstür kurası (lig aşaması eşleşmeleri) — YAPILDI (2026-10-03)

- Fikstür Planlama → grup seçilince **Kura** satırı. Grupta maç varsa kura çekilemez.
- Tek maç / rövanşlı, sezon ayarındaki **Rövanşlı** anahtarından alınır.
- Herkes herkesle; her hafta bir takım en fazla bir maç; tek sayıda takımda bay. Ev sahibi sayıları dengelenir; rövanşta ev sahibi değişir.
- Önizleme: başlangıç haftası değiştirilebilir, **Yeniden Çek / İptal / Kaydet**. Maçlar tarih-saat belirsiz, tek istekte kaydedilir.
- Haftalık tekrarla (2 takımlı gruplar) da Fikstür Planlama'da.

## 4. KVKK onayı olmayan oyuncunun esameye eklenmemesi (market sonrası)
_Eklendi: 2026-10-03_

- Şimdilik **uygulanmayacak**: onayı olmayan oyuncu kadroda ve esamede yer alabilir, sadece uyarı/bilgi gösterilir.
- Uygulama markete çıkıp yeni turnuvalar açıldığında: KVKK + sağlık onayı vermemiş oyuncu **maç esamesine eklenemez**.
- Mevcut turnuvalara geriye dönük uygulanıp uygulanmayacağı o zaman kararlaştırılacak (turnuva bazlı ayar olabilir).

## 5. Bildirime dokununca ilgili sayfanın açılması (deep link) — BÜYÜK ÖLÇÜDE YAPILDI
_Eklendi: 2026-10-03 · Güncellendi: 2026-10-18_

- **Çalışıyor** (`notification_router.dart`, web + APK): maç bildirimleri (gol, canlı, sonuç, saat değişikliği, hatırlatma) → maç detayı; haber → Turnuva Sayfası Haberler (haber açık); kadro talebi, Instagram onayı, yayın uyuşmazlığı → Bekleyen Onaylar; ceza → Ceza Yönetimi.
- **Kalan (düşük):** "haftanın fikstürü açıklandı" gibi bir bildirim henüz yok; eklenirse `fixture-<sezon>:<hafta>` türüyle Turnuva Sayfası Fikstür sekmesinin o haftası açılır. `roster-` (talebiniz onaylandı) ve `penaltyok-` bildirimleri yalnız uygulamayı açar.

## 7. Sponsor bölümü — YAPILDI (2026-10-07)
_Eklendi: 2026-10-07_

- **Kararlar:** Sponsorlar **turnuvaya** bağlı (sezona değil). İki tür: **ana sponsor** ve **alt sponsor**. Alanlar: ad, logo, (isteğe bağlı) link, sıra, aktif/pasif.
- **Yetki:** Yalnızca admin ve o turnuvanın kurucu başkanları ekler/düzenler. "Sponsor Yönetimi" kartı başkalarına (bölge sorumlusu dahil) görünmez.
- **Gösterim:** Şimdilik **yalnızca ana sayfada**, turnuva bandının hemen altında ince beyaz şerit (taslaktaki 2. seçenek). Şerit sırayla döner: önce ana sponsorlar (birden fazla olabilir, sıralarına göre), ardından alt sponsorlar.
- **Süreler turnuva ayarında:** Turnuva Ekle/Düzenle popup'ına "Sponsor gösterim süresi" alanı: **ana sponsor** (öneri varsayılan 8 sn) ve **alt sponsor** (öneri 4 sn) ayrı ayrı.
- **Ayrıntılar:** Sponsor yoksa şerit hiç çıkmaz; logoya dokununca link açılır; şeritte "ANA SPONSOR" / "SPONSOR" etiketi; ekran arka plandayken dönüş durur.
- Yan menüdeki ayrı "Sponsorlar" sayfası şimdilik **yok** (ileride istenirse taslağı hazır).
- Mağaza beyanı değişmez (yeni kullanıcı verisi yok).

## 8. Yetkisiz ekran koruması (ortak yetki kapısı)
_Eklendi: 2026-10-07_

- Tek ortak bileşen: her yönetim ekranı hangi rollerin girebileceğini söyler (ör. admin + kurucu başkan). Yetkisiz kişi ekranı görmez; "Bu ekrana erişim yetkiniz yok" kartı + Geri.
- Deneme `app_errors` tablosuna ve Telegram'a "yetkisiz ekran denemesi: ekran, rol" diye düşer (gözden kaçan menü/düğme hemen fark edilir).
- Veritabanı "yetkiniz yok" (RLS) dediğinde teknik mesaj yerine anlaşılır uyarı.
- Kapsam: ~15 yönetim ekranı, tahmini yarım gün. Sponsor ekranı bu yapıyla kurulabilir.

**Yapılacaklar özeti (2026-10-18):**
1. `AccessGate(roles: [...], child: ...)` bileşeni: `AppSession` rolüne bakar; yetki yoksa ekran yerine "Bu ekrana erişim yetkiniz yok" kartı + Geri düğmesi.
2. Her yönetim ekranının girişine sarılır (Turnuva / Takım / Lisans / Fikstür Planlama / Canlı Kura / Ceza / Haber / Sponsor / Hakem / Bekleyen Onaylar / admin panelleri). Rol listesi rol hiyerarşisine göre (admin > kurucu başkan > bölge sorumlusu > futbolcu > misafir; üst rol alttakinin yetkisini taşır, yalnız kendi turnuvası).
3. Yetkisiz deneme `app_errors`'a `screen` + `last_role` ile yazılır, Telegram'a düşer.
4. Ortak hata çevirisi: PostgrestException 42501 / RLS → "Bu işlem için yetkiniz yok."
5. Veritabanı tarafı değişmez (RLS zaten asıl koruma); bu katman kullanıcı deneyimi ve erken uyarı içindir.

## 9. App Store incelemesi: ekran kaydı + bilgi cevabı (iOS 1.0)
_Eklendi: 2026-10-08_

- Apple 1.0'ı **Guideline 2.1 – Information Needed** ile geri çevirdi (yeni geliştirici hesabı için ek bilgi istiyor). Kod değişikliği gerekmiyor; aynı derleme yeniden incelemeye girer.
- **Ekran kaydı eşimin iPhone'uyla çekilecek** (gerçek cihaz + güncel iOS şart; uygulama TestFlight'tan kurulacak). Kayıt uygulamanın açılışıyla başlamalı:
  1. Açılış → giriş ekranı
  2. "Kayıt Ol" → talep gönderme ve "admin onayından sonra şifre gelir" mesajı
  3. "Misafir olarak devam et" → puan durumu, fikstür, maç detayı, haberler, oyuncu/takım sayfaları
  4. Demo hesapla giriş (5000000000 / demo2026) → profil, takım, maç, bildirimler
  5. **Hesap silme ayrı bir test hesabıyla** (demo hesabı silinmesin!): Profil → Çıkış Yap → Hesabımı Sil → onay → giriş ekranı
- Silme testi hesabı: **500 000 00 01 / demotest** ("Demo Test", iki demo turnuvasında kurucu başkan). Silindikten sonra tekrar gerekirse Claude aynı kimlikle (`…0000000000ab`) yeniden açabilir. Demo hesabı 2026-10-08'de yanlışlıkla silinmiş, aynı kimlikle geri açıldı.
- Video + İngilizce cevap metni hem Resolution Center'a cevap olarak hem de App Review Information → Notes alanına eklenecek. Metinde: amaç/kitle, misafir modu + demo hesap, kayıt akışı, hesap silme yeri, herkese açık kullanıcı içeriği olmadığı (haberleri yalnızca admin girer, yorum/sohbet yok), ücretli özellik yok, dış servisler (Supabase, Firebase Hosting, YouTube, Telegram), bölge farkı yok, düzenlemeye tabi alan değil.
- Göndermeden önce: demo hesabın rolüne bak (Apple her hesap türü için giriş bilgisi istiyor, gerekirse yönetici demo hesabı da ekle); mağazada yalnızca Türkiye seçiliyse 5. maddeyi buna göre düzelt.
- **2026-10-08 13:43 gönderildi:** kesilmiş video (`~/Downloads/iosVideo_apple.mp4`, açılıştan kayıt talebine 2:34, sessiz) + İngilizce metin Resolution Center'a yazıldı; durum "Ready for Review".

## 10. Sezon verisini CDN'den sunmak (ölçek: binlerce eşzamanlı kullanıcı)
_Eklendi: 2026-10-11_

- **Ne:** Sezonun takım, kadro, fikstür ve grup verisi değiştiğinde JSON dosyası olarak CDN'e yazılır. Açılışta herkes bu dosyayı okur, veritabanına sorgu gitmez.
- **Neden bekliyor:** Sürüm önbelleği (data_versions) açılış yükünün büyük kısmını aldı. CDN'in getirisi asıl maç günü: sezon sayacı her golde arttığı için açılışlar yine veritabanına gidiyor.
- **Karar ölçütü:** Pro'ya geçince 500–1.000 kişilik test yapılacak. Maç günü açılışları veritabanını zorlarsa önce daha basit adım denenecek: sezonun tüm verisini tek istekte döndüren veritabanı fonksiyonu (8 sorgu → 1). CDN ancak o da yetmezse yapılacak.
- **Dikkat:**
  - Gizli ve demo turnuvalar herkese açık CDN'den sunulamaz; onlar veritabanından okumaya devam eder.
  - Dosyayı her değişiklikte yeniden üreten bir mekanizma gerekir (tetikleyici → Edge Function → Storage).
- **Tahmini iş:** ~1 gün.

## 13. Halısaha videolarından gol kesitleri (dakikasız)
_Eklendi: 2026-10-14_

- **Şu an:** Kesitler, maç detayındaki gol dakikalarının çevresinde aranıyor (maç başına ~0,04 $). Sezonda "Gol Dakikası" kapalıysa (halısaha) onaylı gol videoları herkese görünüyor, ama YZ analizini yalnız admin başlatabiliyor ve tüm video taranıyor; tahmini maliyet sınırı aşarsa analiz başlamıyor.
- **Sorun:** Dakika yoksa 60 dakikanın tamamını taramak gerekir. Tahmini maliyet kamera başına 0,40–0,60 $, yani mevcut 0,50 $/maç limitine takılır. Bazı halısahalarda iki kamera var; bu da maliyeti ikiye katlar.
- **Önerilen yol:**
  - Başlama vuruşu bulunur, iki kamera bununla senkronlanır.
  - Video düşük kare hızında (ör. 10 sn'de 1 kare) taranır, yalnız kutlama ve santra anları işaretlenir. Maçtaki gol sayısı ve sırası bilindiği için sonuç doğrulanabilir.
  - Bulunan anlar çevresinde ±1 dakikalık ayrıntılı kesit alınır.
  - İki kamerada gol yalnız birinde (geniş açı) aranır. Her gol için diğer kameranın ±30 sn'sine bakılıp "kaleye yakın ve net olan" seçilir. Devre arası taraf değiştiği için karar gol başına verilir.
  - Maç medyasında video linkine "Kamera 1 / Kamera 2" etiketi gerekir.
- **Önce:** Gerçek bir halısaha videosuyla maliyet ölçülecek.

## 14. Haberleri ve maç sonucu kartını Instagram'a paylaşmak (Instagram B2)
_Eklendi: 2026-10-14_

- **Şu an:**
  - Turnuvanın Instagram gönderileri Haberler'e otomatik düşüyor (Instagram A).
  - Afişler Instagram'a tek tuşla paylaşılıyor (B1).
- **Sonra:**
  - Haber Yönetimi'ndeki her haberde bir "Instagram'da paylaş" düğmesi olacak. Haberin fotoğrafları (en fazla 5) çoklu gönderi olarak gidecek. Fotoğraflar 4:5 çerçeveye sığdırılacak, kırpılmayacak.
  - Otomatik maç sonucu kartı görsele çevrilip gönderi olarak paylaşılacak.
  - Paylaşılan haberde "Instagram'da paylaşıldı ✓" işareti görünecek. Aynı haber iki kez gönderilmeyecek.
  - Fotoğrafsız haber için metinden otomatik görsel üretmek de düşünülebilir.
- **Neden ertelendi:** Turnuva sahipleri genelde doğrudan Instagram'da paylaşıyor. Bu gönderilerin Haberler'e düşmesi şimdilik yetiyor.

## 15. Hakemler (maç görevlileri)
_Eklendi: 2026-10-14_

- **İstek:** Maçın 1. hakemi ve yardımcı hakemleri girilsin, maç detayında görünsün.
- **Önerilen yapı:**
  - Turnuvaya bağlı bir hakem listesi: ad soyad, isteğe bağlı telefon (yalnız yöneticiler görür) ve fotoğraf. Kurucu başkan kendi listesini yönetir.
  - Maça üç alan: 1. hakem, 1. yardımcı, 2. yardımcı. 4. hakem isteğe bağlı.
  - Yönetim menüsüne "Hakem Yönetimi" (ortak form tasarımıyla).
  - Maç düzenleme formunda "Hakemler" bölümü: listeden seçim, listede yoksa "+ Yeni hakem".
- **Gösterim:** Detay sekmesinin en altında "Maç Görevlileri" kartı. Hakem girilmemişse kart görünmez. Üst bant zaten dolu olduğu için oraya konmadı.
- **Yük:** Orta (migration + yönetim ekranı + maç formu + detay kartı).

## 18. Sponsor reklam haberi (kampanya)
- Sponsorlar kampanya duyurusu verebilsin; Haberler'de "REKLAM" etiketli haber olarak çıkar.
- Örnek: "BMR Otomotiv'den %10 indirim. 1–31 Ekim tarihleri arasında INDIRIM10 koduyla gelen müşterilerimize %10 indirim uygulanacaktır."
- Olası alanlar: sponsor (sponsorlar listesinden), başlık, metin, kampanya kodu (kopyala düğmesi), geçerlilik tarihleri (bitince otomatik kalkar), görsel.
- Haber akışında normal haberlerden ayrışan görünüm (etiket + sponsor logosu); ana sayfa sponsor şeridine dokununca o sponsorun aktif kampanyası açılabilir.
- Yetki: admin + kurucu başkan. Mağaza beyanlarında (reklam içeriği) güncelleme gerekebilir.

## 19. Takımsız futbolcu profili (serbest oyuncu) + videolarım — DEĞERLENDİRMEDE
_Eklendi: 2026-10-15_

Hiçbir takımda kaydı olmayan kişi kendi futbolcu profilini oluşturabilsin, sonra YouTube/Instagram videolarını ekleyebilsin.

- **Temel karar:** Ayrı "aday" tablosu değil, mevcut `players` kaydı. Takıma girince aynı profil devam eder (geçmiş, videolar kaybolmaz).
- **Faz 1 – Serbest oyuncu kaydı:** Telefonla hesap → "Futbolcu profilimi oluştur". Alanlar: ad soyad, doğum tarihi (herkese yalnız yaş), boy, kilo, ayak, ana + yan mevkiler, il/ilçe, fotoğraf, kısa tanıtım, "Takım arıyorum" anahtarı.
  - Mükerrer kayıt: telefon eşleşirse "Bu sen misin?" → profili sahiplenme; eşleşme yoksa sahiplenme talebi bölge sorumlusu onayına. İleride TC hash ile kesin tekillik.
- **Faz 2 – Videolarım:** YouTube/Instagram/diğer linkler (maç medyasındaki link altyapısı; video yükleme/MP4 çekme yok). En fazla 10 video, sıralama, başlık, "öne çıkan".
  - Apple şartı (kullanıcı içeriği): "Şikâyet et", admin gizleme, kullanım koşulları.
- **Faz 3 – Keşif ve davet:** Takım yöneticisi/kurucu için "Serbest oyuncular" listesi (mevki, yaş, il filtresi) → "Takıma davet et" → futbolcu kabul → bölge sorumlusu onayı (kadro talebi akışı).
- **Dikkat:** KVKK (boy/kilo için açık rıza + görünürlük: herkese açık / yalnız yöneticiler); Play Veri güvenliği, Apple etiketi, gizlilik sayfası güncellenmeli; 18 yaş altı ilk sürümde dışarıda (öneri); yeni tablo/kolonlar → Apple onayından sonra DB.
- **Tahmini maliyet:** Faz 1 orta, Faz 2 düşük-orta, Faz 3 orta.
- **Netleşecek:** Profil varsayılan görünürlüğü; 18 yaş altı; önce ekran önizlemesi (mockup) istenir mi.

## 20. Instagram → Haberler: #ligmasasi etiketiyle seçmeli aktarım — CANLI (2026-10-18)

Kalan: migration 20261023100000 uygulanacak, `instagram-sync` edge function deploy edilecek, web + APK yayınlanacak.


Bugün aktarım açıksa turnuvanın Instagram hesabındaki her yeni gönderi sorulmadan haber olarak yayınlanıyor. İstek: her gönderi uygulamada görünmesin.

- Açıklamada `#ligmasasi` varsa (büyük/küçük harf ve İ/ı duyarsız) → haber hemen yayınlanır; etiket haber metninden çıkarılır.
- Etiket yoksa → haber `is_published = false` kaydedilir; kurucu başkana bildirim, Bekleyen Onaylar'da yeni "Haber" filtresi: görsel + açıklama + tarih, "Yayınla" / "Haberlere alma".
- Değişecek yer: `supabase/functions/_shared/instagram_sync.ts` (insert), onay ekranı (`admin_pending_actions_screen.dart`), bildirim tetikleyicisi.
- Eski sürümler etkilenmez (yayınlanmamış haber kullanıcılara görünmez).
- Maliyet: düşük-orta.

## 21. Esame kağıdını kamerayla okutma — YAPILACAK

Fotoğraf yükleyerek esame okuma 2026-10-17'de yapıldı (galeriden seçme, Gemini ile okuma, kadroyla eşleştirme, onay ekranı). Sıradaki adım: aynı akışa "Kameraya okut" seçeneği.

- iOS'ta `NSCameraUsageDescription` gerekir → yeni iOS derlemesi + Apple incelemesi (inceleme notuna özelliği yaz).
- Android/web'de image_picker kamera kaynağı ek izin istemeden çalışır.
- Turnuva ayarı: "Esame girişi: Elle / Kağıttan oku (kamera + galeri)".
- Sonraki aşama: maç sonu kağıttaki gol / SK / KK sütunlarını okuma.

## 22. Dil seçeneği (çok dilli uygulama) — BÜYÜMEDE YAPILACAK

Kullanıcı sayısı büyür ve Türkçe bilmeyen kitleden talep gelirse yapılacak (karar 2026-10-19). Maliyet: yüksek.

Ölçek (2026-10-19 ölçümü):
- Uygulamada 184 dosyada ~2.400 sabit Türkçe metin.
- Veritabanında ~600 satır Türkçe metin: bildirim başlıkları, otomatik haber, hata mesajları.
- Afişlere gömülü yazılar ("MAÇ SONUCU", "HAFTA" …).

Aşamalar:
1. Uygulama ekranları:
   - Metinler ARB dosyalarına taşınır (`flutter_localizations` + `intl` zaten kurulu).
   - Ayarlara dil seçimi eklenir.
   - İlk dil İngilizce.
2. Sunucu metinleri:
   - Kullanıcının dil tercihi `notification_prefs` içinde tutulur.
   - `push_send`, otomatik haber ve afiş metinleri dile göre üretilir.
3. Mağaza: App Store / Play açıklamaları, görseller, gizlilik ve koşullar sayfaları her dil için.

Kalıcı maliyet: sonrasında her yeni özellik iki dilde yazılır.

## 23. Yönetim Masası (web paneli, ligmasasi.com/panel) — 1a YAPILDI (2026-10-19)
- Sorumluların masaüstü paneli: `web/panel.html`, sade HTML/JS, uygulamayla aynı hesap ve yetkiler. Veriler tek RPC'den gelir (`desk_matches`).
- **1a:**
  - giriş
  - Bugün (gün seçimi, sonucu girilmemiş maçlar)
  - skor girişi (eleme maçında penaltı)
  - kısayollar: ← → gün, ↑ ↓ maç, Enter skor, B bugün, R yenile
- **1b YAPILDI (2026-10-19):** canlı maç ekranı.
  - Kontroller: devre düğmeleri, uzatma/penaltı, son adımı geri al.
  - Olay girişi: olay türü tuşla seçilir (G gol, P penaltı, O kendi kalesine, X kaçan penaltı, S sarı, R kırmızı, D değişiklik, Y maçın adamı), ardından oyuncuya tıklanır; golde ardından asist seçilir.
  - Olay sonrası: VAR iptali ve sil.
  - Dakika maç saatinden kendiliğinden gelir.
  - RPC'ler: `desk_match`, `desk_add_event`, `desk_delete_event`. Skor atomik güncellenir.
- **Liste + detay düzeni (2026-10-19):** maç satırları yatay; tıklanan maç sağ bölmede açılır, başka maça tıklanınca sağ taraf o maça geçer.
- **Oyuncu değişikliği kuralı (2026-10-19, DB tetikleyici, uygulamada da geçerli):** çıkan oyuncu sahada, giren oyuncu kenarda olmalı.
- **Onaylar YAPILDI (2026-10-19):**
  - Kapsam: kadro talepleri, kart cezaları (maç sayısı düzenlenir), profil değişiklikleri, yayın linki uyuşmazlıkları, Instagram gönderileri.
  - Menüde talep sayısı rozeti görünür.
  - Kısayollar: O onayla, X reddet.
  - Kayıtlar `desk_approvals` RPC'sinden gelir (security invoker).
- **Kalan bölümler YAPILDI (2026-10-19):** tek RPC `desk_season`'dan beslenirler.
  - **Fikstür:** haftalık tablo; tarih, saat, saha ve durum yerinde değişir.
  - **Puan Durumu:** uygulamadaki sıralama kuralıyla.
  - **Takımlar:** kadro ve sorumlu.
  - **Lisanslar:** oyuncu arama.
  - **Cezalar:** liste.
  - **Sponsorlar:** ekle, düzenle, gizle, sil; logo yüklenir.
  - **Haberler:** yeni haber (en çok 5 fotoğraf), yayınla/kaldır, sil.
  - **Ctrl+K arama.**
- **Panelde olmayanlar** (uygulamadan yapılır):
  - oyuncu lisansı ekleme
  - kadro düzenleme
  - esame
  - sponsor logosunun arka plan temizliği

### Web'e taşınacaklar
Uygulamada yapılan ve panele de dokunan değişiklikler buraya yazılır. Kullanıcı "web'e uygula" deyince toplu olarak işlenir, sonra liste temizlenir. Veritabanı kuralları (RPC, tetikleyici, RLS) iki tarafa kendiliğinden yansır, buraya yazılmaz.
- (boş)

## 24. Takım sorumlusu telefonla — YAPILDI (2026-10-19)
- Takım Yönetimi › Takım Sorumlusu: önce telefon yazılır. Telefon bir futbolcuya, hesaba ya da sahip/sorumlu davetine kayıtlıysa ad soyad kendiliğinden gelir ve değiştirilemez; kayıtlı değilse elle yazılır. Kadroda olmayan kişi de (ör. teknik sorumlu) atanabilir.
- Veritabanı: `set_team_manager` RPC, `lookup_person_by_phone`. Telefon herkese açık `teams` tablosunda değil, `team_manager_contacts` tablosunda durur (yalnız takımı yönetebilenler okur). Ad `teams.manager_name`'de.
- Futbolcu olmayan sorumlu bu telefonla kayıt olabilir. Hesap açılınca yetkisi kendiliğinden bağlanır.
- Eski derlemeler futbolcu seçerek `manager_id` yazmaya devam edebilir; ad ve telefon futbolcudan doldurulur.
- **Vazgeçildi:** ikinci yetkili (kaptan).
- **Sonra:** kurucu başkan ve bölge sorumlusu ekleme pencerelerinde de telefonla otomatik ad.
