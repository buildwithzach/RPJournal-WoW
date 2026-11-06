#!/usr/bin/env python3
"""Build a reproducible installable ZIP and SHA-256 sidecar."""
import hashlib
import re
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
ROOT = Path(__file__).resolve().parents[1]
addon = ROOT / 'CharacterMemory'
manifest = (addon/'CharacterMemory.toc').read_text()
version = re.search(r'^## Version: ([0-9]+\.[0-9]+\.[0-9]+)$', manifest, re.M)[1]
assert '## Interface: 16001' in manifest
out = ROOT/'dist'/f'RPJournal-Forever-{version}.zip'
out.parent.mkdir(exist_ok=True)
# Keep source artwork in Git; ship only textures referenced by the runtime.
textures = {'Art/parchment.tga', 'media/cmjournal.tga', 'media/CMcompact.tga'}
paths = sorted(p for p in addon.rglob('*') if p.is_file() and
               (p.suffix.lower() in {'.toc', '.lua', '.xml'} or
                p.relative_to(addon).as_posix() in textures))
for path in paths:
    if path.suffix in {'.lua', '.xml', '.toc'}:
        source = path.read_text().replace(chr(92), '/')
        for ref in re.findall(r'Interface/AddOns/CharacterMemory/([A-Za-z0-9_./-]+\.(?:png|tga|blp))', source):
            assert ref in textures, f'Runtime texture omitted: {ref}'
paths += [ROOT/name for name in ['INSTALL-FOREVER.txt','README.md','CHANGELOG.md']]
with ZipFile(out, 'w', ZIP_DEFLATED, compresslevel=9) as bundle:
    for path in paths:
        assert not path.is_symlink(), f'Symlinks cannot be packaged: {path}'
        info = ZipInfo(path.relative_to(ROOT).as_posix(), date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = ZIP_DEFLATED
        info.create_system = 3
        info.external_attr = 0o100644 << 16
        bundle.writestr(info, path.read_bytes())
with ZipFile(out) as bundle:
    assert bundle.testzip() is None
    assert 'CharacterMemory/CharacterMemory.toc' in bundle.namelist()
    assert 'CharacterMemory/Bindings.xml' in bundle.namelist()
    for line in manifest.splitlines():
        if line.strip().endswith(('.lua','.xml')):
            assert 'CharacterMemory/'+line.strip() in bundle.namelist()
    assert not any(name.startswith(('tests/','experiments/','.git/')) for name in bundle.namelist())
digest = hashlib.sha256(out.read_bytes()).hexdigest()
out.with_suffix('.zip.sha256').write_text(f'{digest}  {out.name}\n')
print(out)
print('SHA256', digest)
print('Bytes', out.stat().st_size)
