#!/usr/bin/env python3
"""Package the generated master into the standard macOS AppIcon sizes."""
import json, subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[1]
output = root / 'MacKit/Assets.xcassets/AppIcon.appiconset'
output.mkdir(parents=True, exist_ok=True)
images = []
for points in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        pixels = points * scale
        name = f'icon_{points}x{points}@{scale}x.png'
        subprocess.run(['sips', '-z', str(pixels), str(pixels), str(root / 'Assets/MacKit-Icon.png'), '--out', str(output / name)], check=True, stdout=subprocess.DEVNULL)
        images.append({'idiom': 'mac', 'size': f'{points}x{points}', 'scale': f'{scale}x', 'filename': name})
(output / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
(output.parent / 'Contents.json').write_text('{"info":{"author":"xcode","version":1}}\n')
