#!/usr/bin/env python3
"""Extract the selected scissors snip from the user-provided MP3 using ffmpeg."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path, help='User-provided scissors MP3')
args = parser.parse_args()
if not args.source.is_file():
    parser.error('Source audio does not exist')
output = Path(__file__).resolve().parents[1] / 'MacKit/Resources/Cut.wav'
output.parent.mkdir(parents=True, exist_ok=True)
# Keep the main snip and natural tail; remove the surrounding silence.
# Tiny fades only suppress boundary clicks, without replacing the source sound.
subprocess.run([
    'ffmpeg', '-v', 'error', '-y', '-i', str(args.source),
    '-af', 'atrim=start=0.085:end=0.235,asetpts=PTS-STARTPTS,afade=t=in:d=0.002,afade=t=out:st=0.142:d=0.008',
    '-ac', '1', '-ar', '44100', '-c:a', 'pcm_s16le', '-map_metadata', '-1', str(output)
], check=True)
print(f'{output.name}: 0.15s, {output.stat().st_size} bytes')
