#!/usr/bin/env python3
"""Validate the exact WoW install layout, independently of package construction."""
from pathlib import PurePosixPath
from zipfile import ZipFile
import stat
import sys


def validate_package(path):
    with ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise ValueError('Corrupt ZIP member')
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate ZIP members')
        for info in archive.infolist():
            name = info.filename
            parts = PurePosixPath(name).parts
            if (not parts or parts[0] != 'CharacterMemory' or '\\' in name
                    or '..' in parts or any(p.startswith('.') for p in parts)
                    or (len(parts) == 1 and not info.is_dir())):
                raise ValueError(f'Every file must be inside CharacterMemory/: {name}')
            if stat.S_ISLNK(info.external_attr >> 16):
                raise ValueError(f'Symlink in package: {name}')
        toc = 'CharacterMemory/CharacterMemory.toc'
        if toc not in names or 'CharacterMemory/Bindings.xml' not in names:
            raise ValueError('Missing addon manifest or bindings at the install root')
        manifest = archive.read(toc).decode('utf-8')
        for line in manifest.splitlines():
            name = line.strip()
            if name and not name.startswith('#') and 'CharacterMemory/' + name not in names:
                raise ValueError(f'Missing manifest member: {name}')
        return len(names)


if __name__ == '__main__':
    for path in sys.argv[1:]:
        print(f'{path}: {validate_package(path)} members; one valid CharacterMemory/ root')
