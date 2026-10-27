from pathlib import Path
import zipfile, hashlib
ROOT=Path(__file__).resolve().parents[1]
source=ROOT/'KnoxNavigator'
installed=Path.home()/'Zomboid/mods/KnoxNavigator'
files=sorted(p for p in source.rglob('*') if p.is_file())
def sha256(path):
    digest=hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda:handle.read(1024*1024),b''):digest.update(chunk)
    return digest.digest()
for path in files:
    target=installed/path.relative_to(source)
    assert target.is_file() and sha256(target)==sha256(path),f'Installed copy differs: {target}'
archive=ROOT/'KnoxNavigator.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as zip:
    # PNG tiles are already compressed; storing them avoids minutes of redundant work.
    for path in files:
        zip.write(path,path.relative_to(ROOT),compress_type=zipfile.ZIP_STORED if path.suffix.lower()=='.png' else zipfile.ZIP_DEFLATED)
with zipfile.ZipFile(archive) as zip:
    assert zip.testzip() is None
    assert 'KnoxNavigator/42/mod.info' in zip.namelist()
    assert 'KnoxNavigator/common/README.txt' in zip.namelist()
print('Installed files verified:',len(files))
print('Archive validated:',archive,round(archive.stat().st_size/1024**2,1),'MiB')
