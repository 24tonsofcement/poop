# Android branch

This branch does not change the Windows/main release. Android releases are prereleases named `android-channel`, so the desktop updater never selects them.

## Install and play

Download PulseFour-Android.apk from the Android early-access release, allow installation from your browser/file manager, and open it. The included demo works offline. Play landscape: each quarter of the screen is one touch lane. Multiple fingers can hold independent lanes; fingers remain on their original lane until lifted. The top-right pause button and Android Back pause local play. Online rounds cannot pause.

Settings include note speed, input calibration, audio, effects, hype, video brightness and highway opacity. One player per phone. Existing manual LAN/internet lobbies support song downloads; use a reachable server address rather than localhost. A phone can create a room on a running server but does not run the desktop server executable.

## Add your songs

Run the companion on the computer that has your existing imported song library. No desktop game files are modified:

```
python mobile/companion.py --songs "C:\Users\YOURNAME\AppData\Roaming\Godot\app_userdata\Pulse Four\songs" --worker "C:\path\to\PulseFour\importer\PulseImporter.exe"
```

Use your actual library/importer paths. The computer prints an access token. In phone Settings > Songs, enter `http://COMPUTER_LAN_IP:27441` and that token. Both devices must be on the same network, and the computer firewall must allow this port on the private network. Do not expose this plain-HTTP service to the public internet. A reverse proxy with HTTPS is needed for remote use.

Browse companion songs and download them for offline play, including chart, audio, artwork and video. You can also submit YouTube/SoundCloud URLs; generation runs on the computer and can take several minutes. The installed desktop importer supplies dependencies. Without `--worker`, install the Python importer dependencies and FFmpeg/yt-dlp/Deno on the computer. Existing downloaded song packs and the bundled demo need no running companion.

PNG card import/export and direct phone-based Demucs generation are not included yet. Import cards on the computer, then download the resulting song from the companion. The song library provides deletion without deleting personal records.

## Updates

The base APK uses Godot 4.4.1. Its boot scene checks only `android-channel`, downloads the PCK over HTTPS, verifies SHA-256, and mounts it before loading game scripts. Downloads stage separately; failed/offline checks use the installed content. A trial marker discards a failed startup bundle next launch. Only one installed content bundle is retained after successful startup. Songs/settings/scores live separately in private app storage.

The CI retains the first APK rather than replacing it with a differently signed build. Future updates normally replace the PCK, not the APK. Android itself still requires confirmation for an eventual native APK upgrade; content updates cannot upgrade the engine or permissions. Uninstalling the app deletes private data.

CI validates GDScript imports, multi-touch state, demo startup, mobile settings, and companion library path handling, then exports an APK for ARM64, ARMv7 and x86_64. Automated headless checks do not replace physical-device testing.
