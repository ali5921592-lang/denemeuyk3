# Google Play'e yayımlama rehberi

Bu dosya Sleepify'ı Play Store'a çıkarmanın tam yolunu anlatır.
Önce en önemli iki gerçeği söyleyelim, çünkü planını bunlar belirler.

**App Store'a gitmez.** App Store Apple'ındır ve yalnızca iOS uygulamalarını
kabul eder. Sleepify Android için yazıldı; iOS sürümü için bir Mac, Apple
Developer üyeliği (yıllık 99 USD) ve alarm altyapısının yeniden yazılması
gerekir — çünkü `AndroidAlarmManager`ın iOS karşılığı yoktur.

**Tam otomatik yayın diye bir şey yok.** GitHub, derlemeyi ve Play Console'a
yüklemeyi otomatik yapabilir. Ama ilk yükleme elle, mağaza bilgileri elle ve
Google'ın incelemesi kaçınılmazdır. Kod her `git push` sonrası otomatik
mağazaya düşmez.

---

## Maliyet ve süre

| Kalem | Tutar / süre |
|---|---|
| Play Console kaydı | 25 USD, bir kez |
| Kapalı test zorunluluğu | 12 test kullanıcısı × 14 gün |
| İnceleme | genelde 1–7 gün |
| **Toplam ilk yayın** | **yaklaşık 3–4 hafta** |

Kapalı test kuralı önemli: kişisel geliştirici hesapları için
en az 12 test kullanıcısının kesintisiz 14 gün kayıtlı kalması ve uygulamayı
gerçekten kullanması gerekiyor; bu tamamlanmadan üretim erişimi açılmıyor.
Kural yalnızca 13 Kasım 2023'ten sonra açılan **kişisel** hesaplar için
geçerli; şirket (organization) hesapları muaf.

Pratik tavsiye: 12 değil **15–18 kişi** topla. Biri çekilirse 14 günlük sayaç
sıfırlanabiliyor. Arkadaş, aile ve tanıdıklar yeterli; herkesin ayrı bir Google
hesabıyla katılıp uygulamayı gerçek bir cihaza kurması gerekiyor.

---

## 1. adım · Hesap aç

[play.google.com/console](https://play.google.com/console) → kaydol, 25 USD öde,
kimlik doğrulamasını tamamla. Genelde 1–2 gün sürer.

## 2. adım · İmzalama anahtarı üret

Bu anahtar uygulamanın kimliğidir. **Kaybedersen aynı uygulamayı bir daha
güncelleyemezsin**, yedeğini güvenli bir yerde sakla.

```bash
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Sonra base64'e çevir (GitHub sırrına koymak için):

```bash
base64 -w0 upload-keystore.jks > keystore.txt
```

## 3. adım · GitHub sırlarını gir

Depo → **Settings → Secrets and variables → Actions → New repository secret**

| Sır adı | Değeri |
|---|---|
| `KEYSTORE_BASE64` | `keystore.txt` içeriği |
| `STORE_PASSWORD` | keystore parolası |
| `KEY_PASSWORD` | anahtar parolası |
| `KEY_ALIAS` | `upload` |
| `SERVICE_ACCOUNT_JSON` | 6. adımda alınacak |

## 4. adım · İlk AAB'yi üret

```bash
git tag v1.0.0
git push origin v1.0.0
```

Actions → **Play Store yükle** çalışır. Bitince **Artifacts → sleepify-aab**
bağlantısından `app-release.aab` dosyasını indir.

## 5. adım · Play Console'da uygulamayı kur

Play Console → **Create app**. Sonra sol menüden şunları doldur:

- **Store listing** — ad, kısa açıklama (80 karakter), uzun açıklama,
  512×512 simge, 1024×500 kapak görseli, en az 2 ekran görüntüsü
- **App content** — gizlilik politikası bağlantısı (**zorunlu**),
  veri güvenliği formu, hedef kitle, reklam beyanı
- **Closed testing** → Create release → AAB'yi yükle → test kullanıcılarının
  e-postalarını ekle → opt-in bağlantısını onlara gönder

Veri güvenliği formunda Sleepify için doğru cevaplar:

| Soru | Cevap |
|---|---|
| Veri topluyor mu | Hayır |
| Veri paylaşıyor mu | Hayır |
| Veriler cihazda mı | Evet, tamamı |
| Kamera kullanımı | Evet, barkod okuma için, kaydedilmez |
| Mikrofon kullanımı | Evet, gece sesi seviyesi için, kaydedilmez |

Gizlilik politikası şart. Ücretsiz bir sayfa yeter; bu depoda
`store/privacy-tr.md` ve `store/privacy-en.md` hazır — GitHub Pages ile
yayımlayıp bağlantısını verebilirsin.

## 6. adım · Otomatik yüklemeyi aç

İlk sürüm elle yüklendikten sonra gerisi otomatikleşir.

1. Play Console → **Setup → API access** → Google Cloud projesi bağla
2. Google Cloud → **IAM & Admin → Service Accounts** → hesap oluştur →
   JSON anahtar indir
3. Play Console → **Users and permissions** → servis hesabını davet et →
   *Release to testing tracks* ve *Release to production* yetkisi ver
4. JSON içeriğini GitHub'da `SERVICE_ACCOUNT_JSON` sırrına yapıştır

Artık her etiket gönderdiğinde AAB otomatik olarak Play Console'a düşer:

```bash
git tag v1.0.1
git push origin v1.0.1
```

Kanalı seçmek için: Actions → **Play Store yükle** → Run workflow →
`internal` / `alpha` / `beta` / `production`.

## 7. adım · 14 günü tamamla ve üretime başvur

Test kullanıcıları 14 gün boyunca kayıtlı kalsın ve uygulamayı kullansın.
Play Console panosunda katılım durumunu izle; düşen olursa hemen yerine yenisini
ekle. Süre dolunca **Apply for production access** düğmesi açılır.

Başvuruda uygulamanı, test sürecini ve yayına hazır olduğunu anlatan sorular
sorulur; kısa ve dürüst cevapla.

---

## Sürüm numarası nasıl artar

`pubspec.yaml` içindeki satır:

```yaml
version: 1.0.0+1
```

Nokta öncesi kullanıcıya görünen sürüm, `+` sonrası ise **build numarası**.
Play Store aynı build numarasını iki kez kabul etmez; her yüklemede artır:

```yaml
version: 1.0.1+2
```

## Reddedilme sebepleri ve önlemi

| Sebep | Önlem |
|---|---|
| Gizlilik politikası eksik veya erişilemiyor | Bağlantının açık ve çalışır olduğundan emin ol |
| Veri güvenliği formu gerçekle uyuşmuyor | Kamera/mikrofon kullanımını beyan et |
| İzinler gerekçesiz | Açıklamada neden gerektiğini yaz |
| Ekran görüntüleri uygulamayla uyuşmuyor | Gerçek ekranları kullan, montaj yapma |
| Sağlık iddiası | "Uyku evreleri tahminidir, tıbbi ölçüm değildir" ibaresi zaten uygulamada var, açıklamada da tekrarla |

Son not: uygulama uyku takibi yaptığı için **tıbbi iddiada bulunmamaya** dikkat
et. "Uykunuzu iyileştirir" yerine "uyku alışkanlıklarınızı izlemenize yardımcı
olur" gibi ifadeler kullan.
