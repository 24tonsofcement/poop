"""Preserve installed Python distribution licenses in the release bundle."""
from importlib import metadata
from pathlib import Path
import shutil
import sys
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
manifest = []
for dist in metadata.distributions():
    name = dist.metadata.get('Name', 'unknown')
    manifest.append(f'{name}=={dist.version}: {dist.metadata.get("License", "See included license / project metadata")}')
    for entry in dist.files or []:
        if any(part.upper().startswith(('LICENSE', 'COPYING', 'NOTICE')) for part in Path(str(entry)).parts):
            source = Path(dist.locate_file(entry))
            if source.is_file():
                target = out / name / str(entry).replace('..', '_')
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
(out / 'PYTHON-PACKAGES.txt').write_text('\n'.join(manifest), encoding='utf-8')
