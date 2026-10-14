"""Stage the KF2VR Steam Workshop item (3817663661) from an extracted release.

    python tools/workshop/stage_workshop.py --release <folder> --changenote "<text>"

<folder> holds app/, READ ME FIRST.txt and Start KF2-VR.cmd (an extracted
KF2VR-Multiplayer ZIP or a live install). The release is checked against its
app/release.json, then laid out the way the item ships:

    Upload/Play.cmd, Setup KF2VR.cmd, KF2VR-Setup.ps1
    Upload/BrewedPC/Script/KF2VR.u, KF2VRNet.u, KF2VRNetClient.u
    Upload/BrewedPC/Packages/KF2VRHands.upk
    Upload/KF2VR/app (without those four), play.py, READ ME FIRST.txt, Start KF2-VR.cmd

KF2 loads an item's BrewedPC for every Steam player (desktop joins), and
play.py copies the four packages from there into the launcher's app/Packages.
The staging folder also gets workshop_item.vdf (absolute paths, this change
note) and upload.cmd, which runs SteamCMD with it.
"""
import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ITEM = HERE / "item"
REPO = HERE.parents[1]
SCRIPT_PACKAGES = ["KF2VR.u", "KF2VRNet.u", "KF2VRNetClient.u"]
ART_PACKAGES = ["KF2VRHands.upk"]
# Per-user or generated files that a used install may hold; never shipped.
SKIP_DIRS = {"sessions", "logs", "__pycache__", "build", ".pytest_cache"}
SKIP_FILES = {"settings.json", "JOIN-SERVER.txt"}


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def verify_release(app):
    listed = json.loads((app / "release.json").read_text(encoding="utf-8-sig"))["files_sha256"]
    bad = [name for name, expected in listed.items()
           if not (app / name).is_file() or sha256(app / name) != expected.upper()]
    if bad:
        sys.exit("The release does not match its release.json: " + ", ".join(bad[:10]))
    for name in SCRIPT_PACKAGES + ART_PACKAGES:
        if "Packages/" + name not in listed:
            sys.exit("release.json does not list Packages/" + name)
    return len(listed)


def copy_app(source, target):
    for path in sorted(source.rglob("*")):
        relative = path.relative_to(source)
        if any(part in SKIP_DIRS for part in relative.parts[:-1]) or path.is_dir():
            continue
        if path.name in SKIP_FILES or path.suffix == ".pyc":
            continue
        if relative.parts[0] == "Packages" and path.name in SCRIPT_PACKAGES + ART_PACKAGES:
            continue
        (target / relative).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target / relative)


def vdf_text(text):
    # SteamCMD's KeyValues parser has no escapes: a quote or backslash breaks the file.
    if '"' in text or "\\" in text:
        sys.exit("The change note cannot contain double quotes or backslashes.")
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--release", required=True, type=Path)
    parser.add_argument("--changenote", required=True)
    parser.add_argument("--out", type=Path, default=REPO / "build" / "workshop-stage")
    args = parser.parse_args()
    release, out = args.release.resolve(), args.out.resolve()
    app = release / "app"
    count = verify_release(app)

    upload = out / "Upload"
    if upload.exists():
        shutil.rmtree(upload)  # Stale files would otherwise ship.
    copy_app(app, upload / "KF2VR" / "app")
    for folder, names in (("Script", SCRIPT_PACKAGES), ("Packages", ART_PACKAGES)):
        (upload / "BrewedPC" / folder).mkdir(parents=True, exist_ok=True)
        for name in names:
            shutil.copy2(app / "Packages" / name, upload / "BrewedPC" / folder / name)
    for name in ("READ ME FIRST.txt", "Start KF2-VR.cmd"):
        shutil.copy2(release / name, upload / "KF2VR" / name)
    shutil.copy2(ITEM / "play.py", upload / "KF2VR" / "play.py")
    shutil.copy2(ITEM / "Play.cmd", upload / "Play.cmd")
    shutil.copy2(HERE / "KF2VR-Setup.ps1", upload / "KF2VR-Setup.ps1")
    setup = ["@echo off",
             "rem Puts the Play in VR / Play normally choice on Killing Floor 2. Run again to remove it.",
             'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0KF2VR-Setup.ps1"']
    (upload / "Setup KF2VR.cmd").write_bytes(("\r\n".join(setup) + "\r\n").encode("ascii"))

    shutil.copy2(ITEM / "preview.jpg", out / "preview.jpg")
    vdf = (ITEM / "workshop_item.vdf").read_text(encoding="utf-8")
    vdf = (vdf.replace("__CONTENT__", upload.as_posix())
              .replace("__PREVIEW__", (out / "preview.jpg").as_posix())
              .replace("__CHANGENOTE__", vdf_text(args.changenote)))
    (out / "workshop_item.vdf").write_text(vdf, encoding="utf-8", newline="")
    cmd = ["@echo off",
           "rem Uploads the staged KF2VR item. SteamCMD asks for the password and Steam Guard code itself.",
           'if "%~1"=="" (echo Usage: upload.cmd ^<path to steamcmd.exe^> & exit /b 2)',
           "set /p STEAMUSER=Steam account name: ",
           '"%~1" +login %STEAMUSER% +workshop_build_item "%~dp0workshop_item.vdf" +quit']
    (out / "upload.cmd").write_bytes(("\r\n".join(cmd) + "\r\n").encode("ascii"))

    files = sum(1 for path in upload.rglob("*") if path.is_file())
    size = sum(path.stat().st_size for path in upload.rglob("*") if path.is_file())
    print(f"release verified ({count} files); staged {files} files, {size / 2**20:.0f} MB in {upload}")
    print("BrewedPC:")
    for path in sorted((upload / "BrewedPC").rglob("*.u*")):
        print(f"  {path.relative_to(upload).as_posix()}  {sha256(path)}")
    print(f"upload with: {out / 'upload.cmd'} <path to steamcmd.exe>")


if __name__ == "__main__":
    main()
