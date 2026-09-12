"""Verify Demucs outputs or atomically package an existing Windows release."""
import os
from pathlib import Path
import sys
import wave
import zipfile

def verify(folder):
    signatures = []
    for name in ('drums', 'bass', 'vocals', 'other', 'guitar', 'piano'):
        with wave.open(str(folder / (name + '.wav')), 'rb') as audio:
            if audio.getsampwidth() != 2 or audio.getcomptype() != 'NONE':
                raise ValueError(name + ': expected PCM16 WAV')
            if audio.getnframes() <= 0:
                raise ValueError(name + ': empty stem')
            signatures.append((audio.getframerate(), audio.getnframes(), audio.getnchannels()))
    if len(set(signatures)) != 1:
        raise ValueError('Stems do not share the same timeline')
    print('Verified all six PCM16 stems on the same timeline.')

def package(release, output):
    if not (release / 'PulseFour.exe').is_file() or not (release / 'importer' / 'PulseImporter.exe').is_file():
        raise ValueError('Game or importer executable missing')
    temporary = output.with_suffix('.zip.partial')
    files = sorted(p for p in release.rglob('*') if p.is_file())
    with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED, compresslevel=1) as archive:
        for path in files:
            archive.write(path, Path('PulseFour') / path.relative_to(release))
    os.replace(temporary, output)
    print('Packaged', len(files), 'files into', output)

if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'verify':
        verify(Path(sys.argv[2]))
    elif len(sys.argv) == 4 and sys.argv[1] == 'zip':
        package(Path(sys.argv[2]), Path(sys.argv[3]))
    else:
        raise SystemExit('Usage: finish_repair.py verify STEM_FOLDER | zip RELEASE_FOLDER OUTPUT_ZIP')
