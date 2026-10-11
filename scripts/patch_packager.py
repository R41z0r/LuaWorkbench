#!/usr/bin/env python3
"""Add a fail-closed archive check and release-candidate classification to the pinned packager."""
from pathlib import Path
import sys


def patch(path):
    path=Path(path);source=path.read_text()
    anchor='if [[ -z $skip_upload && -n $archive && -s $archive ]]; then'
    assert source.count(anchor)==1,'Upload boundary changed'
    check='''# Validate this exact archive before any publisher receives it.
python3 "$topdir/scripts/validate_archive.py" "$LUAWORKBENCH_TAG" "$archive" || exit 1

'''
    source=source.replace(anchor,check+anchor)
    old='elif [[ "${tag,,}" == *"beta"* ]]; then'
    assert source.count(old)==1,'Release-type detection changed'
    source=source.replace(old,'elif [[ "${tag,,}" == *"beta"* || "${tag,,}" =~ (^|[-._])rc[0-9]*($|[-._]) ]]; then')
    path.write_text(source)


if __name__=='__main__': patch(sys.argv[1])
