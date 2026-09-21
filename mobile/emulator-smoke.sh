#!/usr/bin/env bash
set -euo pipefail
package=org.pulsefour.mobile
adb install -r dist/PulseFour-Android.apk
adb logcat -c
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
if grep -E 'FATAL EXCEPTION|SCRIPT ERROR|Parse Error|FAIL:' dist/android-logcat.txt; then exit 1; fi
