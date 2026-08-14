#!/usr/bin/env bash
# Sleepify — flutter create ile üretilen android/ klasörünü alarm için hazırlar.
# Hem CI'da hem yerelde çalıştırılabilir, tekrar çalıştırmak zarar vermez.
set -e

python3 - <<'PY'
import re, pathlib, sys

root = pathlib.Path('android')
if not root.exists():
    sys.exit("android/ klasörü yok. Önce: flutter create . --platforms=android")

# ---------------------------------------------------------------- manifest
man = root / 'app/src/main/AndroidManifest.xml'
t = man.read_text(encoding='utf-8')

perms = [
    'android.permission.VIBRATE',
    'android.permission.WAKE_LOCK',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.SCHEDULE_EXACT_ALARM',
    'android.permission.USE_EXACT_ALARM',
    'android.permission.USE_FULL_SCREEN_INTENT',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.CAMERA',
    'android.permission.RECORD_AUDIO',
]
block = '\n'.join(f'    <uses-permission android:name="{p}"/>'
                  for p in perms if p not in t)
if block:
    t = t.replace('<application', block + '\n\n    <application', 1)

# Kamera ve mikrofon zorunlu görünmesin: olmayan cihazlar da uygulamayı kurabilsin
feats = [
    '<uses-feature android:name="android.hardware.camera" android:required="false"/>',
    '<uses-feature android:name="android.hardware.camera.autofocus" android:required="false"/>',
    '<uses-feature android:name="android.hardware.microphone" android:required="false"/>',
]
fblock = '\n'.join('    ' + f for f in feats if f not in t)
if fblock:
    t = t.replace('<application', fblock + '\n\n    <application', 1)

# Alarm çalarken kilit ekranını açıp ekranı uyandırsın
if 'android:showWhenLocked' not in t:
    t = re.sub(r'(<activity\b[^>]*?android:name="\.MainActivity")',
               r'\1\n            android:showWhenLocked="true"'
               r'\n            android:turnScreenOn="true"',
               t, count=1)

# Uygulama adı
t = re.sub(r'android:label="[^"]*"', 'android:label="Sleepify"', t, count=1)
man.write_text(t, encoding='utf-8')
print('✓ AndroidManifest.xml güncellendi')

# ---------------------------------------------- desugaring (local notifications şartı)
DESUGAR = 'com.android.tools:desugar_jdk_libs:2.1.4'
kts = root / 'app/build.gradle.kts'
groovy = root / 'app/build.gradle'

if kts.exists():
    g = kts.read_text(encoding='utf-8')
    if 'isCoreLibraryDesugaringEnabled' not in g:
        g = g.replace('compileOptions {',
                      'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
    if DESUGAR not in g:
        g += f'\n\ndependencies {{\n    coreLibraryDesugaring("{DESUGAR}")\n}}\n'
    kts.write_text(g, encoding='utf-8')
    print('✓ build.gradle.kts: desugaring açıldı')
elif groovy.exists():
    g = groovy.read_text(encoding='utf-8')
    if 'coreLibraryDesugaringEnabled' not in g:
        g = g.replace('compileOptions {',
                      'compileOptions {\n        coreLibraryDesugaringEnabled true', 1)
    if DESUGAR not in g:
        g += f"\n\ndependencies {{\n    coreLibraryDesugaring '{DESUGAR}'\n}}\n"
    groovy.write_text(g, encoding='utf-8')
    print('✓ build.gradle: desugaring açıldı')
else:
    sys.exit('app/build.gradle bulunamadı')
PY

echo "Android tarafı hazır."
