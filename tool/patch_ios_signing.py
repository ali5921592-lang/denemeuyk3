#!/usr/bin/env python3
"""
Sleepify · iOS imzalama yapılandırması

Xcode projesini App Store Connect API anahtarıyla otomatik imzalamaya hazırlar:
  • Paket kimliğini (bundle id) sabitler
  • Takım kimliğini (DEVELOPMENT_TEAM) yazar
  • CODE_SIGN_STYLE = Automatic yapar — profilleri Xcode kendisi üretir

Çevre değişkenleri:
  TEAM_ID     Apple Developer takım kimliği (10 karakter)
  BUNDLE_ID   Paket kimliği, örn. com.sleepify.app
"""
import os
import pathlib
import re
import sys

team = os.environ.get('TEAM_ID', '').strip()
bundle = os.environ.get('BUNDLE_ID', 'com.sleepify.app').strip()

if not team:
    sys.exit('TEAM_ID tanımlı değil. GitHub sırlarına APPLE_TEAM_ID ekle.')

pbx = pathlib.Path('ios/Runner.xcodeproj/project.pbxproj')
if not pbx.exists():
    sys.exit('project.pbxproj yok. Önce: flutter create . --platforms=ios')

t = pbx.read_text(encoding='utf-8')

# ---- paket kimliği ----
t = re.sub(r'PRODUCT_BUNDLE_IDENTIFIER = [^;]+;',
           f'PRODUCT_BUNDLE_IDENTIFIER = {bundle};', t)

# ---- takım kimliği: yoksa ekle, varsa güncelle ----
if 'DEVELOPMENT_TEAM' in t:
    t = re.sub(r'DEVELOPMENT_TEAM = [^;]*;', f'DEVELOPMENT_TEAM = {team};', t)
else:
    t = t.replace('PRODUCT_BUNDLE_IDENTIFIER =',
                  f'DEVELOPMENT_TEAM = {team};\n\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER =')

# ---- otomatik imzalama ----
if 'CODE_SIGN_STYLE' in t:
    t = re.sub(r'CODE_SIGN_STYLE = [^;]*;', 'CODE_SIGN_STYLE = Automatic;', t)
else:
    t = t.replace('PRODUCT_BUNDLE_IDENTIFIER =',
                  'CODE_SIGN_STYLE = Automatic;\n\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER =')

# Elle profil ataması varsa kaldır: otomatik imzalamayla çakışır
t = re.sub(r'\s*PROVISIONING_PROFILE_SPECIFIER = [^;]*;', '', t)
t = re.sub(r'\s*CODE_SIGN_IDENTITY = "iPhone Distribution[^"]*";', '', t)

pbx.write_text(t, encoding='utf-8')
print(f'✓ imzalama hazır · takım {team} · paket {bundle}')

# ---- dışa aktarma seçenekleri ----
export = pathlib.Path('ios/ExportOptions.plist')
export.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store</string>
  <key>teamID</key><string>{team}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>uploadBitcode</key><false/>
  <key>destination</key><string>export</string>
</dict>
</plist>
''', encoding='utf-8')
print('✓ ExportOptions.plist yazıldı')
