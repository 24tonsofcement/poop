#!/usr/bin/env bash
set -euxo pipefail
capture() {
  adb logcat -d > dist/android-logcat.txt || true
  adb exec-out screencap -p > dist/android-last-screen.png || true
  grep -E 'FATAL|fatal|SIGSEGV|SIGABRT|SCRIPT ERROR|ERROR:|Godot|godot' dist/android-logcat.txt | tail -100 || true
}
trap capture EXIT
package=org.pulsefour.standalone
adb install --no-incremental -r dist/PulseFour-Android.apk
adb logcat -c
adb shell am start -n "$package/com.godot.game.GodotApp" --ez pulse_native_test true
for attempt in $(seq 1 30); do
  if adb shell run-as "$package" test -f files/native-test-result; then break; fi
  sleep 2
done
adb shell run-as "$package" cat files/native-test-result | tee dist/native-test-result.txt
grep -q '^PASS:' dist/native-test-result.txt
adb shell am force-stop "$package"
adb shell monkey -p "$package" -c android.intent.category.LAUNCHER 1
sleep 18
adb shell pidof "$package"
# Skip a slow network update check, then capture the compact menu and start demo.
adb shell input tap 960 600
sleep 3
adb exec-out screencap -p > dist/android-menu.png
adb shell input tap 960 666
sleep 4
adb shell pidof "$package"
adb exec-out screencap -p > dist/android-gameplay.png
adb shell am force-stop "$package"
# Exercise the actual APK bootloader mounting a downloaded content bundle.
adb shell run-as "$package" mkdir -p files
adb shell run-as "$package" sh -c "'cat > files/update.pck'" < dist/PulseFour-Android.pck
adb shell run-as "$package" sh -c "'echo keep-me > files/update-preservation-test'"
adb shell monkey -p "$package" -c android.intent.category.LAUNCHER 1
sleep 18
adb shell input tap 960 600
sleep 3
adb shell pidof "$package"
adb shell run-as "$package" test -f files/update-preservation-test
adb shell run-as "$package" test ! -f files/update-trial
adb logcat -d > dist/android-logcat.txt
if grep -E 'FATAL EXCEPTION|SCRIPT ERROR|Parse Error|FAIL:|E godot.*ERROR:' dist/android-logcat.txt; then exit 1; fi

python - <<'PYTEST'
from PIL import Image
for path in ['dist/android-menu.png', 'dist/android-gameplay.png']:
    image = Image.open(path).convert('RGB')
    width, height = image.size
    colors = image.crop((100, 100, width - 150, height - 100)).getcolors(5000)
    assert colors is None or len(colors) > 100, f'Blank Android render: {path}'
PYTEST
