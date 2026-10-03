// KVKK ve sağlık onay metinleri (TASLAK — yayından önce hukukçu kontrolü
// gerekir). Metin değişirse [kConsentVersion] artırılır ve veritabanındaki
// current_consent_version() de aynı değere çekilir; oyunculardan onay yeniden
// istenir.

const kConsentVersion = '2026-10-v1';

/// Onay türleri; veritabanındaki consent_type değerleriyle aynı.
enum ConsentType {
  privacyNotice('privacy_notice'),
  healthData('health_data'),
  healthDeclaration('health_declaration'),
  photoPublish('photo_publish');

  const ConsentType(this.db);
  final String db;
}

class ConsentText {
  const ConsentText({
    required this.type,
    required this.title,
    required this.checkbox,
    required this.body,
    this.required = true,
  });

  final ConsentType type;
  final String title;
  final String checkbox;
  final String body;
  final bool required;
}

const kConsentTexts = <ConsentText>[
  ConsentText(
    type: ConsentType.privacyNotice,
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
  ConsentText(
    type: ConsentType.healthData,
    title: 'Sağlık Verisi Açık Rızası',
    checkbox:
        'Sağlık beyanımın turnuva güvenliği amacıyla işlenmesine açık rıza veriyorum.',
    body: '''
Turnuvada oynamanıza engel bir sağlık durumu bulunmadığına ilişkin beyanınız, KVKK m.6 kapsamında özel nitelikli kişisel veri (sağlık verisi) sayılır.

Bu beyan yalnızca "beyan verildi / verilmedi" ve tarih bilgisi olarak saklanır; hastalık, ilaç veya rapor gibi ayrıntılar istenmez ve tutulmaz. Beyan yalnızca turnuva sahibi ve yetkili görevlilerce görülebilir, herkese açık yayınlanmaz.

Bu rızayı dilediğiniz zaman profilinizden geri alabilirsiniz. Rızanın geri alınması, geri alma tarihine kadar yapılan işlemleri etkilemez; ancak turnuva kurallarına göre maçlarda oynamanız kısıtlanabilir.''',
  ),
  ConsentText(
    type: ConsentType.healthDeclaration,
    title: 'Sağlık Beyanı ve Risk Kabulü',
    checkbox:
        'Futbol oynamama engel bir sağlık sorunum olmadığını beyan ediyor, riskleri kabul ediyorum.',
    body: '''
Futbol oynamama engel olabilecek bir sağlık sorunum (kalp, tansiyon, solunum rahatsızlığı, yakın tarihli ameliyat veya sakatlık vb.) bulunmadığını, gerekli gördüğüm durumlarda doktor kontrolünden geçtiğimi beyan ederim.

Futbolun doğası gereği sakatlanma ve yaralanma riskleri taşıdığını biliyor ve bu riskleri kabul ediyorum. Sağlık durumumda oynamama engel olabilecek bir değişiklik olursa turnuva sahibini bilgilendireceğimi ve maçlara katılmayacağımı taahhüt ederim.

Bu beyan; turnuva sahibinin, organizatörlerin veya uygulama sahibinin kast veya ağır kusurundan doğan sorumluluğunu kaldırmaz.''',
  ),
  ConsentText(
    type: ConsentType.photoPublish,
    title: 'Fotoğraf ve İsim Yayın İzni',
    checkbox:
        'Fotoğrafımın ve adımın kadro afişlerinde, haberlerde ve profilimde yayınlanmasına izin veriyorum.',
    required: false,
    body: '''
Fotoğrafınız ve adınız; kadro afişlerinde, maç ve turnuva haberlerinde, oyuncu profilinizde ve turnuvanın sosyal medya paylaşımlarında kullanılabilir.

Bu izin isteğe bağlıdır. İzin vermemeniz turnuvaya katılımınızı etkilemez. İzninizi dilediğiniz zaman profilinizden geri alabilirsiniz; geri alma öncesinde yapılmış paylaşımlar için turnuva sahibinden kaldırılmasını talep edebilirsiniz.''',
  ),
];
