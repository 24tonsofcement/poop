import hashlib
import json
from pathlib import Path
root = Path('dist')
pack = root / 'PulseFour-Android.pck'
(root / 'android-update.json').write_text(json.dumps({
    'runtime': 'godot-4.4.1-android-2',
    'version': Path('mobile/VERSION').read_text().strip(),
    'sha256': hashlib.sha256(pack.read_bytes()).hexdigest(),
    'url': 'https://github.com/24tonsofcement/poop/releases/download/android-standalone/PulseFour-Android.pck',
}))
