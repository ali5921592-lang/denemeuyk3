import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'alarm_bridge.dart';
import 'alarm_ios.dart';

/// Hangi platformdayız — alarm katmanı buna göre seçilir.
bool get isIOS => !kIsWeb && Platform.isIOS;
bool get isAndroid => !kIsWeb && Platform.isAndroid;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isAndroid) {
    await AlarmBridge.init();
  } else if (isIOS) {
    await IosAlarm.init();
  }
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,          // iOS
    systemNavigationBarColor: Color(0xFF0C0A24),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const SleepifyApp());
}

class SleepifyApp extends StatelessWidget {
  const SleepifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sleepify',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0C0A24),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7B5BFF),
          brightness: Brightness.dark,
        ),
      ),
      home: const SleepifyShell(),
    );
  }
}

class SleepifyShell extends StatefulWidget {
  const SleepifyShell({super.key});

  @override
  State<SleepifyShell> createState() => _SleepifyShellState();
}

class _SleepifyShellState extends State<SleepifyShell> with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _build();
  }

  void _build() {
    // Platforma özel oluşturma parametreleri
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,            // video tam ekrana zıplamasın
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0C0A24))
      ..addJavaScriptChannel('Sleepify', onMessageReceived: _onWebMessage)
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) async {
          if (!mounted) return;
          setState(() => _ready = true);
          await _deliverFiredAlarm();
        }),
      );

    final platform = _controller.platform;

    // ---- Android: WebView'in kamera/mikrofon isteklerini onayla ----
    if (platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(false);
      platform.setMediaPlaybackRequiresUserGesture(false);
      platform.setOnPlatformPermissionRequest((request) async {
        var ok = true;
        if (request.types.contains(WebViewPermissionResourceType.camera)) {
          ok = ok && await _ensure(Permission.camera);
        }
        if (request.types.contains(WebViewPermissionResourceType.microphone)) {
          ok = ok && await _ensure(Permission.microphone);
        }
        ok ? request.grant() : request.deny();
      });
    }

    // ---- iOS: WKWebView izin isteği ----
    // Info.plist açıklamaları tool/patch_ios.py ile eklenir.
    if (platform is WebKitWebViewController) {
      platform.setOnPlatformPermissionRequest((request) async {
        var ok = true;
        if (request.types.contains(WebViewPermissionResourceType.camera)) {
          ok = ok && await _ensure(Permission.camera);
        }
        if (request.types.contains(WebViewPermissionResourceType.microphone)) {
          ok = ok && await _ensure(Permission.microphone);
        }
        ok ? request.grant() : request.deny();
      });
    }

    _controller.loadFlutterAsset('assets/web/index.html');
  }

  Future<bool> _ensure(Permission p) async {
    var status = await p.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      _tell('İzin daha önce reddedilmiş. Ayarlardan açman gerekiyor.');
      return false;
    }
    status = await p.request();
    return status.isGranted;
  }

  void _tell(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        action: SnackBarAction(label: 'Ayarlar', onPressed: openAppSettings),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _ready) _deliverFiredAlarm();
  }

  void _onWebMessage(JavaScriptMessage message) async {
    try {
      final msg = jsonDecode(message.message) as Map<String, dynamic>;
      switch (msg['type']) {
        case 'sync':
          final list = msg['alarms'] as List<dynamic>;
          final n = isIOS ? await IosAlarm.sync(list) : await AlarmBridge.sync(list);
          debugPrint('Sleepify: $n alarm zamanlandı');
          break;
        case 'wakelock':
          msg['on'] == true
              ? await WakelockPlus.enable()
              : await WakelockPlus.disable();
          break;
        case 'dismissed':
          if (isIOS) {
            final id = msg['id'];
            if (id is num) await IosAlarm.stopChain(id.toInt());
            await IosAlarm.clearNotifications();
          } else {
            await AlarmBridge.clearNotifications();
          }
          break;
        case 'permission':
          if (msg['what'] == 'camera') await _ensure(Permission.camera);
          if (msg['what'] == 'microphone') await _ensure(Permission.microphone);
          if (msg['what'] == 'notification' && isIOS) {
            await IosAlarm.requestPermissions(critical: false);
          }
          break;
      }
    } catch (e) {
      debugPrint('Sleepify köprü hatası: $e');
    }
  }

  Future<void> _deliverFiredAlarm() async {
    final id = isIOS ? await IosAlarm.takeFired() : await AlarmBridge.takeFired();
    if (id == null) return;
    await _controller.runJavaScript('window.SleepifyFire && window.SleepifyFire($id)');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else if (isAndroid) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0C0A24),
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (!_ready)
                const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF7B5BFF),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
