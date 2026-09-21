# Standalone Android edition

Work is isolated on the `android` branch. The PC `main` branch is unchanged.

Install the standalone APK on a 64-bit Android 8.0+ device. It includes the
six-stem model, media downloader, audio/video tools, Python analysis runtime,
and the game. No computer companion or separately installed tools are needed.
YouTube/SoundCloud imports and Claude requests require internet. Installed
songs play offline. Native source separation is CPU intensive and may take
considerably longer than the song on some phones.

## Songs and cards

Open **Songs**, paste a YouTube or SoundCloud link, and choose **Generate on
this device**. Ordinary generation requires no API key. **Regenerate selected
chart** reuses its existing audio. Card imports preserve the shared chart and
retrieve its referenced media. **Import song cards** accepts multiple original
PNGs; **Export selected card** uses the song title as its filename. Android's
file picker remembers separate import/export locations. Send cards as files,
not compressed messenger photos. Installed songs can be removed in Songs.

## Optional Claude assistance

In **Settings > Songs & AI**, enter a fresh API key, refresh available models,
and choose an exact model your account supports. Then enable **Claude-assisted
charts** in Songs. API usage is billed to that key. Keys are encrypted using
Android Keystore and are never bundled, logged, sent in prompts or included
in exported cards. The exposed key from the conversation must be revoked.

The editor uses measured per-instrument rhythms, pitch contours, recurring
phrases, sustain evidence, hype candidates and aggregate measurements from
the supplied 169-chart mania study. It preserves supported timing and validates
playability. This is evidence-grounded assistance, not direct audio input to
Claude or a trained charting model. Human playtesting is still needed to judge
musical quality. See [native implementation notes](native/README.md).

## Updates and installation identity

The new package is `org.pulsefour.standalone`, isolated from the previous
companion-only APK. Game-content updates use the separate `android-standalone`
prerelease channel, with SHA-256 verification, staged installation and startup
rollback. Scores, settings and songs are stored separately from updates.
Native libraries and bundled Python changes require an APK update signed with
the same private identity; Android requires installation confirmation. Do not
uninstall the standalone app to update it, because uninstalling removes its
private songs and scores.

The published APK is signed locally. Public signature patches let CI publish
the tested APK without receiving the private signing key. PC releases and the
old Android channel are not replaced. The original computer-companion utility
remains in source for legacy installations but is unnecessary for this edition.
