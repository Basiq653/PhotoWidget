#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Собирает rootless .deb (Dopamine, /var/jb) из готового PhotoWidget.app.

Использование:
    python3 scripts/make_deb.py <путь/к/PhotoWidget.app> <выходной.deb>

Скрипт не требует dpkg/fakeroot — ar-архив и tar.gz пишутся напрямую,
поэтому одинаково работает на macOS-раннере GitHub Actions и на Linux.
"""

import gzip
import io
import os
import stat
import sys
import tarfile
import time

PACKAGE = "com.photowidget"
NAME = "Photo Widget"
VERSION = "1.0.0"
ARCH = "iphoneos-arm64"          # rootless (Dopamine, /var/jb)
SECTION = "Tweaks"
AUTHOR = "custom build"
MAINTAINER = "custom build"
APP_NAME = "PhotoWidget.app"
INSTALL_DIR = "var/jb/Applications"   # куда ставится бандл (от корня устройства)

POSTINST = r"""#!/bin/sh
JBROOT=/var/jb
APP="$JBROOT/Applications/PhotoWidget.app"

# приложение должно уметь обновлять копию фото внутри своего бандла
chown -R mobile:mobile "$APP" 2>/dev/null || true
chmod -R a+rX "$APP" 2>/dev/null || true

if [ -x "$JBROOT/usr/bin/uicache" ]; then
    "$JBROOT/usr/bin/uicache" -a >/dev/null 2>&1 || true
fi

exit 0
"""


# --------------------------------------------------------------------------- #
#  tar / ar helpers
# --------------------------------------------------------------------------- #

def _tarinfo(name, mode, size=0, kind=tarfile.REGTYPE, linkname=""):
    info = tarfile.TarInfo(name)
    info.mode = mode
    info.uid = 0
    info.gid = 0
    info.uname = "root"
    info.gname = "wheel"
    info.mtime = int(time.time())
    info.type = kind
    info.size = size
    info.linkname = linkname
    return info


def _tar_gz(build):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.GNU_FORMAT) as tar:
        build(tar)
    return gzip.compress(buf.getvalue(), 9)


def control_tar_gz(installed_kb):
    control = (
        f"Package: {PACKAGE}\n"
        f"Name: {NAME}\n"
        f"Version: {VERSION}\n"
        f"Architecture: {ARCH}\n"
        f"Author: {AUTHOR}\n"
        f"Maintainer: {MAINTAINER}\n"
        f"Section: {SECTION}\n"
        f"Installed-Size: {installed_kb}\n"
        "Description: Home screen widget that shows any photo from the gallery\n"
        " Adds a WidgetKit widget (small / medium / large) that displays a photo\n"
        " picked from the Photos library in the companion app.\n"
    ).encode()

    def build(tar):
        tar.addfile(_tarinfo("./control", 0o644, len(control)), io.BytesIO(control))
        script = POSTINST.encode()
        tar.addfile(_tarinfo("./postinst", 0o755, len(script)), io.BytesIO(script))

    return _tar_gz(build)


def _is_bundle_executable(path):
    """Mach-O внутри .app/.appex всегда должен быть 0755, иначе не запустится."""
    name = os.path.basename(path)
    parent = os.path.basename(os.path.dirname(path))
    for ext in (".app", ".appex"):
        if parent.endswith(ext) and name == parent[:-len(ext)]:
            return True
    return False


def data_tar_gz(app_path):
    app_path = os.path.abspath(app_path).rstrip(os.sep)
    app_base = os.path.basename(app_path)

    def build(tar):
        for parent in ("./", "./var/", "./var/jb/", "./var/jb/Applications/"):
            tar.addfile(_tarinfo(parent, 0o755, kind=tarfile.DIRTYPE))

        arcs = []
        for root, dirs, files in os.walk(app_path):
            dirs.sort()
            rel_root = os.path.relpath(root, os.path.dirname(app_path)).replace(os.sep, "/")
            for d in sorted(dirs):
                arcs.append((f"./{INSTALL_DIR}/{rel_root}/{d}", os.path.join(root, d), True))
            for f in sorted(files):
                arcs.append((f"./{INSTALL_DIR}/{rel_root}/{f}", os.path.join(root, f), False))

        arcs.sort(key=lambda x: x[0])

        for arcname, path, is_dir in arcs:
            if is_dir:
                tar.addfile(_tarinfo(arcname + "/", 0o755, kind=tarfile.DIRTYPE))
                continue

            if os.path.islink(path):
                target = os.readlink(path)
                tar.addfile(_tarinfo(arcname, 0o777, kind=tarfile.SYMTYPE, linkname=target))
                continue

            st = os.stat(path)
            mode = 0o755 if (st.st_mode & stat.S_IXUSR) or _is_bundle_executable(path) else 0o644
            with open(path, "rb") as fh:
                blob = fh.read()
            tar.addfile(_tarinfo(arcname, mode, len(blob)), io.BytesIO(blob))

    return _tar_gz(build)


def ar_archive(members):
    """members: список (name, bytes) в нужном порядке."""
    out = bytearray(b"!<arch>\n")
    for name, blob in members:
        header = (
            name.ljust(16)
            + str(int(time.time())).ljust(12)
            + "0".ljust(6)          # uid
            + "0".ljust(6)          # gid
            + "100644".ljust(8)     # mode
            + str(len(blob)).ljust(10)
            + "`\n"
        ).encode()
        out += header + blob
        if len(blob) % 2:
            out += b"\n"
    return bytes(out)


# --------------------------------------------------------------------------- #
#  main
# --------------------------------------------------------------------------- #

def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 2

    app_path, out_path = argv[1], argv[2]
    if not os.path.isdir(app_path):
        print(f"error: {app_path} не найден (сначала собери проект)")
        return 1

    total = 0
    for root, _dirs, files in os.walk(app_path):
        for f in files:
            fp = os.path.join(root, f)
            if not os.path.islink(fp):
                total += os.path.getsize(fp)
    installed_kb = max(1, total // 1024)

    deb = ar_archive([
        ("debian-binary", b"2.0\n"),
        ("control.tar.gz", control_tar_gz(installed_kb)),
        ("data.tar.gz", data_tar_gz(app_path)),
    ])

    os.makedirs(os.path.dirname(os.path.abspath(out_path)) or ".", exist_ok=True)
    with open(out_path, "wb") as fh:
        fh.write(deb)

    print(f"ok: {out_path} ({len(deb) / 1024:.0f} KB, payload {installed_kb} KB)")
    print(f"    bundle -> /{INSTALL_DIR}/{os.path.basename(app_path)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
