"""Create a tiny local test video for the Godot playback smoke test."""
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'importer'))
from worker import encode_background, Job
out = root / 'build' / 'video-test'
out.mkdir(parents=True, exist_ok=True)
subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc2=size=160x120:rate=12', '-t', '2', '-c:v', 'mpeg4', str(out / 'source.mp4')], check=True)
encode_background(out / 'source.mp4', out / 'background.ogv', Job(out / 'job.json'))
