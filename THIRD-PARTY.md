# Dependencies and technical references

This source ZIP includes original code and demo audio. It does not contain the third-party binaries or model weights. The Windows build collects Python-package license files and retains the FFmpeg distribution and primary binary licenses in the output's `licenses/` directory. Consult each upstream license before redistributing a built bundle.

- Godot 4.4.1 — MIT. https://godotengine.org/license/
- Demucs 4.0.1 and htdemucs — see the repository and model licensing. https://github.com/facebookresearch/demucs
- PyTorch / torchaudio — BSD-style licenses and bundled dependency notices. https://github.com/pytorch/pytorch/blob/main/LICENSE
- NumPy — BSD-3-Clause. https://numpy.org/doc/stable/license.html
- SciPy — BSD-3-Clause and third-party notices. https://github.com/scipy/scipy/blob/main/LICENSE.txt
- PyInstaller — GPL with bootloader exception. https://pyinstaller.org/en/stable/license.html
- yt-dlp — Unlicense source; its distributed executable contains additional dependencies with their own terms. https://github.com/yt-dlp/yt-dlp#license
- Deno — MIT with third-party notices. https://github.com/denoland/deno
- FFmpeg — the build script selects BtbN's LGPL shared build and retains its files. https://ffmpeg.org/legal.html and https://github.com/BtbN/FFmpeg-Builds
- SoundFile and libsndfile — BSD / LGPL, respectively. https://github.com/bastibe/python-soundfile

Primary implementation references checked during development:

- Godot Windows export / command line: https://docs.godotengine.org/en/4.4/tutorials/export/exporting_projects.html
- Runtime WAV loading: https://docs.godotengine.org/en/4.4/classes/class_audiostreamwav.html
- osu file fields and mania hold objects: https://osu.ppy.sh/wiki/en/Client/File_formats/osu_%28file_format%29
- yt-dlp installation and runtime requirements: https://github.com/yt-dlp/yt-dlp
- Demucs four-part separation: https://github.com/facebookresearch/demucs

The game is independent of osu!, YouTube, and those projects. No commercial songs or third-party beatmaps are bundled. The demo “First Light” was synthesized specifically for this project.
