"""Build the update payload consumed by the persistent launcher."""
from pathlib import Path
import shutil
import sys
import zipfile


def package(root):
    name = (root / 'VERSION').read_text().strip()
    sys.path.insert(0, str(root / 'launcher'))
    from updater import version
    version(name)
    release = root / 'dist' / 'PulseFour'
    for required in ['PulseFour.exe', 'PulseLobby.exe', 'importer/PulseImporter.exe']:
        if not (release / required).is_file():
            raise RuntimeError('Missing release component: ' + required)
    shutil.copy(root / 'VERSION', release / 'VERSION')
    output = root / 'dist' / 'PulseFour-update.zip'
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=1) as z:
        for path in sorted(release.rglob('*')):
            if path.is_file():
                z.write(path, path.relative_to(release))
    if output.stat().st_size >= 2_000_000_000:
        raise RuntimeError('Release is too large for the updater; split runtime components before publishing')
    print(output)

if __name__ == '__main__':
    package(Path(__file__).resolve().parents[1])
