"""Cache model weights at build time; frozen imports need no model download."""
import os
from pathlib import Path
import sys
os.environ['TORCH_HOME'] = str(Path(sys.argv[1]).resolve())
from demucs.pretrained import get_model
get_model('htdemucs')
print('Demucs weights cached.')
