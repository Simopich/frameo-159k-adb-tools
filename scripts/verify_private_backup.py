"""Additional offline checks and an English inventory for an already verified private backup."""
import argparse
import csv
import hashlib
import json
import re
import shutil
import sqlite3
import subprocess
import tarfile
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path, PurePosixPath

parser = argparse.ArgumentParser()
parser.add_argument('--backup', required=True, type=Path)
parser.add_argument('--aapt2', required=True, type=Path)
parser.add_argument('--scratch', required=True, type=Path)
args = parser.parse_args()
backup = args.backup.resolve(strict=True)
status = json.loads((backup / 'backup-status.json').read_text())
assert status['complete'] and status['personal_photos_excluded']
payload = backup / 'payload'
scratch = args.scratch.resolve() / ('private-database-check-' + uuid.uuid4().hex)
scratch.mkdir(parents=True)

def sha(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()

apk_rows = []
for apk in sorted((payload / 'apks').rglob('*.apk')):
    result = subprocess.run([str(args.aapt2), 'dump', 'badging', str(apk)],
                            check=True, capture_output=True, text=True, encoding='utf-8', errors='replace')
    package = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']*)'", result.stdout)
    if not package:
        raise RuntimeError('Could not identify APK: ' + str(apk.relative_to(backup)))
    label = re.search(r"^application-label:'(.*)'$", result.stdout, re.MULTILINE)
    apk_rows.append({'Package': package[1], 'VersionCode': package[2], 'VersionName': package[3],
                     'Label': label[1] if label else '', 'Bytes': apk.stat().st_size,
                     'SHA256': sha(apk), 'BackupPath': apk.relative_to(backup).as_posix()})
with (backup / 'APK-INDEX.csv').open('w', encoding='utf-8-sig', newline='') as stream:
    writer = csv.DictWriter(stream, fieldnames=list(apk_rows[0]))
    writer.writeheader(); writer.writerows(apk_rows)

preferences = 0
realm_files = 0
with tarfile.open(payload / 'userdata.tar.gz', 'r:gz') as archive:
    for member in archive:
        if not member.isfile():
            continue
        name = member.name.removeprefix('./')
        if name.startswith('data/net.frameo.frame/shared_prefs/') and name.endswith('.xml'):
            ET.fromstring(archive.extractfile(member).read())
            preferences += 1
        if name.startswith('data/net.frameo.frame/files/') and name.endswith('.realm'):
            realm_files += 1
        prefix = 'data/net.frameo.frame/databases/'
        if name.startswith(prefix):
            relative = PurePosixPath(name[len(prefix):])
            if '..' in relative.parts or relative.is_absolute():
                raise RuntimeError('Unexpected database path')
            destination = scratch.joinpath(*relative.parts)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(archive.extractfile(member).read())

database_checks = []
for path in sorted(scratch.rglob('*')):
    if not path.is_file() or path.read_bytes()[:16] != b'SQLite format 3\0':
        continue
    connection = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)
    try:
        checks = [row[0] for row in connection.execute('PRAGMA quick_check')]
    finally:
        connection.close()
    database_checks.append({'Database': path.relative_to(scratch).as_posix(), 'Result': checks})
    if checks != ['ok']:
        raise RuntimeError('SQLite check failed: ' + str(path.name))

with tarfile.open(payload / 'customizations.tar.gz', 'r:gz') as archive:
    vendor_frameo_files = [m.name for m in archive if m.isfile() and m.name.startswith('vendor/frameo/')]
report = {'FrameoPreferencesXmlParsed': preferences, 'FrameoSqliteDatabases': database_checks,
          'FrameoRealmFilesPreserved': realm_files, 'RealmSemanticIntegrityChecked': False,
          'VendorFrameoFiles': vendor_frameo_files, 'APKsIndexed': len(apk_rows),
          'PersonalPhotoFilesInKnownExcludedPaths': status['archives']['userdata.tar.gz']['personal_photo_files']}
(backup / 'ADDITIONAL-VALIDATION.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
summary = '# Backup completed and verified\n\n'
summary += f"- APK files: **{len(apk_rows)}**, indexed in `APK-INDEX.csv`.\n"
summary += f"- Named recovery/firmware partition images: **{len(status['partitions'])}**.\n"
summary += f"- Payload size: **{status['payload_bytes'] / 1024**3:.2f} GiB**.\n"
summary += f"- Frameo private files: **{status['archives']['userdata.tar.gz']['frameo_private_files']}**.\n"
summary += f"- Frameo preference XML files parsed: **{preferences}**.\n"
summary += f"- Frameo SQLite databases checked: **{len(database_checks)}**.\n"
summary += '- Personal photos, videos, thumbnails and image caches in the documented paths: **excluded**.\n'
summary += '- Source/copy SHA256, APK CRCs, gzip integrity, tar listings, decompressed image sizes/hashes: **verified**.\n\n'
summary += 'See `RESTORE-NOTES.md` before restoring to another OS. App data, licenses and original images are private; keep this directory local. '
summary += 'This preserves files and configuration; compatibility with a different OS and hardware-backed credentials is not guaranteed. '
summary += 'Realm files are byte-preserved but were not validated with a Realm engine.\n'
(backup / 'BACKUP-SUMMARY.md').write_text(summary, encoding='utf-8')
if scratch.parent != args.scratch.resolve() or not scratch.name.startswith('private-database-check-') or scratch.is_symlink():
    raise RuntimeError('Unexpected scratch directory; cleanup refused')
shutil.rmtree(scratch)
print(json.dumps({'apks': len(apk_rows), 'preferences': preferences, 'sqlite_databases': len(database_checks),
                  'realm_files': realm_files, 'vendor_frameo_files': len(vendor_frameo_files)}, indent=2))
