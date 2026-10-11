#!/usr/bin/env python3
"""Deploy only !!!LuaWorkbench to an existing client Interface/AddOns directory."""
import argparse
import hashlib
from pathlib import Path

NAME = '!!!LuaWorkbench'
FLAVORS = ('retail', 'forever', 'tbc')


def deploy(root, target, flavor, version='dev-local'):
    root = Path(root).resolve(strict=True)
    target = Path(target).expanduser().resolve(strict=True)
    if target.name != 'AddOns' or target.parent.name != 'Interface' or not target.is_dir():
        raise ValueError('Target must be an existing Interface/AddOns directory')
    destination = target / NAME
    if destination.is_symlink() or destination == root or destination in root.parents:
        raise ValueError('Unsafe deployment destination')
    if flavor not in FLAVORS:
        raise ValueError('Unsupported deployment flavor')
    toc_name = NAME + '.toc'
    toc = (root / toc_name).read_text().replace('@project-version@', version)
    files = {}
    for line in toc.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        relative = Path(line.replace('\\', '/'))
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Unsafe TOC path')
        files[relative] = (root / relative).read_bytes()
    for path in (root / 'Assets').rglob('*'):
        if path.is_file() and path.suffix.lower() in ('.tga', '.blp'):
            files[path.relative_to(root)] = path.read_bytes()
    for name in ('LICENSE', 'THIRD_PARTY.md'):
        files[Path(name)] = (root / name).read_bytes()
    files[Path(toc_name)] = toc.encode()
    # Old client-specific TOCs override the shared TOC, so remove only our legacy manifests.
    legacy_tocs = [destination / (NAME + suffix + '.toc') for suffix in ('_Camelot', '_TBC')]
    if any(path.is_symlink() for path in legacy_tocs):
        raise ValueError('Refusing symlink legacy TOC')
    for relative in files:
        path = destination / relative
        if path.is_symlink() or any(parent.is_symlink() for parent in path.parents):
            raise ValueError('Refusing symlink destination')
    for relative, data in files.items():
        path = destination / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    for path in legacy_tocs:
        path.unlink(missing_ok=True)
    for relative, data in files.items():
        if hashlib.sha256((destination / relative).read_bytes()).digest() != hashlib.sha256(data).digest():
            raise RuntimeError(f'Deployment verification failed: {relative}')
    print(f'Verified {len(files)} files: {destination} ({flavor})')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flavor', choices=FLAVORS, required=True)
    parser.add_argument('--target', type=Path, required=True)
    parser.add_argument('--version', default='dev-local')
    args = parser.parse_args()
    deploy(Path(__file__).resolve().parent.parent, args.target, args.flavor, args.version)
