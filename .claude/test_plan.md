# Test planı — 2026-10-01 değişiklikleri (Android, Pixel 7 emülatörü)

Amaç: aşağıdaki değişikliklerden sonra uygulamanın admin ve misafir olarak
çalıştığını doğrulamak ve sonucu `.claude/test_report.md` dosyasına yazmak.
**Kod, şema veya RLS kuralı değiştirme; sadece test et ve raporla.** Düzeltme
önerilerini rapora yaz, kullanıcı onayladıktan sonra yapılır.

## Neler değişti (test edilecek olanlar)

1. **RLS açıldı** (`supabase/migrations/20261001120000_roles_approvals_rls.sql`):
   okuma herkese açık; yazma sadece admin (`admins.user_id`) ve turnuva
   sahibine (`league_owners`). Admin her şeyi yazabilmeli. Şüpheli nokta:
   bir admin ekranı yazarken "row-level security" / 42501 hatası alırsa bu
   bir kural açığıdır → raporla (tablo + işlem + hata).
2. **Roller** `AppSession`'da veritabanından okunuyor (admin artık e-postaya
   göre değil `admins.user_id`'ye göre).
3. **Onay sistemi** Supabase `pending_actions` + `review_pending_action`
   RPC'sine taşındı; ekran: Admin Panel → Bekleyen Onaylar.
4. **Ana sayfa bölüm başlığı**: turnuva adı solda (gerekirse 2 satır, "..."
   ile kesilmemeli), sezonda birden fazla grup varsa grup adı sağda küçük
   yeşil yazı. `MatchModel.fromMap` artık `group_id` okuyor → maçlar gruba
   göre ayrı başlıklar altında listelenmeli.
5. Firebase/Firestore kodu kaldırıldı, paketler güncellendi (file_picker 13,
   share_plus 13, permission_handler 13...).

## Kurulum

- Emülatör: `flutter emulators --launch Pixel_7`; açılışı bekle:
  `~/Library/Android/sdk/platform-tools/adb wait-for-device` sonra
  `adb shell getprop sys.boot_completed` = 1 olana kadar kontrol et
  (Monitor/until döngüsü, foreground sleep yok).
- Uygulama: `flutter run -d emulator-5554 > <scratchpad>/run.log 2>&1`
  **arka planda** çalıştır. Log'u sadece `grep -E "Exception|Error|error|══"`
  ile oku; tamamını okuma.
- `adb` yolu: `~/Library/Android/sdk/platform-tools/adb`.

## Gizli bilgiler

- Admin: `~/.config/football_tournament/admin.env` (`ADMIN_EMAIL`,
  `ADMIN_PASSWORD`). Veritabanı: `~/.config/football_tournament/db.env`.
- **Bu dosyaları asla `source` etme, `cat` etme, çıktıya yazdırma.** Değeri
  şöyle al: `grep -o "postgres[^'\" ]*" db.env | head -1` (DB URL) ve
  `sed -n "s/^ADMIN_PASSWORD=//p" admin.env | tr -d "'\""` (şifre).
  psql/curl çıktılarını `sed -E 's#:[^@ ]*@#:***@#g'` ile maskele.
- Şifreyi `adb shell input text` ile yazarken komut çıktısına basılmasın.

## Limit tasarrufu (önemli)

- Ekranı okumak için önce metin dökümü:
  `adb exec-out uiautomator dump /dev/tty` → sadece `text=`/`content-desc=`
  ve `bounds=` alanlarını grep ile çıkar. Dokunma koordinatlarını buradan al.
- Ekran görüntüsünü sadece görsel kontrol gereken yerde (T1 başlık düzeni)
  ve bir hata anında al; küçült: `adb exec-out screencap -p > x.png` +
  `sips -Z 700 x.png`. Hata görüntülerini `.claude/test_shots/` altına kaydet.
- Veritabanı doğrulamasını psql ile tek sorguda yap.
- Aynı adımı tekrar tekrar deneme; 2 denemede olmuyorsa "yapılamadı" diye
  raporla ve devam et.

## Testler

Başlangıç zamanını not et (`date -u`); temizlikte kullanılacak.

**T1 – Misafir, ana sayfa**
- Uygulama açılıyor, çökme yok.
- Tarih şeridinden 4/10 (Pazar): "Master Bosphorus Legends" iki ayrı başlık
  altında olmalı: sağda "Avrupa Yakası" (18:30, 19:40, 20:50) ve "Anadolu
  Yakası" (19:30, 21:00). Turnuva adı "..." ile kesilmemeli. → 1 küçük
  ekran görüntüsü.
- 3/10 (Cumartesi): Anadolu Yakası 19:30 ve 21:00.
- Bir maça dokun → maç detayı açılıyor. Fikstür ve gruplar/puan tablosu
  ekranları açılıyor.

**T2 – Admin girişi**
- Giriş ekranında başlıktaki "Giriş Yap" yazısına 1 saniye içinde 3 kez
  dokun (3 `input tap` komutunu tek satırda arka arkaya) → şifre penceresi
  → şifreyi yaz → giriş.
- Profil/rol: "Sistem Yöneticisi"; Admin Panel görünüyor.

**T3 – Bekleyen Onaylar**
- Admin Panel → Bekleyen Onaylar açılıyor, "Bekleyen talep yok" yazıyor,
  hata yok.

**T4 – Admin yazma işlemleri (RLS kontrolü)**
Gerçek maç/oyuncu/takım verisini **değiştirme**. Ya değişmeden kaydet
(no-op) ya da adı `TEST ` ile başlayan kayıt oluşturup aynı test içinde sil.
Her adımda: ekranda hata/snackbar var mı + log'da hata var mı + gerekiyorsa
psql ile kaydın oluştuğunu/silindiğini doğrula.
- Saha: "TEST Saha" ekle → sil.
- Takım: "TEST Takım" ekle → sil.
- Oyuncu: "TEST Oyuncu" ekle (doğum tarihi gir) → sil.
- Grup: mevcut bir sezonda "TEST Grup" ekle → sil.
- Maç: mevcut bir maçı düzenleme ekranında açıp değiştirmeden kaydet.
- Turnuva/sezon düzenleme ekranını açıp değiştirmeden kaydet.
- Haber yönetimi: bir haber eklemeyi dene. Beklenti: `news` tablosu
  veritabanında yok → hata beklenir; sadece ne olduğunu raporla.

**T5 – Çıkış**
- Çıkış yap → misafir görünümüne dönüyor, admin paneli kayboluyor.

## Temizlik (zorunlu)

Test sonunda psql ile kontrol et, kalan test kaydı varsa sil (sadece test
başlangıcından sonra oluşturulanlar):
`name like 'TEST %'` → `pitches`, `teams`, `groups`; `players` için
`name = 'TEST' or name like 'TEST %'`. Silmeden önce satırları listele ve
rapora yaz. Başka hiçbir veriyi silme. `flutter run` sürecini durdur.

## Rapor: `.claude/test_report.md`

- Özet: kaç test geçti / kaldı / yapılamadı.
- Tablo: Test | Sonuç (✅/❌/⚠️/⏭) | Not.
- Her ❌ için: adım, ekrandaki mesaj, log satırı (maskeli), ilgili tablo ve
  RLS kuralı tahmini, ekran görüntüsü yolu, önerilen düzeltme.
- Temizlik sonucu (silinen test kayıtları).
- Rapor bitince dur; düzeltme yapma.
