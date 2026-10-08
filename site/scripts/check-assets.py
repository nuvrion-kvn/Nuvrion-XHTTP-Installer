#!/usr/bin/env python3
"""Read-only deployment asset verification. No source image writes or edits."""
import argparse
import json
from pathlib import Path
from PIL import Image

EXPECTED_PHOTOS = {
    'world-guinness', 'world-guinness-zero', 'world-guinness-fes',
    'world-chimay-blue', 'world-chimay-red', 'world-extra-augustiner',
    'world-extra-ayinger', 'world-extra-rochefort', 'world-extra-orval',
    'world-extra-brooklyn', 'world-extra-samuel', 'world-extra-karmeliet',
    'ru-gorky-get-lost',
}


def metrics(path):
    with Image.open(path) as source:
        source.load()
        rgba = source.convert('RGBA')
        width, height = rgba.size
        alpha = rgba.getchannel('A')
        histogram = alpha.histogram()
        area = width * height
        transparent = sum(histogram[:16]) / area
        solid = sum(histogram[240:]) / max(sum(histogram[1:]), 1)
        corners = [rgba.getpixel(xy) for xy in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]]
        edge = [rgba.getpixel((x, 0)) for x in range(width)] + [rgba.getpixel((x, height - 1)) for x in range(width)]
        edge += [rgba.getpixel((0, y)) for y in range(1, height - 1)] + [rgba.getpixel((width - 1, y)) for y in range(1, height - 1)]
        opaque_white_edge = sum(a > 200 and min(r, g, b) >= 235 for r, g, b, a in edge) / max(len(edge), 1)
        return {'width': width, 'height': height, 'transparentPct': round(transparent * 100, 3),
                'foregroundSolidPct': round(solid * 100, 3), 'maxAlpha': alpha.getextrema()[1],
                'cornerAlpha': [p[3] for p in corners], 'opaqueWhiteEdgePct': round(opaque_white_edge * 100, 3)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', default=str(Path(__file__).resolve().parents[1] / 'dist'))
    parser.add_argument('--json-output')
    args = parser.parse_args()
    root = Path(args.root).resolve()
    beers = json.loads((root / 'beers.json').read_text())
    failures = []
    warnings = []
    rows = []
    photos = {b['id'] for b in beers if b.get('imageType') == 'photo'}
    if len(beers) != 96:
        failures.append(f'Expected 96 beers, found {len(beers)}')
    if len({b['id'] for b in beers}) != len(beers):
        failures.append('Duplicate beer IDs')
    if photos != EXPECTED_PHOTOS:
        failures.append(f'Photo classification differs: missing {sorted(EXPECTED_PHOTOS-photos)}, extra {sorted(photos-EXPECTED_PHOTOS)}')
    for beer in beers:
        path = (root / beer['image'].lstrip('/')).resolve()
        if not path.is_relative_to(root / 'assets') or not path.is_file():
            failures.append(f"{beer['id']}: missing or external asset {beer['image']}")
            continue
        try:
            info = metrics(path)
        except Exception as error:
            failures.append(f"{beer['id']}: unreadable asset ({error})")
            continue
        row = {'id': beer['id'], 'image': beer['image'], 'type': 'photo' if beer['id'] in photos else 'packshot', **info}
        rows.append(row)
        if row['type'] == 'packshot':
            if info['transparentPct'] < 1:
                failures.append(f"{beer['id']}: product background has no meaningful transparent area")
            if any(a > 16 for a in info['cornerAlpha']):
                failures.append(f"{beer['id']}: opaque rectangle corner(s) {info['cornerAlpha']}")
            if info['maxAlpha'] < 250:
                failures.append(f"{beer['id']}: product lacks opaque foreground (max alpha {info['maxAlpha']})")
            if info['opaqueWhiteEdgePct'] > 0.5:
                warnings.append(f"{beer['id']}: white opaque perimeter {info['opaqueWhiteEdgePct']}%, manual inspection needed")
    report = {'catalogCount': len(beers), 'photoCount': len(photos), 'packshotCount': len(beers)-len(photos),
              'uniqueAssets': len({b['image'] for b in beers}), 'failures': failures, 'warnings': warnings, 'assets': rows}
    if args.json_output:
        Path(args.json_output).write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps({k:v for k,v in report.items() if k != 'assets'}, ensure_ascii=False, indent=2))
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
