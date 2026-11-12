// Onay metinleri artık veritabanında (consent_versions + consent_items) durur
// ve mağaza güncellemesi gerekmeden değişir; uygulama yürürlükteki sürümü
// sunucudan okur. Buradaki metinler yalnızca sunucuya ulaşılamazsa gösterilen
// ilk sürümdür (2026-10-v1).

const kFallbackConsentVersion = '2026-10-v1';

/// Onay ekranındaki bir kutu (veritabanında consent_items satırı).
class ConsentItem {
  const ConsentItem({
    required this.key,
    required this.title,
    required this.checkbox,
    required this.body,
    this.required = true,
  });

  factory ConsentItem.fromRow(Map<String, dynamic> r) => ConsentItem(
    key: (r['key'] ?? '').toString(),
    title: (r['title'] ?? '').toString(),
    checkbox: (r['checkbox'] ?? '').toString(),
    body: (r['body'] ?? '').toString(),
    required: r['required'] == true,
  );

  /// Veritabanındaki consent_type değeri.
  final String key;
  final String title;
  final String checkbox;
  final String body;
  final bool required;
}

/// Bir metin sürümü ve kutuları.
class ConsentDoc {
  const ConsentDoc({required this.version, required this.items});

  final String version;
  final List<ConsentItem> items;

  ConsentItem? item(String key) {
    for (final i in items) {
      if (i.key == key) return i;
    }
    return null;
  }
}

const kFallbackConsentDoc = ConsentDoc(
  version: kFallbackConsentVersion,
  items: <ConsentItem>[
    ConsentItem(
      key: 'privacy_notice',
      title: 'Aydınlatma Metni',
      checkbox: 'Aydınlatma metnini okudum, bilgilendirildim.',
      body: '''
6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") kapsamında, turnuvaya katılımınız için kişisel verileriniz aşağıda açıklandığı şekilde işlenir.

İşlenen veriler: Ad, soyad, doğum tarihi, cep telefonu, fotoğraf, mevki ve fiziksel bilgiler (boy, kilo — isteğe bağlı), takım ve maç bilgileri (gol, kart, maç kadrosu), sağlık beyanı (yalnızca "oynamaya engel durumum yok" beyanı ve tarihi; sağlık durumunuzun ayrıntısı tutulmaz).

Amaçlar: Turnuvanın düzenlenmesi, kadro ve lisans işlemleri, fikstür, maç sonuçları ve istatistiklerin tutulup yayınlanması, yaş ve kontenjan kurallarının uygulanması, sizinle iletişim kurulması.

Hukuki sebepler: Turnuvaya katılım sözleşmesinin kurulması ve ifası (KVKK m.5/2-c), veri sorumlusunun meşru menfaati (m.5/2-f); sağlık beyanı ve fotoğrafınızın yayınlanması için açık rızanız (m.6 ve m.5/1).

Aktarım: Verileriniz turnuva sahibi, takım sorumlunuz ve maç görevlileriyle paylaşılır. Maç sonuçları, kadrolar ve istatistikler uygulamada herkese açık yayınlanabilir (doğum tarihinizin tamamı, telefonunuz ve sağlık beyanınız yayınlanmaz). Uygulamanın barındırma ve veritabanı hizmetleri yurt dışında bulunan hizmet sağlayıcılar üzerinden yürütülür.

Saklama süresi: Verileriniz turnuva süresince ve sonrasında yasal yükümlülükler ile olası uyuşmazlıklar için gereken süre boyunca saklanır, ardından silinir veya anonim hâle getirilir.

Haklarınız (KVKK m.11): Verilerinizin işlenip işlenmediğini öğrenme, bilgi talep etme, düzeltilmesini veya silinmesini isteme, aktarıldığı kişileri öğrenme, itiraz etme ve zararın giderilmesini talep etme haklarına sahipsiniz. Başvurularınızı turnuva sahibine veya uygulama yöneticisine iletebilirsiniz.''',
    ),
    ConsentItem(
      key: 'health_data',
      title: 'Sağlık Verisi Açık Rızası',
      checkbox:
          'Sağlık beyanımın turnuva güvenliği amacıyla işlenmesine açık rıza veriyorum.',
      body: '''
Turnuvada oynamanıza engel bir sağlık durumu bulunmadığına ilişkin beyanınız, KVKK m.6 kapsamında özel nitelikli kişisel veri (sağlık verisi) sayılır.

Bu beyan yalnızca "beyan verildi / verilmedi" ve tarih bilgisi olarak saklanır; hastalık, ilaç veya rapor gibi ayrıntılar istenmez ve tutulmaz. Beyan yalnızca turnuva sahibi ve yetkili görevlilerce görülebilir, herkese açık yayınlanmaz.

Bu rızayı dilediğiniz zaman profilinizden geri alabilirsiniz. Rızanın geri alınması, geri alma tarihine kadar yapılan işlemleri etkilemez; ancak turnuva kurallarına göre maçlarda oynamanız kısıtlanabilir.''',
    ),
    ConsentItem(
      key: 'health_declaration',
      title: 'Sağlık Beyanı ve Risk Kabulü',
      checkbox:
          'Futbol oynamama engel bir sağlık sorunum olmadığını beyan ediyor, riskleri kabul ediyorum.',
      body: '''
Futbol oynamama engel olabilecek bir sağlık sorunum (kalp, tansiyon, solunum rahatsızlığı, yakın tarihli ameliyat veya sakatlık vb.) bulunmadığını, gerekli gördüğüm durumlarda doktor kontrolünden geçtiğimi beyan ederim.

Futbolun doğası gereği sakatlanma ve yaralanma riskleri taşıdığını biliyor ve bu riskleri kabul ediyorum. Sağlık durumumda oynamama engel olabilecek bir değişiklik olursa turnuva sahibini bilgilendireceğimi ve maçlara katılmayacağımı taahhüt ederim.

Bu beyan; turnuva sahibinin, organizatörlerin veya uygulama sahibinin kast veya ağır kusurundan doğan sorumluluğunu kaldırmaz.''',
    ),
    ConsentItem(
      key: 'photo_publish',
      title: 'Fotoğraf ve İsim Yayın İzni',
      checkbox:
          'Fotoğrafımın ve adımın kadro afişlerinde, haberlerde ve profilimde yayınlanmasına izin veriyorum.',
      required: false,
      body: '''
Fotoğrafınız ve adınız; kadro afişlerinde, maç ve turnuva haberlerinde, oyuncu profilinizde ve turnuvanın sosyal medya paylaşımlarında kullanılabilir.

Bu izin isteğe bağlıdır. İzin vermemeniz turnuvaya katılımınızı etkilemez. İzninizi dilediğiniz zaman profilinizden geri alabilirsiniz; geri alma öncesinde yapılmış paylaşımlar için turnuva sahibinden kaldırılmasını talep edebilirsiniz.''',
    ),
  ],
);
