#!/usr/bin/env python3
"""Reject incompatible, incomplete or development-only release archives."""
import argparse
from pathlib import Path
import re
import zipfile

PREFIX='!!!LuaWorkbench/'
INTERFACES = {16001, 20506, 120100, 120105, 120107}


def validate(path, tag):
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        assert archive.testzip() is None
        assert all(name.startswith(PREFIX) and '..' not in Path(name).parts for name in names)
        banned = ('.github/', 'scripts/', 'Artwork/', 'docs/', '.env', '.git', 'build.sh', '.release')
        assert not any(name[len(PREFIX):].startswith(banned) for name in names)
        toc=archive.read(PREFIX+'!!!LuaWorkbench.toc').decode('utf-8-sig')
        interfaces = re.findall(r'^## Interface: (.+)$', toc, re.M)
        assert len(interfaces) == 1
        assert {int(v.strip()) for v in interfaces[0].split(',')} == INTERFACES
        assert re.search(r'^## Version: '+re.escape(tag)+r'\s*$',toc,re.M)
        assert '@project-version@' not in toc and 'Dependencies:' not in toc
        assert {name for name in names if name.endswith('.toc')} == {PREFIX+'!!!LuaWorkbench.toc'}
        for line in toc.splitlines():
            if line.strip() and not line.startswith('#'):
                assert PREFIX+line.replace('\\','/') in names,line
        for required in ['Assets/Icon.tga','LICENSE','THIRD_PARTY.md','PACKAGE_CHANGELOG.md']:
            assert PREFIX+required in names,required
        notes=archive.read(PREFIX+'PACKAGE_CHANGELOG.md').decode('utf-8-sig')
        assert '## ['+tag+']' in notes and '[Unreleased]' not in notes
    print('Verified release archive:',Path(path).name,tag)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag');parser.add_argument('archive')
    a=parser.parse_args();validate(a.archive,a.tag)
