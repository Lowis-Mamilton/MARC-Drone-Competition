"""Package the tested Windows application and corresponding project sources."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import hashlib

root = Path(__file__).resolve().parents[1]
dist = root / 'dist'
source_zip = dist / 'MARCDroneSimulator-source.zip'
portable_zip = dist / 'MARCDroneSimulator-Windows-x64.zip'
source_dirs = ('src', 'addons', 'config', 'schemas', 'scripts', 'tests', 'docs', 'examples', 'web')
source_files = ('project.godot', 'export_presets.cfg', 'package.json', 'README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'icon.svg', 'start-simulator.ps1', '.gitignore')

def include_file(path):
    return path.is_file() and path.suffix not in ('.import', '.pyc') and '__pycache__' not in path.parts

with ZipFile(source_zip, 'w', ZIP_DEFLATED, compresslevel=6) as archive:
    for name in source_files:
        path = root / name
        if path.is_file(): archive.write(path, path.relative_to(root))
    for name in source_dirs:
        for path in sorted((root / name).rglob('*')):
            if include_file(path): archive.write(path, path.relative_to(root))
    for path in sorted((root / 'scratch').glob('*')):
        if include_file(path): archive.write(path, path.relative_to(root))
    for package in ('scratch-gui', 'scratch-vm'):
        upstream = root / 'scratch/node_modules/@scratch' / package
        for sub in ('src', 'LICENSE', 'package.json', 'README.md'):
            base = upstream / sub
            paths = base.rglob('*') if base.is_dir() else [base]
            for path in paths:
                if include_file(path):
                    archive.write(path, Path('upstream-sources') / package / path.relative_to(upstream))

with ZipFile(portable_zip, 'w', ZIP_DEFLATED, compresslevel=6) as archive:
    for name in ('MARCDroneSimulator.exe', 'MARCDroneSimulator.pck', 'README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', source_zip.name):
        archive.write(dist / name, name)
    for directory in ('web', 'examples', 'docs'):
        for path in sorted((dist / directory).rglob('*')):
            if include_file(path): archive.write(path, path.relative_to(dist))

for path in (source_zip, portable_zip):
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    (dist / (path.name + '.sha256')).write_text(f'{digest}  {path.name}\n', encoding='ascii')
    print(f'{path.name}: {path.stat().st_size / 1024 / 1024:.1f} MB SHA256 {digest}')
