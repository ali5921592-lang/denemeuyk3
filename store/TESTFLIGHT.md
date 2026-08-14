# TestFlight otomatik yükleme

Etiket gönderdiğinde GitHub imzalı IPA üretip App Store Connect'e yükler.
Mac gerekmez, sertifika dışa aktarman gerekmez, iki adımlı doğrulama sormaz.

```bash
git tag v1.0.0
git push origin v1.0.0
```

15–25 dakika sonra derleme TestFlight'ta görünür.

---

## Bir kerelik kurulum

### 1. App Store Connect'te uygulamayı kaydet

[appstoreconnect.apple.com](https://appstoreconnect.apple.com) → **Apps → +**

- **Platform:** iOS
- **Bundle ID:** listede yoksa önce
  [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)
  sayfasından oluştur. Öneri: `com.sleepify.app`
- **SKU:** herhangi bir metin, örn. `sleepify001`

Bundle ID'yi bir kere seçince değiştiremezsin, dikkatli seç.

### 2. API anahtarı üret

App Store Connect → **Users and Access → Integrations → App Store Connect API**
→ **+** ile yeni anahtar:

- **Name:** GitHub Actions
- **Access:** **App Manager**

Oluşturunca üç bilgiyi al:

| Bilgi | Nerede |
|---|---|
| **Issuer ID** | sayfanın üstünde, uzun bir UUID |
| **Key ID** | anahtar satırında, 10 karakter |
| **`.p8` dosyası** | **Download API Key** — yalnızca bir kez indirilir |

`.p8` dosyasını kaybedersen yenisini üretmen gerekir, yedekle.

### 3. Takım kimliğini bul

[developer.apple.com/account](https://developer.apple.com/account) →
**Membership details** → **Team ID** (10 karakter, örn. `A1B2C3D4E5`)

### 4. GitHub sırlarını gir

Depo → **Settings → Secrets and variables → Actions → New repository secret**

| Sır adı | Değer |
|---|---|
| `APPSTORE_ISSUER_ID` | Issuer ID (UUID) |
| `APPSTORE_KEY_ID` | Key ID (10 karakter) |
| `APPSTORE_PRIVATE_KEY` | `.p8` dosyasının **tüm içeriği** |
| `APPLE_TEAM_ID` | Team ID (10 karakter) |

`.p8` içeriğini bir metin düzenleyicide açıp olduğu gibi yapıştır —
`-----BEGIN PRIVATE KEY-----` satırından `-----END PRIVATE KEY-----` satırına
kadar hepsi dahil.

Bundle ID varsayılandan farklıysa **Variables** sekmesinden `BUNDLE_ID` ekle.

### 5. Çalıştır

```bash
git tag v1.0.0
git push origin v1.0.0
```

Actions → **TestFlight yükle** akışını izle. İlk çalıştırmada Xcode gerekli
sertifika ve profilleri API anahtarıyla kendisi üretir; senin bir şey yapmana
gerek yok.

---

## Sürüm numarası

Etiketten otomatik alınır:

```
v1.0.0  →  version: 1.0.0+42
                     ↑      ↑
                  etiket   çalıştırma numarası
```

Build numarası her çalıştırmada arttığı için App Store Connect "bu build zaten
var" hatası vermez. Elle çalıştırırsan sürüm sabit kalır, yalnızca build
numarası artar — aynı sürümün düzeltmesini yüklerken bu işe yarar.

## İlk yüklemeden sonra

TestFlight'ta derleme birkaç dakika **"Processing"** durumunda kalır. Sonra:

- **Test Information** → geri bildirim e-postası ve test notları (bir kez)
- **Export Compliance** → şifreleme sorusu. Sleepify şifreleme kullanmıyor,
  **"No"** de. Bunu her build için sormaması adına `Info.plist`'e
  `ITSAppUsesNonExemptEncryption = false` eklemek istersen `tool/patch_ios.py`
  içine bir satır ekleyebilirim.
- **Internal Testing** → kendini ve 100 kişiye kadar ekip üyesini ekle,
  inceleme beklemez
- **External Testing** → 10.000 kişiye kadar, ilk seferde Apple incelemesi var
  (genelde 1 gün)

## App Store'a çıkarken

TestFlight'a yüklenen build doğrudan mağazaya gitmez. App Store Connect →
**Distribution** → sürüm oluştur → build'i seç → ekran görüntüleri, açıklama ve
gizlilik bilgilerini doldur → **Submit for Review**.

Sleepify için gizlilik etiketi cevabı: **"Data Not Collected"**.
Gizlilik politikası `store/privacy-tr.md` ve `store/privacy-en.md` dosyalarında
hazır; GitHub Pages ile yayımlayıp bağlantısını verebilirsin.

İnceleme notuna şunları yazmanı öneririm:

> Uygulama tamamen çevrimdışı çalışır, sunucu bağlantısı yoktur.
> Arka plan ses modu, uyku sesleri ve alarm sesinin çalması için kullanılır.
> Kamera yalnızca barkod okuma göreviyle alarm kapatmada, mikrofon yalnızca
> ortam ses seviyesini ölçmede kullanılır; ikisi de kayıt yapmaz.
> Uyku evreleri bir uyku döngüsü modelinden tahmin edilir, tıbbi ölçüm değildir.

## Sorun giderme

| Hata | Sebep ve çözüm |
|---|---|
| `No signing certificate "iOS Distribution" found` | API anahtarının rolü **App Manager** olmalı, Developer yetmez |
| `No profiles for 'com.sleepify.app' were found` | Bundle ID'yi önce Identifiers sayfasında oluştur |
| `Invalid Issuer ID` veya `Authentication failed` | Sırları kontrol et; `.p8` içeriği eksiksiz yapıştırılmış mı |
| `The bundle version must be higher` | Aynı build numarası ikinci kez yüklenmiş; yeni etiket gönder |
| `Missing Info.plist value NSCameraUsageDescription` | `patch_ios.py` çalışmamış, iş akışı adımlarını kontrol et |
| Xcode sürüm hatası | `testflight.yml` içindeki `Xcode_15.4.app` satırını sunucudaki sürümle güncelle |
