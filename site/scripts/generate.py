import pathlib, re, json, yaml
root = pathlib.Path(__file__).resolve().parents[1]
doc = root.joinpath('DESIGN.md').read_text()
front = yaml.safe_load(doc.split('---')[1])
css = ['/* Generated from DESIGN.md by scripts/generate.py */', ':root {']
for group, prefix in [('colors','color'),('rounded','radius'),('spacing','space')]:
    for name,value in front[group].items():
        css.append(f'  --{prefix}-{name.lower()}: {value};')
for name,value in front['typography'].items():
    css.append(f'  --font-{name}: {value["fontFamily"]};')
css.append('}')
root.joinpath('dist/tokens.css').write_text('\n'.join(css)+'\n')
paths = [root/'dist/russian-beers.json', root/'dist/world-beers.json']
if all(p.exists() for p in paths):
    groups = []
    for main, extra in [('russian-beers.json','russian-extra.json'),('world-beers.json','world-extra.json')]:
        group = json.loads((root/'dist'/main).read_text())
        extra_path = root/'dist'/extra
        if extra_path.exists():
            group += json.loads(extra_path.read_text())
        groups.append(group)
    beers=[]
    # An alternating shelf puts Russian and international beers side by side.
    for i in range(max(map(len, groups))):
        beers.extend(g[i] for g in groups if i < len(g))
    root.joinpath('dist/beers.json').write_text(json.dumps(beers,ensure_ascii=False,separators=(',',':')))
    print(f'Generated tokens and {len(beers)} beers')
else:
    print('Generated tokens; catalog data pending')
