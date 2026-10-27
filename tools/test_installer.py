"""Exercise the compiled Windows installer against disposable tiny packages."""
from pathlib import Path
import json, subprocess, tempfile, zipfile

ROOT = Path(__file__).resolve().parents[1]
exe = ROOT / 'dist' / 'KnoxNavigatorSetup.exe'
with tempfile.TemporaryDirectory(prefix='knox-setup-test-') as temp:
    temp = Path(temp)
    payload = temp / 'source' / 'KnoxNavigator'
    (payload / '42').mkdir(parents=True)
    (payload / '42' / 'mod.info').write_text('id=KnoxNavigator\nversion=one\n')
    (payload / 'common').mkdir()
    (payload / 'common' / 'example.txt').write_text('first')
    mods = temp / 'Профиль игрока' / 'Zomboid' / 'mods'
    def run(mode, source, success=True):
        result = subprocess.run([str(exe), mode, str(source), str(mods)])
        assert (result.returncode == 0) == success, mods.with_suffix('.error.txt')
    run('--install-local', payload)
    assert (mods / 'KnoxNavigator' / 'common' / 'example.txt').read_text() == 'first'
    (payload / 'common' / 'example.txt').write_text('updated')
    archive = temp / 'update.zip'
    with zipfile.ZipFile(archive, 'w') as bundle:
        for file in payload.rglob('*'):
            if file.is_file(): bundle.write(file, file.relative_to(payload.parent))
    run('--install-zip', archive)
    assert (mods / 'KnoxNavigator' / 'common' / 'example.txt').read_text() == 'updated'
    backups = list(mods.glob('.KnoxNavigator-backup-*'))
    assert len(backups) == 1 and (backups[0] / 'common' / 'example.txt').read_text() == 'first'
    bad = temp / 'bad.zip'
    with zipfile.ZipFile(bad, 'w') as bundle: bundle.writestr('../escaped.txt', 'bad')
    run('--install-zip', bad, False)
    assert (mods / 'KnoxNavigator' / 'common' / 'example.txt').read_text() == 'updated'
    invalid = temp / 'invalid'; invalid.mkdir()
    run('--install-local', invalid, False)
    assert not list(mods.glob('.KnoxNavigator-install-*'))
print('Installer: first install, ZIP update, Cyrillic paths, backup, invalid payload and ZIP traversal checks pass.')
