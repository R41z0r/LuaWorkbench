#!/usr/bin/env python3
"""Validate locales, runtime manifests and standalone packaging contracts."""
from pathlib import Path
import re
import struct

LOCALES = {'enUS','deDE','esES','esMX','frFR','itIT','koKR','ptBR','ruRU','zhCN','zhTW'}


def validate(root):
    root = Path(root)
    blocks = re.findall(r'\t(\w+) = \{\n(.*?)\n\t\},', (root/'Localization.lua').read_text(), re.S)
    assert {locale for locale, _ in blocks} == LOCALES, 'Locale set mismatch'
    expected = None
    for locale, body in blocks:
        keys = re.findall(r'\["(.*?)"\] = ',body)
        assert keys == sorted(set(keys)), f'Unsorted or duplicate keys: {locale}'
        assert expected is None or keys == expected, f'Key mismatch: {locale}'
        expected = keys
    refs = set()
    for path in root.glob('*.lua'):
        refs.update(re.findall(r'\bL\.([a-zA-Z][a-zA-Z0-9_]*)',path.read_text()))
        refs.update(re.findall(r'\bL\["([^"\n]+)"\]',path.read_text()))
    assert refs <= set(expected), 'Missing locale keys: '+str(refs-set(expected))
    assert sorted(p.name for p in root.glob('*.toc')) == ['!!!LuaWorkbench.toc']
    assert sorted(p.name for p in root.glob('CHANGELOG*.md')) == ['CHANGELOG.md']
    for suffix in ('',):
        text = (root/('!!!LuaWorkbench'+suffix+'.toc')).read_text()
        assert not re.search(r'^## (?:OptionalDeps|Dependencies|RequiredDeps):',text,re.M)
        assert '## X-Wago-ID: EGPaBWN1' in text and '## X-Curse-Project-ID: 1736834' in text
        assert '## X-WoWI-ID: 27254' in text
        assert '## Category: Development Tools' in text and '## X-License: MIT' in text
        for locale in LOCALES - {'enUS'}:
            assert '## Notes-'+locale+':' in text and '## Category-'+locale+':' in text
        for line in text.splitlines():
            if line.strip() and not line.startswith('#'):
                assert (root/line.replace('\\','/')).is_file(),line
    image = (root/'Assets/Icon.tga').read_bytes()
    width, height, depth = struct.unpack_from('<HHB',image,12)
    assert (width,height,depth)==(128,128,32) and image[2]==2, 'Invalid runtime icon'
    assert '/build.sh' in (root/'.gitignore').read_text()
    print('PASS: 11 locales, referenced keys, one shared standalone TOC, metadata and runtime icon')


if __name__ == '__main__':
    validate(Path(__file__).resolve().parent.parent)
