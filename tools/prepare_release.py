"""Split an existing mod ZIP into GitHub release assets and verify every byte."""
from pathlib import Path
import argparse, hashlib, json, re, zipfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--repository', required=True)
parser.add_argument('--tag', default='v0.2.4')
args = parser.parse_args()
if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repository):
    raise SystemExit('Expected owner/repository')
if not re.fullmatch(r'[A-Za-z0-9_.-]+', args.tag):
    raise SystemExit('Invalid tag')
archive = ROOT / 'KnoxNavigator.zip'
output = ROOT / 'dist' / 'release'
output.mkdir(parents=True, exist_ok=True)
parts = []
limit = 1800 * 1024 * 1024
with archive.open('rb') as source:
    index = 1
    while True:
        block = source.read(1024 * 1024)
        if not block:
            break
        name = f'KnoxNavigator.zip.{index:03}'
        digest = hashlib.sha256()
        size = 0
        with (output / name).open('wb') as destination:
            while block:
                destination.write(block)
                digest.update(block)
                size += len(block)
                if size >= limit:
                    break
                block = source.read(min(1024 * 1024, limit - size))
        parts.append(dict(name=name, size=size, sha256=digest.hexdigest()))
        print(f'{name}: {size / 1024**2:.1f} MiB', flush=True)
        index += 1
with zipfile.ZipFile(archive) as bundle:
    unpacked = sum(info.file_size for info in bundle.infolist())
manifest = dict(version=args.tag.removeprefix('v'),
                baseUrl=f'https://github.com/{args.repository}/releases/download/{args.tag}',
                parts=parts, unpackedBytes=unpacked)
(output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
checksums = '\n'.join(f'{p["sha256"]}  {p["name"]}' for p in parts)
installer = ROOT / 'dist' / 'KnoxNavigatorSetup.exe'
checksums += '\n' + hashlib.sha256(installer.read_bytes()).hexdigest() + '  KnoxNavigatorSetup.exe\n'
(output / 'SHA256SUMS.txt').write_text(checksums, encoding='utf-8')
with archive.open('rb') as original:
    for part in parts:
        digest = hashlib.sha256()
        with (output / part['name']).open('rb') as split:
            while block := split.read(1024 * 1024):
                assert original.read(len(block)) == block, 'Split differs from original ZIP'
                digest.update(block)
        assert digest.hexdigest() == part['sha256']
    assert original.read(1) == b''
print('Release parts and checksums verified.', flush=True)
