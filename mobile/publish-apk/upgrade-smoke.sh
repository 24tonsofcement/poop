#!/usr/bin/env bash
set -euo pipefail
package=org.pulsefour.standalone
# Upgrade the actual previously published APK; preserve its package data.
adb install --no-incremental -r release/previous.apk
adb shell run-as "$package" mkdir -p files shared_prefs
printf '%s' '{"volume":0.37,"offset":42,"scroll_speed":777}' | adb shell run-as "$package" sh -c "'cat > files/settings.json'"
printf '%s' '<?xml version="1.0" encoding="utf-8"?><map><string name="model">upgrade-test-model</string><string name="last_import">content://test/import</string><string name="last_export">content://test/export</string></map>' | adb shell run-as "$package" sh -c "'cat > shared_prefs/private_import.xml'"
adb shell run-as "$package" sh -c "'echo retained-song-data > files/preserved-song-test'"
adb install --no-incremental -r release/PulseFour-Android.apk
adb shell settings put secure immersive_mode_confirmations confirmed
adb shell am start -n "$package/com.godot.game.GodotApp" --es pulse_update_probe seed
sleep 20
adb shell run-as "$package" cat files/update-probe-result | grep '^PASS:'
adb shell run-as "$package" cat files/settings.json > release/upgrade-settings.json
adb shell run-as "$package" cat shared_prefs/private_import.xml > release/upgrade-prefs.xml
python - <<'VERIFY'
import json,xml.etree.ElementTree as ET
s=json.load(open('release/upgrade-settings.json'))
assert s['volume']==0.37 and s['offset']==42 and s['scroll_speed']==777
p={e.attrib['name']:e.text for e in ET.parse('release/upgrade-prefs.xml').getroot()}
assert p['model']=='upgrade-test-model' and p['last_import']=='content://test/import' and p['last_export']=='content://test/export'
VERIFY
adb shell run-as "$package" cat files/preserved-song-test | grep retained-song-data
adb shell am force-stop "$package"
adb shell run-as "$package" rm files/update-probe-result
# Replace the signed APK again and verify the retained encrypted preference decrypts.
adb install --no-incremental -r release/PulseFour-Android.apk
adb shell am start -n "$package/com.godot.game.GodotApp" --es pulse_update_probe check
sleep 8
adb shell run-as "$package" cat files/update-probe-result | grep '^PASS:'
adb shell am force-stop "$package"
