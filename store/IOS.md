# iOS rehberi

Sleepify artık iPhone'da da çalışıyor. Ama iOS'un alarm konusunda Android'den
çok farklı kuralları var; bunları bilerek karar vermen için önce sınırları
yazıyorum, sonra kurulumu.

---

## Önce dürüst tablo

Apple, üçüncü taraf uygulamaların kilitli cihazda kod çalıştırmasına izin vermez.
`AndroidAlarmManager`ın karşılığı yoktur. Bu yüzden iOS'ta alarm, önceden
zamanlanmış **yerel bildirimlerle** kurulur ve şu sınırlar geçerlidir:

| Konu | Android | iOS |
|---|---|---|
| Uygulama kapalıyken alarm | Tam çalışır | Bildirim olarak çalar |
| Alarm sesi süresi | Sınırsız, kapatılana dek | **En fazla 30 saniye** |
| Sessiz moddayken ses | Çalar | Apple'dan "Critical Alerts" izni gerekir |
| Kilit ekranını açma | Tam ekran açılır | Bildirime dokunmak gerekir |
| Uyandırma görevleri | Doğrudan | Bildirime dokununca uygulama açılır, görev orada |
| Uyku sesleri arka planda | Kısıtlı | Arka plan ses modu açık |

Bu sınırı aşmak için uygulama her alarmda **sekiz bildirimlik bir zincir**
kurar: 30 saniye arayla art arda gelir, yani yaklaşık dört dakika boyunca
seni dürtükler. Alarmı kapattığında zincirin kalanı iptal edilir.

Sessiz moddayken de çalması istiyorsan Apple'a **Critical Alerts** yetkisi için
başvurman gerekir ([başvuru formu](https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/)).
Apple bunu genelde sağlık ve güvenlik uygulamalarına verir; alarm uygulamaları
için onay alması zordur. Yetki olmadan varsayılan olarak **time-sensitive**
seviyesi kullanılır: odak modunu deler ama sessiz modu delmez.

---

## IPA nasıl alınır

Mac'e ihtiyacın yok. GitHub'ın macOS sunucusu derliyor.

Depoya `build-ios.yml` yüklendikten sonra Actions → **iOS derle** çalışır ve
iki çıktı üretir:

- **sleepify-ios-unsigned** — imzasız IPA
- **sleepify-ios-simulator** — Mac'i olanlar için simülatör paketi

İmzasız IPA'yı iPhone'a kurmak için:

| Yöntem | Gereken | Süre sınırı |
|---|---|---|
| **AltStore / SideStore** | Ücretsiz Apple ID | 7 günde bir yenileme |
| **Sideloadly** | Ücretsiz Apple ID + bilgisayar | 7 gün |
| **Apple Developer** | Yıllık 99 USD | 1 yıl |

Ücretsiz hesapla kurulan uygulamalar 7 gün sonra açılmaz; AltStore arka planda
kendi kendine yeniler. Kendin ve birkaç kişi için bu yeterli.

---

## App Store'a yayımlama

Play Store'dan daha zahmetli ve daha pahalı:

| Kalem | Değer |
|---|---|
| Apple Developer üyeliği | **99 USD / yıl** (Play'de 25 USD, tek sefer) |
| Derleme ve yükleme | Mac + Xcode gerekir (veya CI'da imzalama kurulumu) |
| İnceleme | 1–3 gün, ama ret oranı yüksek |
| Test | TestFlight, 12 kişi zorunluluğu yok |

Apple'ın en sık takıldığı noktalar, Sleepify özelinde:

**Arka plan ses modu.** `UIBackgroundModes: audio` açık ve uygulama gerçekten
ses çalmıyorsa Apple reddeder. Bizde uyku sesleri ve alarm var, gerekçe meşru —
ama inceleme notuna bunu açıkça yaz.

**WebView tabanlı uygulama.** Apple kuralı 4.2, "yalnızca bir web sitesini
paketleyen" uygulamaları reddeder. Sleepify buna girmez çünkü çevrimdışı
çalışır, cihaz sensörlerini ve bildirimleri kullanır. Yine de inceleme notunda
"uygulama tamamen çevrimdışıdır, web sitesi paketlemesi değildir" demen iyi olur.

**Sağlık iddiası.** Uyku evrelerinin model tahmini olduğu, tıbbi ölçüm olmadığı
hem uygulamada hem mağaza açıklamasında yazmalı. "Uykunuzu iyileştirir" gibi
ifadeler kullanma.

**İzin açıklamaları.** `patch_ios.py` bunları Info.plist'e ekliyor. Eksik olsa
uygulama açılışta çökerdi.

### Adımlar

1. [developer.apple.com](https://developer.apple.com/programs/) → Apple Developer
   Program üyeliği al (99 USD/yıl)
2. App Store Connect → yeni uygulama kaydı, paket kimliği `com.sleepify.sleepify`
3. Mac'te: `flutter build ipa` → Xcode ile imzala ve yükle
   (Mac'in yoksa CI'da imzalama sertifikası kurulumu gerekir, daha karmaşık)
4. TestFlight ile test et
5. Mağaza bilgileri: açıklama, ekran görüntüleri (6.7" ve 6.5" boyutlarda),
   gizlilik politikası (`store/privacy-tr.md` hazır), gizlilik "besin etiketi"
6. İncelemeye gönder

Gizlilik etiketinde Sleepify için doğru cevap **"Veri Toplanmıyor"** — uygulama
hiçbir şey göndermiyor.

---

## Benim tavsiyem

Önce **Android'de yayınla**. Sebepleri:

- Maliyet 25 USD tek sefer, iOS'ta 99 USD her yıl
- Alarm Android'de tam çalışıyor, iOS'ta sınırlı
- Uygulamanın çekirdek özelliği alarm; iOS'ta yarım kalan bir deneyim
  kötü yorum getirir

iOS tarafını **kendi kullanımın ve yakın çevren için** imzasız IPA olarak tut.
Android'de kullanıcı toplayıp uygulama oturduktan sonra, gerçekten talep varsa
App Store'a geç.

Bir de şunu düşün: Sleepify tamamen çevrimdışı bir web uygulaması olduğu için
iPhone'da **Safari → Paylaş → Ana Ekrana Ekle** ile de kurulabiliyor. Alarm
çalışmaz ama uyku sesleri, nefes rehberi, atmosfer ve analiz çalışır. Hiç para
harcamadan denetmek için en hızlı yol bu.
