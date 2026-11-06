#!/usr/bin/env python3
"""Regression tests for CurseForge's top-level-file rejection."""
import sys
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from validate_package import validate_package

class PackageLayoutTests(unittest.TestCase):
    def check_members(self, extra):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'addon.zip'
            with ZipFile(path, 'w') as archive:
                archive.writestr('CharacterMemory/CharacterMemory.toc', '## Interface: 16001\nCore.lua\n')
                archive.writestr('CharacterMemory/Core.lua', '-- addon')
                archive.writestr('CharacterMemory/Bindings.xml', '<Bindings/>')
                for name in extra:
                    archive.writestr(name, 'documentation')
            return validate_package(path)

    def test_documentation_inside_addon_folder_is_valid(self):
        self.assertEqual(self.check_members(['CharacterMemory/README.md']), 4)

    def test_rejects_every_previously_shipped_top_level_document(self):
        for name in ['README.md', 'CHANGELOG.md', 'INSTALL-FOREVER.txt']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.check_members([name])

    def test_rejects_extra_roots_hidden_files_and_traversal(self):
        for name in ['RPJournal-WoW/README.md', '__MACOSX/junk', '.DS_Store',
                     'CharacterMemory/../README.md', '/CharacterMemory/README.md',
                     'CharacterMemory/.DS_Store']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.check_members([name])

if __name__ == '__main__':
    unittest.main()
