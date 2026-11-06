#!/usr/bin/env python3
"""Run release checks, then prove two package builds produce identical bytes."""
import subprocess
import sys
import shutil
import tempfile
from zipfile import ZipFile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
for script in ['tests/run.py', 'tests/validate.py', 'scripts/package.py']:
    subprocess.run([sys.executable, str(ROOT/script)], cwd=ROOT, check=True)
first = {p.name: p.read_bytes() for p in (ROOT/'dist').glob('*.zip')}
subprocess.run([sys.executable, str(ROOT/'scripts/package.py')], cwd=ROOT, check=True)
assert all((ROOT/'dist'/name).read_bytes() == data for name, data in first.items())
print('Release checks passed; ZIP rebuild is byte-identical. In-game validation is still required.')

# Exercise the distributed addon, not only the source working tree.
with tempfile.TemporaryDirectory(prefix='rpjournal-package-') as directory:
    target = Path(directory)
    shutil.copytree(ROOT/'tests', target/'tests', ignore=shutil.ignore_patterns('__pycache__'))
    version = next(line.split(': ', 1)[1] for line in (ROOT/'CharacterMemory/CharacterMemory.toc').read_text().splitlines() if line.startswith('## Version: '))
    with ZipFile(ROOT/'dist'/f'RPJournal-Forever-{version}.zip') as archive:
        archive.extractall(target)
    subprocess.run([sys.executable, str(target/'tests/run.py')], cwd=target, check=True)
print('Packaged addon passed the integration suite.')
