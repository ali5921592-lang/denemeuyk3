import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// ============================================================================
/// iOS ALARM KATMANI
///
/// iOS'ta `AndroidAlarmManager` karşılığı yoktur: üçüncü taraf uygulamalar
/// kilitli cihazda kod çalıştıramaz. Bu yüzden alarm, önceden zamanlanmış
/// **yerel bildirimlerle** kurulur.
///
/// Sınırlar (dürüst olmak gerekirse):
///   • Bildirim sesi en fazla 30 saniye çalar, uygulama açılmadan uzamaz.
///   • Sessize alınmış cihazda ses çıkması için Apple'dan "Critical Alerts"
///     yetkisi almak gerekir; yetki yoksa sessiz modda titreşim/banner kalır.
///   • Bu yüzden her alarm için arka arkaya birkaç bildirim zamanlanır;
///     kullanıcı uyanana kadar zincir devam eder.
///   • Bildirime dokunulunca uygulama açılır ve uyandırma görevi orada işler.
/// ============================================================================

const int kIosBase = 200000;      // Android tarafıyla çakışmasın
const int kChainCount = 8;        // her alarm için zincir uzunluğu
const int kChainGapSec = 30;      // zincirdeki bildirimler arası saniye

class IosAlarm {
  static final FlutterLocalNotificationsPlugin _fln =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(await _localZone()));

    await _fln.initialize(
      const InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,   // izinleri biz istiyoruz
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _onTap,
    );
    _ready = true;
  }

  /// Cihazın saat dilimini bulur; bulunamazsa UTC'ye düşer.
  static Future<String> _localZone() async {
    try {
      final now = DateTime.now();
      final off = now.timeZoneOffset;
      // Yaygın dilimler için kaba eşleme; tam çözüm flutter_timezone paketidir.
      if (off.inHours == 3) return 'Europe/Istanbul';
      if (off.inHours == 1) return 'Europe/Berlin';
      if (off.inHours == 0) return 'Europe/London';
      if (off.inHours == -5) return 'America/New_York';
      if (off.inHours == 9) return 'Asia/Tokyo';
    } catch (_) {}
    return 'UTC';
  }

  /// Bildirim izinlerini ister. `critical` yalnızca Apple onayı varsa çalışır.
  static Future<bool> requestPermissions({bool critical = false}) async {
    final ios = _fln.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final ok = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
      critical: critical,
    );
    return ok ?? false;
  }

  static NotificationDetails _details({required bool critical}) {
    return NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'alarm.caf',                       // paketteki özel ses
        interruptionLevel: critical
            ? InterruptionLevel.critical          // sessiz modu deler
            : InterruptionLevel.timeSensitive,    // odak modunu deler
      ),
    );
  }

  /// Web arayüzünden gelen alarm listesini zamanlar.
  /// Her alarm için bir zincir kurulur; iOS'un 64 bekleyen bildirim
  /// sınırı olduğundan en yakın alarmlara öncelik verilir.
  static Future<int> sync(List<dynamic> alarms) async {
    await init();
    await _fln.cancelAll();

    final prefs = await SharedPreferences.getInstance();
    final critical = prefs.getBool('criticalGranted') ?? false;

    // Açık alarmların bir sonraki tekrarını çıkar ve zamana göre sırala
    final upcoming = <MapEntry<DateTime, Map<String, dynamic>>>[];
    for (final raw in alarms) {
      final a = raw as Map<String, dynamic>;
      if (a['on'] != true) continue;
      final when = _next(a);
      if (when != null) upcoming.add(MapEntry(when, a));
    }
    upcoming.sort((x, y) => x.key.compareTo(y.key));

    var slot = 0;
    for (final e in upcoming) {
      if (slot >= 56) break;                       // 64 sınırına pay bırak
      final a = e.value;
      final id = kIosBase + (a['id'] as num).toInt() * 10;
      final label = (a['label'] as String?)?.trim();
      final title = '${_two(a['h'])}:${_two(a['m'])}';
      final body = (label == null || label.isEmpty) ? 'Alarm' : label;

      for (var k = 0; k < kChainCount && slot < 56; k++, slot++) {
        final at = tz.TZDateTime.from(
          e.key.add(Duration(seconds: k * kChainGapSec)),
          tz.local,
        );
        try {
          await _fln.zonedSchedule(
            id + k,
            title,
            body,
            at,
            _details(critical: critical),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: jsonEncode({'id': a['id']}),
          );
        } catch (_) {
          // izin yoksa veya sınır dolduysa sessizce atla
        }
      }
      await prefs.setString('iosAlarm_$id', jsonEncode({'id': a['id']}));
    }
    return upcoming.length;
  }

  /// Bildirime dokunulduğunda hangi alarmın çaldığını işaretler.
  static void _onTap(NotificationResponse r) async {
    try {
      final p = r.payload;
      if (p == null) return;
      final data = jsonDecode(p) as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('fired_id', (data['id'] as num).toInt());
      await prefs.setInt('fired_at', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Uygulama öne geldiğinde: yakın zamanda çalan alarm var mı?
  static Future<int?> takeFired() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final id = prefs.getInt('fired_id');
    final at = prefs.getInt('fired_at') ?? 0;
    if (id == null) return null;
    await prefs.remove('fired_id');
    await prefs.remove('fired_at');
    if (DateTime.now().millisecondsSinceEpoch - at > 15 * 60 * 1000) return null;
    return id;
  }

  /// Alarm kapatıldığında zincirin kalanını iptal eder.
  static Future<void> stopChain(int alarmId) async {
    final base = kIosBase + alarmId * 10;
    for (var k = 0; k < kChainCount; k++) {
      await _fln.cancel(base + k);
    }
  }

  static Future<void> clearNotifications() => _fln.cancelAll();

  static String _two(dynamic n) =>
      (n as num).toInt().toString().padLeft(2, '0');

  /// JS ile aynı kural: days boşsa tek seferlik, doluysa haftanın günleri.
  static DateTime? _next(Map<String, dynamic> a) {
    final now = DateTime.now();
    final days = (a['days'] as List?)?.map((e) => (e as num).toInt()).toList() ??
        const <int>[];
    final h = (a['h'] as num).toInt();
    final m = (a['m'] as num).toInt();
    for (var i = 0; i < 8; i++) {
      final d = DateTime(now.year, now.month, now.day + i, h, m);
      if (!d.isAfter(now)) continue;
      final weekday = d.weekday % 7;   // Dart Pzt=1..Paz=7 → JS Paz=0
      if (days.isEmpty || days.contains(weekday)) return d;
    }
    return null;
  }
}
