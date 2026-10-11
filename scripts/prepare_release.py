#!/usr/bin/env python3
"""Prepare shared release notes from one exact, nonempty changelog section."""
import argparse
from pathlib import Path
import re

NAME = '!!!LuaWorkbench'
TAG = re.compile(r'\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)\d+)?\Z')


def prepare(root, tag, output):
    if not TAG.fullmatch(tag):
        raise ValueError('Use major.minor.patch, optionally followed by -alphaN, -betaN or -rcN')
    root, output = Path(root), Path(output)
    source = (root / 'CHANGELOG.md').read_text()
    headings = list(re.finditer(r'^## \[([^\]]+)\][^\n]*$', source, re.M))
    matches = [(i, h) for i, h in enumerate(headings) if h[1] == tag]
    if len(matches) != 1:
        raise ValueError('Expected exactly one changelog section for ' + tag)
    index, heading = matches[0]
    end = headings[index + 1].start() if index + 1 < len(headings) else len(source)
    notes = re.sub(r'<!--.*?-->', '', source[heading.start():end], flags=re.S).strip() + '\n'
    if not re.search(r'^\s*[-*]\s+\S', notes, re.M):
        raise ValueError('Empty tag section in CHANGELOG.md')
    output.mkdir(parents=True, exist_ok=True)
    (output / 'github.md').write_text(notes)
    (root / 'PACKAGE_CHANGELOG.md').write_text(notes)
    return notes


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--output', type=Path, default=Path('.release-notes'))
    args = parser.parse_args()
    prepare(args.root, args.tag, args.output)
