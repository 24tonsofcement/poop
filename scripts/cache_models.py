"""Cache only the active separator model, replacing obsolete model weights."""
import os
from pathlib import Path
import shutil
import sys
import tempfile

target = Path(sys.argv[1]).resolve()
target.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='model-cache-', dir=target.parent) as tmp:
    os.environ['TORCH_HOME'] = tmp
    from demucs.pretrained import get_model
    get_model('htdemucs_6s')
    if target.exists(): shutil.rmtree(target)
    shutil.copytree(tmp, target)
print('Active Demucs weights cached; obsolete weights removed.')
