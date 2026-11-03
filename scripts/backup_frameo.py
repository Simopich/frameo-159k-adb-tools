#!/usr/bin/env python3
"""Create and verify a private, local pre-flash backup of the documented Frameo 159K.

Run with the companion backup-device.sh. Device collections contain private data
and vendor firmware; never commit or publish the output directory.
"""
from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import json
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import time
import uuid
import zipfile
from datetime import datetime, timezone
from pathlib import Path


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def write_json(path: Path, data: object) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", required=True, type=Path)
    parser.add_argument("--target", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--keep-device-staging", action="store_true")
    parser.add_argument("--exclude-photos", action="store_true",
                        help="Omit known personal photo/video, thumbnail and Frameo image-cache directories")
    parser.add_argument("--resume", action="store_true",
                        help="Resume transferring/verifying an already completed device collection")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9.:-]+", args.target):
        parser.error("Invalid ADB target")
    adb = args.adb.resolve(strict=True)
    helper = Path(__file__).with_name("backup-device.sh").resolve(strict=True)
    output = args.output.resolve()
    if output.exists() and not args.resume:
        parser.error("Output already exists; previous backups are never overwritten")
    output.parent.mkdir(parents=True, exist_ok=True)
    if shutil.disk_usage(output.parent).free < 12 * 1024**3:
        parser.error("At least 12 GiB of free local space is required")
    if args.resume:
        if not (output / 'backup-status.json').is_file():
            parser.error('Resume requires a backup-status.json from this tool')
        previous = json.loads((output / 'backup-status.json').read_text(encoding='utf-8'))
        if previous.get('schema') != 'frameo-private-backup/v1' or previous.get('complete') or previous.get('target') != args.target:
            parser.error('Resume state does not match this incomplete backup')
        if previous.get('personal_photos_excluded') != args.exclude_photos:
            parser.error('Resume must preserve the original photo policy')
    else:
        output.mkdir(parents=True)
    (output / ".gitignore").write_text("*\n", encoding="ascii")
    log = (output / "operation.log").open("a", encoding="utf-8")
    tag = "frameo-backup-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    remote_stage = "/data/local/tmp/" + tag
    remote_helper = "/data/local/tmp/" + tag + "-helper.sh"
    state: dict = {
        "schema": "frameo-private-backup/v1", "target": args.target,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "remote_stage": remote_stage, "complete": False,
        "personal_photos_excluded": args.exclude_photos,
    }
    if args.resume:
        state = previous
        remote_stage = state['remote_stage']
        if not re.fullmatch(r'/data/local/tmp/frameo-backup-[A-Za-z0-9_-]+', remote_stage):
            parser.error('Invalid resume staging path')
        tag = remote_stage.rsplit('/', 1)[1]
        remote_helper = remote_stage + '-helper.sh'
    write_json(output / "backup-status.json", state)

    def run(arguments: list[str], *, check: bool = True, timeout: int = 60) -> subprocess.CompletedProcess:
        completed = subprocess.run([str(adb), *arguments], capture_output=True, text=True,
                                   encoding="utf-8", errors="replace", timeout=timeout)
        log.write("COMMAND " + repr(arguments) + "\n" + completed.stdout + completed.stderr + "\n")
        log.flush()
        if check and completed.returncode:
            raise RuntimeError("ADB command failed; inspect operation.log")
        return completed

    def shell(command: str, *, root: bool = False) -> str:
        remote = "su -c " + shlex.quote(command) if root else command
        return run(["-s", args.target, "shell", remote]).stdout.strip()

    try:
        run(["connect", args.target])
        if shell("getprop ro.product.model") != "159K":
            raise RuntimeError("Wrong device model")
        if shell("getprop ro.build.display.id") != "RK3326_8.1_AY_FRAMEO_202511241509":
            raise RuntimeError("Unverified firmware build")
        if shell("id -u", root=True) != "0":
            raise RuntimeError("Root is required for a complete application-data backup")
        if shell("getprop ro.adb.secure") != "1":
            raise RuntimeError("Expected authenticated ADB")
        activity = shell("dumpsys activity activities | grep mResumedActivity")
        match = re.search(r"\bu\d+ (net\.frameo\.frame/[A-Za-z0-9_.$]+)", activity)
        if not match:
            raise RuntimeError("Open Frameo before backup so its active screen can be restored")
        restore_activity = match.group(1)
        state.setdefault("frameo_activity_before", restore_activity)
        state.setdefault("boot_id_before", shell("cat /proc/sys/kernel/random/boot_id"))
        write_json(output / "backup-status.json", state)
        if args.resume:
            if shell('cat ' + shlex.quote(remote_stage + '/OWNER_MARKER'), root=True) != tag:
                raise RuntimeError('Resume ownership marker differs')
            shell('test -f ' + shlex.quote(remote_stage + '/COLLECTION_COMPLETE'), root=True)
            staged = shlex.quote(remote_stage)
            shell('chgrp -R 2000 ' + staged + ' && find ' + staged +
                  ' -type d -exec chmod 750 {} \\; && find ' + staged +
                  ' -type f -exec chmod 640 {} \\;', root=True)
            print('Resuming a completed device collection; no app data is recollected.', flush=True)
        else:
            run(["-s", args.target, "push", str(helper), remote_helper])
            command = "sh " + shlex.quote(remote_helper) + " " + shlex.quote(remote_stage) + " " + shlex.quote(restore_activity)
            command += " exclude" if args.exclude_photos else " include"
            print("Collecting on the frame; only the temporary staging directory is written.", flush=True)
            process = subprocess.Popen([str(adb), "-s", args.target, "shell", "su -c " + shlex.quote(command)],
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                       encoding="utf-8", errors="replace", bufsize=1)
            assert process.stdout is not None
            for line in process.stdout:
                log.write(line)
                log.flush()
                print(line.rstrip(), flush=True)
            if process.wait() != 0:
                raise RuntimeError("Device collection failed; staging retained for inspection")

        print("Transferring the private backup to the PC.", flush=True)
        transfer = output / "transfer"
        transfer.mkdir(exist_ok=args.resume)
        for attempt in range(3):
            result = run(["-s", args.target, "pull", remote_stage, str(transfer)], check=False, timeout=3600)
            if result.returncode == 0:
                break
            if attempt == 2:
                raise RuntimeError("Transfer failed after retries; device staging retained")
            run(["connect", args.target], check=False)
            time.sleep(2)
        downloaded = transfer / tag
        if not downloaded.is_dir() or not (downloaded / "COLLECTION_COMPLETE").is_file():
            raise RuntimeError("Unexpected transfer layout or missing collection marker")
        payload = output / "payload"
        downloaded.rename(payload)
        transfer.rmdir()

        print("Comparing every file against the device-side SHA256 manifest.", flush=True)
        inventory: list[dict] = []
        for line in (payload / "SHA256SUMS").read_text(encoding="utf-8").splitlines():
            match = re.fullmatch(r"([a-fA-F0-9]{64})\s{2}(\./.+)", line)
            if not match:
                raise RuntimeError("Invalid checksum manifest entry")
            expected, relative = match.groups()
            path = (payload / relative).resolve()
            if not path.is_relative_to(payload) or not path.is_file():
                raise RuntimeError("Manifest path escapes the backup or is missing")
            actual = digest(path)
            if actual.lower() != expected.lower():
                raise RuntimeError("Transferred file checksum mismatch: " + relative)
            inventory.append({"path": path.relative_to(output).as_posix(), "bytes": path.stat().st_size,
                              "sha256": actual})

        print("Checking all APK ZIPs, compressed partition images, and data archives.", flush=True)
        apks = sorted((payload / "apks").rglob("*.apk"))
        for apk in apks:
            with zipfile.ZipFile(apk) as archive:
                bad = archive.testzip()
                if bad or "AndroidManifest.xml" not in archive.namelist():
                    raise RuntimeError("APK verification failed: " + str(apk.relative_to(output)))
        with (payload / "metadata/raw-partition-hashes.tsv").open(encoding="utf-8", newline="") as stream:
            partition_records = list(csv.DictReader(stream, delimiter="\t"))
        verified_partitions = []
        for partition in partition_records:
            name = partition["partition"]
            if not re.fullmatch(r"[A-Za-z0-9_-]+", name):
                raise RuntimeError("Invalid partition name")
            image = payload / "partitions" / (name + ".img.gz")
            raw_hash = hashlib.sha256()
            raw_bytes = 0
            with gzip.open(image, "rb") as stream:
                for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
                    raw_hash.update(chunk)
                    raw_bytes += len(chunk)
            if raw_bytes != int(partition["raw_bytes"]) or raw_hash.hexdigest() != partition["raw_sha256"]:
                raise RuntimeError("Decompressed partition verification failed: " + name)
            verified_partitions.append({"name": name, "raw_bytes": raw_bytes, "sha256": raw_hash.hexdigest()})

        archive_results: dict[str, dict] = {}
        for name in ("userdata.tar.gz", "customizations.tar.gz", "root-files.tar.gz"):
            archive_path = payload / name
            with gzip.open(archive_path, "rb") as stream:
                for _ in iter(lambda: stream.read(4 * 1024 * 1024), b""):
                    pass  # Read through the gzip footer to validate its checksum.
            counts = {"members": 0, "regular_files": 0, "regular_bytes": 0,
                      "frameo_private_files": 0, "shared_media_files": 0, "vendor_frameo_files": 0,
                      "personal_photo_files": 0}
            names: list[str] = []
            with tarfile.open(archive_path, "r:gz") as archive:
                for member in archive:
                    counts["members"] += 1
                    names.append(member.name)
                    if member.isfile():
                        counts["regular_files"] += 1
                        counts["regular_bytes"] += member.size
                        normalized = member.name.removeprefix("./")
                        if normalized.startswith("data/net.frameo.frame/"):
                            counts["frameo_private_files"] += 1
                        if normalized.startswith("media/"):
                            counts["shared_media_files"] += 1
                        if normalized.startswith("vendor/frameo/"):
                            counts["vendor_frameo_files"] += 1
                        if normalized.startswith(("media/0/frameo_files/media/", "media/0/frameo_files/profilePictures/",
                                                  "media/0/frameo_files/videoThumbnails/", "media/0/frameo_files/cache/",
                                                  "media/0/Pictures/", "media/0/DCIM/", "media/0/Movies/",
                                                  "data/net.frameo.frame/cache/")):
                            counts["personal_photo_files"] += 1
            (output / (name + ".contents.txt")).write_text("\n".join(names) + "\n", encoding="utf-8")
            archive_results[name] = counts
        if not apks or not any("net.frameo.frame" in str(path) for path in apks):
            raise RuntimeError("No Frameo APK was backed up")
        if archive_results["userdata.tar.gz"]["frameo_private_files"] == 0:
            raise RuntimeError("Frameo private data missing from the archive")
        if args.exclude_photos and archive_results["userdata.tar.gz"]["personal_photo_files"]:
            raise RuntimeError("Excluded personal-photo paths are still present")

        state.pop('error', None)
        state.update({"complete": True, "completed_utc": datetime.now(timezone.utc).isoformat(),
                      "apk_count": len(apks), "verified_files": len(inventory),
                      "payload_bytes": sum(item["bytes"] for item in inventory),
                      "partitions": verified_partitions, "archives": archive_results,
                      "boot_id_after": shell("cat /proc/sys/kernel/random/boot_id"),
                      "root_after": shell("id", root=True),
                      "adb_secure_after": shell("getprop ro.adb.secure"),
                      "persistent_tcp_after": shell("getprop persist.adb.tcp.port"),
                      "native_adb_after": shell("getprop persist.internet.adb.enable")})
        write_json(output / "file-manifest.json", inventory)
        write_json(output / "backup-status.json", state)
        (output / "RESTORE-NOTES.md").write_text(
            "# Private Frameo 159K pre-flash backup\n\n"
            "All payload files were compared with device-side SHA256 checksums. APK ZIP CRCs, gzip trailers, "
            "tar listings, and decompressed partition lengths and hashes were verified.\n\n"
            "- `payload/apks/`: every APK found under system, vendor, OEM and installed-app paths, preserving original paths.\n"
            "- `payload/userdata.tar.gz`: data-root files, including app code/private data, selected shared-storage files, system settings, Wi-Fi and ADB configuration. "
            "Rebuildable caches, diagnostic logs, volatile IPC sockets/FIFOs, and the temporary backup directory were excluded; exact exclusions are recorded.\n"
            "- `payload/customizations.tar.gz`: available Frameo vendor files, overlays, OEM files, metadata and system configuration.\n"
            "- `payload/root-files.tar.gz`: init, fstab and related root filesystem configuration.\n"
            "- `payload/partitions/`: compressed raw images of named recovery/firmware partitions. Userdata and cache are not raw-imaged.\n"
            "- `payload/metadata/`: package/UID/permission inventory, settings exports, partition layout and source hashes.\n\n"
            "## Restore limits\n\n"
            "This is a preservation backup, not a universal automatic restore or a complete flashable disk image. "
            "The live filesystem snapshot is not an atomic whole-device snapshot. Frameo was stopped while userdata was captured and its screen was reopened. "
            "APK reinstall can be done with `adb install -r` on a compatible OS; some OEM packages need privileged placement, platform signatures or native libraries. "
            "On another OS, install apps first and restore their data selectively with the new UIDs and appropriate SELinux labels. "
            "Do not blindly extract the full data archive or overwrite Android system settings on a different OS. "
            "Hardware-backed credentials, cloud sessions, DRM and vendor licensing may require the original hardware/firmware or new authentication. "
            "Raw partition images are only for an identity/layout-checked restoration to this unit, not another frame. "
            "No flashing or restore was performed. No physical external SD card was mounted in the observed storage inventory.\n\n"
            "## Privacy\n\nThis directory is local and unencrypted. It can contain photographs, Wi-Fi credentials, app tokens, "
            "licenses and device identity files. Keep it private and do not upload it to the public source repository.\n",
            encoding="utf-8")
        with (output / "RESTORE-NOTES.md").open("a", encoding="utf-8") as notes:
            notes.write("\n## Personal media policy\n\n")
            notes.write("Personal photos/videos, thumbnails and Frameo image caches in the recorded paths were excluded at the owner's request. "
                        "Settings, licenses and databases were retained; database records may still reference the omitted media.\n"
                        if args.exclude_photos else "Personal media was included where present in the data archive.\n")
        if not args.keep_device_staging:
            marker = shell("cat " + shlex.quote(remote_stage + "/OWNER_MARKER"), root=True)
            if marker != tag or not re.fullmatch(r"/data/local/tmp/frameo-backup-[A-Za-z0-9_-]+", remote_stage):
                raise RuntimeError("Refusing cleanup of an unexpected device directory")
            cleanup = "rm -rf -- " + shlex.quote(remote_stage) + " && rm -f -- " + shlex.quote(remote_helper)
            shell(cleanup, root=True)
            state["device_staging_removed"] = True
            write_json(output / "backup-status.json", state)
        print(json.dumps({"complete": True, "output": str(output), "apks": len(apks),
                          "verified_files": len(inventory), "payload_bytes": state["payload_bytes"],
                          "partitions": len(verified_partitions), "archives": archive_results}, indent=2), flush=True)
        return 0
    except Exception as error:
        state["error"] = str(error)
        write_json(output / "backup-status.json", state)
        print("BACKUP NOT COMPLETE: " + str(error), file=sys.stderr, flush=True)
        print("Previous files and device staging were retained for inspection.", file=sys.stderr, flush=True)
        return 1
    finally:
        log.close()


if __name__ == "__main__":
    raise SystemExit(main())
