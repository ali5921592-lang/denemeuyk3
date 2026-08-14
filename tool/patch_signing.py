#!/usr/bin/env python3
"""
Sleepify · imzalama yaması

`flutter create` ile üretilen android/app/build.gradle(.kts) dosyasına
release imzalama yapılandırmasını ekler. Play Store yalnızca imzalı AAB
kabul eder; imzasız derleme yüklenemez.

android/key.properties dosyası iş akışı tarafından oluşturulur.
"""
import pathlib
import sys

root = pathlib.Path('android')
if not root.exists():
    sys.exit('android/ klasörü yok. Önce: flutter create . --platforms=android')

kts = root / 'app/build.gradle.kts'
groovy = root / 'app/build.gradle'

# ---------------------------------------------------------------- Kotlin DSL
if kts.exists():
    g = kts.read_text(encoding='utf-8')
    if 'keystoreProperties' in g:
        print('imzalama zaten tanımlı'); sys.exit(0)

    header = '''import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

'''
    g = header + g

    signing = '''
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
'''
    g = g.replace('buildTypes {', signing + '\n    buildTypes {', 1)
    g = g.replace('signingConfig = signingConfigs.getByName("debug")',
                  'signingConfig = signingConfigs.getByName("release")')
    kts.write_text(g, encoding='utf-8')
    print('✓ build.gradle.kts: release imzalama eklendi')

# ------------------------------------------------------------------- Groovy
elif groovy.exists():
    g = groovy.read_text(encoding='utf-8')
    if 'keystoreProperties' in g:
        print('imzalama zaten tanımlı'); sys.exit(0)

    header = '''def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

'''
    g = header + g

    signing = '''
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }
'''
    g = g.replace('buildTypes {', signing + '\n    buildTypes {', 1)
    g = g.replace('signingConfig signingConfigs.debug',
                  'signingConfig signingConfigs.release')
    groovy.write_text(g, encoding='utf-8')
    print('✓ build.gradle: release imzalama eklendi')

else:
    sys.exit('app/build.gradle bulunamadı')
