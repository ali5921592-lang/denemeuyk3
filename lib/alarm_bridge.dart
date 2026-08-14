import 'dart:convert';
import 'dart:typed_data';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Web tarafındaki alarm id'leri küçük sayılar (1, 2, 3...).
/// AlarmManager id'leriyle çakışmasın diye sabit bir taban eklenir.
const int kIdBase = 100000;

const AndroidNotificationChannel kAlarmChannel = AndroidNotificationChannel(
  'sleepify_alarm',
  'Alarmlar',
  description: 'Sleepify alarmlarının tam ekran bildirimleri',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

/// Alarm saati geldiğinde ayrı bir isolate'te çalışır.
/// Uygulama tamamen kapalı olsa bile Android bu fonksiyonu uyandırır.
@pragma('vm:entry-point')
Future<void> alarmCallback(int id) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();

  final raw = prefs.getString('alarm_$id');
  final data = raw == null
      ? <String, dynamic>{}
      : jsonDecode(raw) as Map<String, dynamic>;
  final label = (data['label'] as String?) ?? 'Alarm';
  final time = (data['time'] as String?) ?? 'Sleepify';

  // Uygulama açıldığında hangi alarmın çaldığını bilsin diye işaretle.
  await prefs.setInt('fired_id', id);
  await prefs.setInt('fired_at', DateTime.now().millisecondsSinceEpoch);

  final fln = FlutterLocalNotificationsPlugin();
  await fln.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  await fln
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(kAlarmChannel);

  await fln.show(
    id,
    time,
    label,
    NotificationDetails(
      android: AndroidNotificationDetails(
        kAlarmChannel.id,
        kAlarmChannel.name,
        channelDescription: kAlarmChannel.description,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true, // kilit ekranını açar
        ongoing: true,
        autoCancel: false,
        playSound: true,
        enableVibration: true,
        visibility: NotificationVisibility.public,
        vibrationPattern: Int64List.fromList([0, 500, 300, 500, 300, 500]),
        // FLAG_INSISTENT: kullanıcı dokunana kadar ses tekrar eder
        additionalFlags: Int32List.fromList(<int>[4]),
      ),
    ),
  );
}

class AlarmBridge {
  static final FlutterLocalNotificationsPlugin _fln =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    await AndroidAlarmManager.initialize();
    await _fln.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final android = _fln.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(kAlarmChannel);
    await android?.requestNotificationsPermission();   // Android 13+
    await android?.requestExactAlarmsPermission();     // Android 12+
  }

  /// Web tarafı her değişiklikte tüm alarm listesini gönderir;
  /// burada eskiler iptal edilip yenileri baştan kurulur.
  static Future<int> sync(List<dynamic> alarms) async {
    final prefs = await SharedPreferences.getInstance();

    for (final s in prefs.getStringList('scheduled') ?? <String>[]) {
      final id = int.tryParse(s);
      if (id == null) continue;
      await AndroidAlarmManager.cancel(id);
      await prefs.remove('alarm_$id');
    }

    final scheduled = <String>[];
    for (final raw in alarms) {
      final a = raw as Map<String, dynamic>;
      if (a['on'] != true) continue;

      final when = _nextOccurrence(a);
      if (when == null) continue;

      final id = kIdBase + (a['id'] as num).toInt();
      final hhmm =
          '${_two(a['h'] as num)}:${_two(a['m'] as num)}';

      await prefs.setString(
        'alarm_$id',
        jsonEncode({'label': a['label'] ?? 'Alarm', 'time': hhmm}),
      );
      await AndroidAlarmManager.oneShotAt(
        when,
        id,
        alarmCallback,
        exact: true,
        wakeup: true,
        alarmClock: true,        // Doze modunda bile tetiklenir
        allowWhileIdle: true,
        rescheduleOnReboot: true,
      );
      scheduled.add('$id');
    }

    await prefs.setStringList('scheduled', scheduled);
    return scheduled.length;
  }

  /// Uygulama öne geldiğinde: son 15 dakika içinde çalan bir alarm var mı?
  static Future<int?> takeFired() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final id = prefs.getInt('fired_id');
    final at = prefs.getInt('fired_at') ?? 0;
    if (id == null) return null;

    await prefs.remove('fired_id');
    await prefs.remove('fired_at');
    await _fln.cancel(id);

    final age = DateTime.now().millisecondsSinceEpoch - at;
    if (age > 15 * 60 * 1000) return null; // bayat, görmezden gel
    return id - kIdBase;
  }

  static Future<void> clearNotifications() => _fln.cancelAll();

  static String _two(num n) => n.toInt().toString().padLeft(2, '0');

  /// JS ile aynı kural: days boşsa tek seferlik, doluysa haftanın günleri
  /// (0 = Pazar, JS'teki Date.getDay ile aynı).
  static DateTime? _nextOccurrence(Map<String, dynamic> a) {
    final now = DateTime.now();
    final days = (a['days'] as List?)?.map((e) => (e as num).toInt()).toList() ??
        const <int>[];
    final h = (a['h'] as num).toInt();
    final m = (a['m'] as num).toInt();

    for (var i = 0; i < 8; i++) {
      final d = DateTime(now.year, now.month, now.day + i, h, m);
      if (!d.isAfter(now)) continue;
      final weekday = d.weekday % 7; // Dart: Pzt=1..Paz=7  →  JS: Paz=0
      if (days.isEmpty || days.contains(weekday)) return d;
    }
    return null;
  }
}
