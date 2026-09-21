#!/usr/bin/env bash
set -euo pipefail
adb install -r dist/PulseFour-Android.apk
adb logcat -c
adb shell monkey -p org.pulsefour.mobile -c android.intent.category.LAUNCHER 1
sleep 18
adb shell pidof org.pulsefour.mobile
adb shell input tap 960 600
sleep 3
adb logcat -d > dist/android-logcat.txt
if grep -E 'FATAL EXCEPTION|SCRIPT ERROR|Parse Error|FAIL:' dist/android-logcat.txt; then exit 1; fi
adb exec-out screencap -p > dist/android-launch.png
