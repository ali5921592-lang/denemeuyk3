#!/usr/bin/env python3
"""
Sleepify · iOS yaması

`flutter create --platforms=ios` ile üretilen ios/ klasörünü hazırlar:
  • Info.plist'e kamera, mikrofon ve hareket açıklamalarını ekler
     (bunlar olmadan uygulama çökerek kapanır — Apple zorunlu tutar)
  • Arka plan ses modunu açar
  • Görünen uygulama adını ayarlar
  • Alarm sesini (alarm.caf) Xcode projesine kaynak olarak tanıtır
"""
import os
import pathlib
import plistlib
import re
import sys

ios = pathlib.Path('ios')
if not ios.exists():
    sys.exit('ios/ klasörü yok. Önce: flutter create . --platforms=ios')

plist_path = ios / 'Runner/Info.plist'
if not plist_path.exists():
    sys.exit('Info.plist bulunamadı')

with plist_path.open('rb') as f:
    p = plistlib.load(f)

# ---------------------------------------------------------------- açıklamalar
# Apple, izin isteyen her API için gerekçe metni ister; yoksa uygulama çöker.
usage = {
    'NSCameraUsageDescription':
        'Barkod okuyarak alarmı kapatma görevinde kamera kullanılır. '
        'Görüntü kaydedilmez ve hiçbir yere gönderilmez.',
    'NSMicrophoneUsageDescription':
        'Gece sesi algılama özelliğinde yalnızca ses seviyesi ölçülür. '
        'Ses kaydedilmez ve hiçbir yere gönderilmez.',
    'NSMotionUsageDescription':
        'Sallayarak alarmı kapatma ve akıllı uyanma penceresi için '
        'hareket sensörü kullanılır.',
    'NSPhotoLibraryUsageDescription':
        'Arka plan olarak kendi videonuzu seçebilmeniz için kullanılır.',
    'NSUserNotificationsUsageDescription':
        'Alarmın çalabilmesi için bildirim izni gerekir.',
}
for k, v in usage.items():
    p[k] = v

# ---------------------------------------------------------------- arka plan
# Alarm sesinin çalabilmesi ve uyku seslerinin sürmesi için ses modu.
modes = set(p.get('UIBackgroundModes', []))
modes.update({'audio', 'fetch', 'processing'})
p['UIBackgroundModes'] = sorted(modes)

# ---------------------------------------------------------------- görünüm
p['CFBundleDisplayName'] = 'Sleepify'
p['CFBundleName'] = 'Sleepify'
p['UIStatusBarStyle'] = 'UIStatusBarStyleLightContent'
p['UIViewControllerBasedStatusBarAppearance'] = False
# Yalnızca dikey
p['UISupportedInterfaceOrientations'] = ['UIInterfaceOrientationPortrait']
p['UISupportedInterfaceOrientations~ipad'] = ['UIInterfaceOrientationPortrait']
# WebView içi medya kullanıcı dokunuşu beklemesin
p['NSAppTransportSecurity'] = {'NSAllowsArbitraryLoads': True}
# Uygulama şifreleme kullanmıyor: TestFlight her yüklemede sormasın
p['ITSAppUsesNonExemptEncryption'] = False

with plist_path.open('wb') as f:
    plistlib.dump(p, f)
print('✓ Info.plist güncellendi (izin açıklamaları + arka plan ses)')

# ---------------------------------------------------------------- alarm sesi
# Bildirim sesi olarak kullanılacak kısa bir CAF dosyası üretilir.
sounds = ios / 'Runner'
caf = sounds / 'alarm.caf'
if not caf.exists():
    try:
        import math
        import struct
        import wave
        wav = sounds / 'alarm.wav'
        rate, dur = 44100, 25.0        # iOS sınırı 30 sn
        with wave.open(str(wav), 'w') as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            frames = bytearray()
            for i in range(int(rate * dur)):
                t = i / rate
                # 0.6 sn'de bir çift bip: 880 Hz ve 1175 Hz
                cyc = t % 1.2
                amp = 0.0
                if cyc < 0.22:
                    amp = math.sin(2 * math.pi * 880 * t)
                elif 0.30 < cyc < 0.52:
                    amp = math.sin(2 * math.pi * 1175 * t)
                env = 1.0
                if amp:
                    local = cyc if cyc < 0.22 else cyc - 0.30
                    env = min(1.0, local / 0.01) * max(0.0, 1 - local / 0.22)
                frames += struct.pack('<h', int(amp * env * 22000))
            w.writeframes(bytes(frames))
        # Xcode CAF ister; afconvert yalnızca macOS'ta bulunur
        if os.system(f'afconvert -f caff -d LEI16 "{wav}" "{caf}" 2>/dev/null') == 0:
            wav.unlink(missing_ok=True)
            print('✓ alarm.caf üretildi')
        else:
            print('! afconvert yok, alarm.wav bırakıldı (macOS dışında normal)')
    except Exception as e:
        print('! alarm sesi üretilemedi:', e)

# ---------------------------------------------------- sesi projeye ekle
pbx = ios / 'Runner.xcodeproj/project.pbxproj'
snd = 'alarm.caf' if caf.exists() else 'alarm.wav'
if pbx.exists():
    txt = pbx.read_text(encoding='utf-8')
    if snd in txt:
        print('✓ ses dosyası projede zaten kayıtlı')
    else:
        fid = 'AA0000000000000000000001'
        bid = 'AA0000000000000000000002'
        txt = txt.replace(
            '/* End PBXFileReference section */',
            f'\t\t{fid} /* {snd} */ = {{isa = PBXFileReference; '
            f'lastKnownFileType = file; path = {snd}; sourceTree = "<group>"; }};\n'
            '/* End PBXFileReference section */', 1)
        txt = txt.replace(
            '/* End PBXBuildFile section */',
            f'\t\t{bid} /* {snd} in Resources */ = {{isa = PBXBuildFile; '
            f'fileRef = {fid} /* {snd} */; }};\n'
            '/* End PBXBuildFile section */', 1)
        # Resources fazına ve Runner grubuna ekle
        txt = re.sub(r'(isa = PBXResourcesBuildPhase;[\s\S]*?files = \(\n)',
                     r'\1\t\t\t\t' + bid + f' /* {snd} in Resources */,\n',
                     txt, count=1)
        txt = re.sub(r'(/\* Runner \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)',
                     r'\1\t\t\t\t' + fid + f' /* {snd} */,\n',
                     txt, count=1)
        pbx.write_text(txt, encoding='utf-8')
        print(f'✓ {snd} Xcode projesine eklendi')

# ---------------------------------------------------- minimum iOS sürümü
podfile = ios / 'Podfile'
if podfile.exists():
    t = podfile.read_text(encoding='utf-8')
    t = re.sub(r"#\s*platform :ios, '[\d.]+'", "platform :ios, '13.0'", t)
    if "platform :ios" not in t:
        t = "platform :ios, '13.0'\n" + t
    podfile.write_text(t, encoding='utf-8')
    print('✓ Podfile: minimum iOS 13')

print('iOS tarafı hazır.')
