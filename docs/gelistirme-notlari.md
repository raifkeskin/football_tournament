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

## 5. Bildirime dokununca ilgili sayfanın açılması (deep link)
_Eklendi: 2026-10-03_

- Şu an bildirime dokununca uygulamanın ana sayfası açılıyor; uygulamada sayfa adresleri (route) tanımlı değil.
- Yapılacak: maç bildirimi → ilgili maç detayı, haber bildirimi → haber, saat/hatırlatma → maç detayı.
- Gerekenler: uygulamaya adres yapısı (ör. `/mac/<id>`, `/haber/<id>`), push-sw.js'te tıklamada adresin açılması, veritabanındaki push tetikleyicilerinde `url` alanının doldurulması.

## 6. Champions Master tanıtım sayfasını kendi alan adımızda yayınlamak
_Eklendi: 2026-10-06_

- Tanıtım sayfası hazır: `docs/tanitim/champions-master-tanitim.html` (görseller içine gömülü, tek dosya). Kaynak şablon: `docs/tanitim/champions-master-tanitim.src.html`. Şu an claude.ai'de de duruyor: https://claude.ai/artifact/MWikmZChsDdT2FmW7a8u3n
- Yapılacak: sayfayı Firebase hosting'e koymak (ör. `/tanitim/champions`), turnuva sahiplerine uygulamanın kendi adresiyle bağlantı göndermek. Hareketli haber galerisi aynen çalışır.
- PDF sürümü şimdilik gerekmiyor; istenirse galeri bölümü 5 küçük kare olarak basılacak.

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
