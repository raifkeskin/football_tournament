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
