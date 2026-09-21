"""Prepare Godot's pinned Gradle template without editing the PC project."""
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET
root=Path('android/build')
root.parent.joinpath('.build_version').write_text('4.4.1.stable')
root.parent.joinpath('.gdignore').touch()
s=root.joinpath('build.gradle').read_text().replace("id 'org.jetbrains.kotlin.android'", "id 'org.jetbrains.kotlin.android'\n    id 'com.chaquo.python' version '17.0.0'")
s=s.replace('minSdkVersion getExportMinSdkVersion()', 'minSdkVersion Math.max(26, Integer.parseInt(getExportMinSdkVersion().toString()))')
s=s.replace('dependencies {','''dependencies {
    implementation 'io.github.junkfood02.youtubedl-android:library:0.18.1'
    implementation 'io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1'
''',1)
s+='''
chaquopy {
    defaultConfig {
        version = '3.10'
        pip {
            install 'numpy'
            install 'scipy==1.8.1'
            install 'Pillow'
            install 'certifi'
        }
    }
    sourceSets { getByName('main') { srcDir 'python' } }
}
android {
    packagingOptions { jniLibs { useLegacyPackaging true } }
    sourceSets { main { jniLibs.srcDirs += ['native-libs']; assets.srcDirs += ['native-assets'] } }
}
'''
root.joinpath('build.gradle').write_text(s)
shutil.copytree('mobile/native/src',root/'src/org/pulsefour/nativeimport',dirs_exist_ok=True)
shutil.copytree('mobile/native/python',root/'python',dirs_exist_ok=True)
for name in ['worker','charting','arrangement','instruments','hype','timing','sources','song_card','static_background']:
    shutil.copy2(f'importer/{name}.py',root/f'python/{name}.py')
# Pillow Android wheel may predate scalable load_default; use bundled Android fonts instead.
p=root/'python/song_card.py';s=p.read_text().replace("ImageFont.load_default(size=22)","ImageFont.truetype('/system/fonts/Roboto-Regular.ttf',22)").replace("ImageFont.load_default(size=15)","ImageFont.truetype('/system/fonts/Roboto-Regular.ttf',15)").replace("['C:/Windows/Fonts/meiryo.ttc'", "['/system/fonts/NotoSansCJK-Regular.ttc', 'C:/Windows/Fonts/meiryo.ttc'");p.write_text(s)
a='{http://schemas.android.com/apk/res/android}'
ET.register_namespace('android',a[1:-1]);ET.register_namespace('tools','http://schemas.android.com/tools')
p=root/'AndroidManifest.xml';tree=ET.parse(p);manifest=tree.getroot()
for permission in ['INTERNET','FOREGROUND_SERVICE','FOREGROUND_SERVICE_DATA_SYNC']:
    ET.SubElement(manifest,'uses-permission',{a+'name':'android.permission.'+permission})
app=manifest.find('application');app.set(a+'extractNativeLibs','true')
ET.SubElement(app,'meta-data',{a+'name':'org.godotengine.plugin.v2.PulseNative',a+'value':'org.pulsefour.nativeimport.PulseNative'})
ET.SubElement(app,'service',{a+'name':'org.pulsefour.nativeimport.ImportService',a+'exported':'false',a+'foregroundServiceType':'dataSync'})
tree.write(p,encoding='utf-8',xml_declaration=True)
