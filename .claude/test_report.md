# Test raporu — 2026-10-01 değişiklikleri (Android, Pixel 7 emülatörü)

- Test başlangıcı: `2026-09-30T23:26:03Z` · bitiş ≈ `23:50Z`
- Ortam: `emulator-5554` (Pixel_7), `flutter run` debug, branch `veteran01102026` (commit edilmemiş değişikliklerle)
- Kod / şema / RLS **değiştirilmedi**. Düzeltme önerileri aşağıda, onay bekliyor.

## Özet

16 kontrol: **11 ✅ geçti · 1 ❌ kaldı · 2 ⚠️ uyarı · 2 ⏭ yapılamadı**

- **RLS açığı bulunmadı.** Hiçbir admin yazma işleminde `42501` / "row-level security" hatası yok (ekranda da log'da da). Statik kontrol: RLS'i açık tüm `public` tablolarının yazma politikaları ya `is_admin()` ya da `owns_league/owns_season/owns_match` kullanıyor, bu üçü de `public.is_admin() or …` ile başlıyor. RLS'i kapalı tablo yok.
- Tek ❌: yan menüdeki **"Çıkış Yap" butonu hiçbir şey yapmıyor** (boş `onPressed`).
- Önemli yan bulgu: oturum boyunca **22 adet yakalanmamış Realtime hatası** (`RealtimeCloseEvent(code: 1002)`) oldu. Admin listeleri yeni kaydı ekrandan çıkıp girmeden göstermedi (ayrıntı aşağıda).

## Sonuç tablosu

| # | Test | Sonuç | Not |
|---|------|:-----:|-----|
| 1 | T1 Misafir ana sayfa, tarih şeridi | ✅ | Çökme yok. **4/10:** "Master Bosphorus Legends" iki başlık altında: *Anadolu Yakası* (19:30, 21:00) ve *Avrupa Yakası* (18:30, 19:40, 20:50). Turnuva adı tam görünüyor ("..." yok), grup adı sağda küçük yeşil yazı. **3/10:** Anadolu Yakası 19:30 ve 21:00 ✔. Ekran görüntüsü: `.claude/test_shots/t1_home_4_10.png` |
| 2 | T1 Maç detayı, Fikstür, Puan Durumu | ✅ | Maç detayı açılıyor (Kardeşler Matbaa – İstanbul Sivas, 04/10 18:30, Seyrantepe). Fikstür açılıyor. Puan Durumu'nda Master Bosphorus Legends için iki ayrı grup tablosu var (Anadolu Yakası 8 takım, Avrupa Yakası). |
| 3 | T2 Admin girişi (başlığa 3 dokunuş) | ✅ | "Sistem Girişi" penceresi açıldı, şifreyle giriş yapıldı, Admin Panel geldi. DB: kullanıcı `admins` tablosunda (1 satır), `last_sign_in_at` 23:29:33Z. |
| 4 | T2 Profilde rol "Sistem Yöneticisi" | ⚠️ | Admin için Profil sekmesi doğrudan Admin Panel'i gösteriyor (`profile_screen.dart:168`). "Rol: Sistem Yöneticisi" satırı bu yüzden **hiç görünmüyor**. Rol mantığı doğru (`state.isAdmin`, `profile_screen.dart:238`), sadece admin bu satırı göremiyor. Tasarım kararıysa sorun değil. |
| 5 | T3 Bekleyen Onaylar | ✅ | "Bekleyen talep yok." yazıyor, hata yok (DB'de `pending_actions` = 0). |
| 6 | T4 Saha: "TEST Saha" ekle → sil | ✅ | Eklendi (23:32:55Z), silindi ("Saha silindi.", DB'de 0). ⚠️ İlk KAYDET denemesi hata snackbar'ıyla başarısız oldu, mesaj okunamadı (aşağıda). Ayrıca yeni saha, ekran yeniden açılana kadar listede görünmedi. |
| 7 | T4 Takım: "TEST Takim" ekle → sil | ✅ | "Takım eklendi." / "Takım silindi.", DB'de doğrulandı. Adı ASCII yazıldı çünkü `adb input text` "ı" harfini yazamıyor. ⚠️ `created_at` +3 saat kaymış kaydediliyor (aşağıda). |
| 8 | T4 Oyuncu: "TEST Oyuncu" ekle (doğum tarihi 01-01-1990) | ✅ | DB: `name='TEST'`, `birth_date=1990-01-01`, 23:38:45Z. Listede "TEST Oyuncu" olarak görünüyor. |
| 9 | T4 Oyuncu: sil | ⏭ | Arayüzde tek oyuncu silme **yok**: listede sadece "Düzenle" var, düzenleme penceresinde silme butonu yok. Yalnızca veri araçlarında "tümünü sil" var, ona dokunulmadı. RLS kontrolü: admin JWT'siyle `delete from players …` geri alınan (rollback) bir transaction'da **1 satır sildi**, yani kural engel değil. Kayıt temizlikte psql ile silindi. |
| 10 | T4 Grup: "TEST Grup" ekle | ✅ | Turnuva Yönetimi → Hürriyet Gençlik Ligi → 2026-2027 Sezonu → Grup Ekle: "Grup eklendi.", DB 23:42:16Z. |
| 11 | T4 Grup: sil | ⏭ | Admin yolundaki sezon ekranında (`season_management_screen.dart`) grup silme yok. Silme sadece `AdminGroupManagementScreen`'de var, o ekran da yalnızca online kayıt → turnuva sahibi paneli üzerinden açılıyor. Rollback'li RLS simülasyonunda admin **1 satır sildi**. Kayıt temizlikte psql ile silindi. |
| 12 | T4 Maç: düzenle → değiştirmeden kaydet | ✅ | Fikstür → Yeşil FK – Beyaz FK (29/09) → Maçı Düzenle → GÜNCELLE: "Maç güncellendi." Satırın öncesi ve sonrası (`updated_at` hariç) **birebir aynı**. |
| 13 | T4 Turnuva / sezon: değiştirmeden kaydet | ✅ | Turnuva (Hürriyet Gençlik Ligi): "Turnuva güncellendi." Sezon (2026-2027): pencere hatasız kapandı. `seasons.updated_at` trigger olmadığı için hep boş, bu yüzden DB'den doğrulanamadı. |
| 14 | T4 Haber ekle | ⚠️ (beklenen) | Snackbar: `Hata: PostgrestException(message: Could not find the table 'public.news' in the schema cache, code: PGRST205, details: Not Found, hint: Perhaps you meant the table 'public.teams')`. Haber listesi açılırken hata göstermiyor, sadece boş liste. Görüntü: `.claude/test_shots/t4_news_pgrst205.png` |
| 15 | T5 Çıkış (Admin Panel → Çıkış Yap) | ✅ | Onay penceresi → Çıkış Yap → giriş ekranı. Profil sekmesi artık giriş formu, Admin Panel görünmüyor. |
| 16 | T5 Çıkış (yan menü → Çıkış Yap) | ❌ | Ayrıntı aşağıda. |

## ❌ Ayrıntı

### #16 Yan menüdeki "Çıkış Yap" çalışmıyor
- **Adım:** Admin girişliyken Menü (☰) → alttaki "Çıkış Yap" (2 kez denendi).
- **Ekranda:** Hiçbir şey olmuyor, menü açık kalıyor, oturum kapanmıyor. Hata mesajı yok.
- **Log:** ilgili satır yok (buton hiçbir kod çalıştırmıyor).
- **Tablo / RLS:** ilgisiz. Kural değil, kod eksikliği:
  `lib/features/home/screens/main_navigator.dart:201` → `onPressed: () { // Çıkış yapma işlemleri }`
- **Ek:** buton misafir kullanıcıda da görünüyor, orada da işlevsiz.
- **Ekran görüntüsü:** yok (değişen bir şey olmadığı için UI dökümüyle doğrulandı).
- **Önerilen düzeltme:** Admin Panel'deki `onLogout` ile aynı çıkış akışını (onay penceresi + `AppSession` sign-out) buraya bağlamak ve butonu sadece giriş yapmış kullanıcıya göstermek.

## ⚠️ Diğer bulgular (öneri, onay bekliyor)

1. **Realtime bağlantısı kopuyor, hata yakalanmıyor.** Log'da 17× `Unhandled Exception: RealtimeCloseEvent(code: 1002, reason: )` ve 5× `RealtimeSubscribeException(status: channelError, details: RealtimeCloseEvent(code: 1002 …))` var. Kaynak `SupabaseStreamBuilder._addException` (supabase_stream_builder.dart:354). İlk hata admin girişinden sonra, ilk admin ekranı açılırken (log satırı 2155) çıktı, girişten önce yoktu. Sonuç: Saha Yönetimi'nde eklenen "TEST Saha" ekrandan çıkıp girilene kadar listede görünmedi. Tahmin: girişte JWT değişince açık realtime kanalları yeniden bağlanırken protokol hatası (1002) alıyor. `resilientStream` hatayı dinleyicisiz bırakıyor.
   *Öneri:* stream'lere `onError` / `handleError` ekleyip hatayı yakalamak ve yeniden abone olmak. Girişte/çıkışta kanalları kapatıp yeniden açmak (`removeAllChannels` + yeniden abone olma). Realtime 1002 nedeni Supabase tarafında (realtime publication / RLS ile `postgres_changes`) ayrıca incelenmeli.
2. **İlk "TEST Saha" kaydı başarısız oldu, sebebi okunamadı.** Hata snackbar'ı pencerenin altında kısa süre kaldı, UI dökümüne düşmedi. İkinci denemede kayıt oluştu. DB'de aynı insert admin JWT'siyle sorunsuz çalışıyor, yani RLS değil. Büyük ihtimalle yukarıdaki bağlantı kopmasıyla aynı anda oldu. *Öneri:* hata ayrıntısını log'a yazmak için geliştirmede `AppConfig.dbLogEnabled` açılabilir.
3. **`teams.created_at` +3 saat kaymış.** "TEST Takim" 23:36Z'de oluşturuldu, DB'de `2026-10-01 02:36:35+00` yazıyor. Sebep: `supabase_team_service.dart` (1297, 1643, 1777, 2206, 2687) `DateTime.now().toIso8601String()` gönderiyor. Bu saat dilimi bilgisi içermeyen yerel saat, `timestamptz` bunu UTC sanıyor. *Öneri:* alanı hiç göndermemek (kolonun default'u `CURRENT_TIMESTAMP`) ya da `DateTime.now().toUtc().toIso8601String()` kullanmak. Aynı desen başka servislerde de olabilir.
4. **Build sırasında `setState` uyarısı** (ölümcül değil): `setState() or markNeedsBuild() called during build` — `_HomeScreenState.build` (`home_screen.dart:546`) içinde `GlobalFilter.setLeague` çağrılıyor → `_onGlobalFilterChanged` (`home_screen.dart:170`) setState yapıyor. *Öneri:* `setLeague` çağrısını `WidgetsBinding.instance.addPostFrameCallback` içine almak.
5. **Admin arayüzünde eksik silme işlemleri:** tek oyuncu silme ve admin yolunda grup silme yok (#9, #11). Özellik isteği olarak not edildi.
6. **`news` tablosu yok** (#14): Haber Yönetimi ekranı ya gizlenmeli ya da tabloyla birlikte migration eklenmeli.

## Temizlik

Silmeden önce listelenen test kayıtları (hepsi test başlangıcından sonra oluşturulmuştu):

| Tablo | id | name | created_at |
|---|---|---|---|
| groups | `56dfd5ca-c88c-44a0-ba7a-00f977dbd873` | TEST Grup | 2026-09-30 23:42:16Z |
| players | `abd27e2f-4024-4bdf-b01c-104baf363f2a` | TEST | 2026-09-30 23:38:45Z |

- Bu iki satır psql ile silindi (`created_at > 2026-09-30T23:26:03Z` koşuluyla). Başka veri silinmedi.
- "TEST Saha" ve "TEST Takim" test sırasında arayüzden silinmişti, temizlikte kalan kayıt yoktu.
- Son sayımlar test öncesiyle aynı: `pitches 13 · teams 26 · groups 4 · players 49 · pending_actions 0`.
- Maç no-op kaydı veriyi değiştirmedi. Turnuva ve sezon aynı değerlerle kaydedildi.
- RLS simülasyonları `begin … rollback` içinde yapıldı, kalıcı etkisi yok.
- `flutter run` süreci durduruldu (emülatör açık bırakıldı).
