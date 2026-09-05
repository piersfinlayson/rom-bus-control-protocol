#!/usr/bin/env python3
"""Copy a built artefact into a one-rom-images checkout and update its manifest.

    publish.py <images-path> app <id> <version> <binary> [<binary> ...]

Every application carries its own version, whatever the delivery. A ROM image
the device serves goes to roms.json, a program the machine loads goes to
retro-apps.json, and the two manifests have the same shape.

The version is named on the command line. Publishing a version that is already
listed with different contents is refused, which is the mistake worth
catching: building a change and publishing it under the version it had before.

Builds nothing and downloads nothing. See RELEASE.md.
"""

import argparse
import hashlib
import json
import os
import shutil
import sys

REPO = "https://github.com/piersfinlayson/rom-bus-control-protocol/tree/main/"

# The ROM images are grouped under the plugin they need.
COLLECTION = "host-control"

# Everything published to images.onerom.org from here, which is not the same
# as everything this repository builds. Adding an application means adding an
# entry. `kind` says which manifest it belongs in: an image the device serves,
# or a program the machine loads.
APPS = {
    # Not built here. R107sl's bootloader, from the fork the published images
    # are built from.
    "c64-bootloader": {
        "kind": "rom",
        "name": "C64 Bootloader",
        "description": "A C64 kernal bootloader compatible with cartridges. "
                       "The c64c image is a combined 16KB kernal and basic "
                       "ROM.",
        "machine": "c64",
        "source": "https://github.com/piersfinlayson/c64-bootloader",
        "files": {
            "c64_bootloader.bin": {},
            "c64_bootloader_c64c.bin": {"variant": "c64c"},
        },
    },
    "c64-boot": {
        "kind": "rom",
        "name": "C64 RBCP Reference Bootloader",
        "description": "A C64 kernal bootloader reference implementation",
        "machine": "c64",
        "source": REPO + "reference/host/6502/c64-boot",
        "files": {"c64_boot.bin": {}},
    },
    "vic20-boot": {
        "kind": "rom",
        "name": "VIC-20 RBCP Reference Bootloader",
        "description": "A VIC-20 kernal bootloader reference implementation",
        "machine": "vic20",
        "source": REPO + "reference/host/6502/vic20-boot",
        "files": {
            "vic20_boot_pal.bin": {"variant": "pal"},
            "vic20_boot_ntsc.bin": {"variant": "ntsc"},
        },
    },
    "apple2-boot": {
        "kind": "rom",
        "name": "Apple II RBCP Reference Bootloader",
        "description": "An Apple II ROM bootloader reference implementation, "
                       "a 2KB F8 image for a II or II+ and an 8KB EF image "
                       "for a IIe",
        "machine": "apple2",
        "source": REPO + "reference/host/6502/apple2-boot",
        "files": {
            "apple2_boot_f8.bin": {"variant": "f8"},
            "apple2_boot_ef.bin": {"variant": "ef"},
        },
    },
    "romsel": {
        "kind": "retro",
        "name": "ROMSEL",
        "description": "Picks which image a One ROM serves from the BIOS "
                       "socket of an 8088 machine, and resets into it. "
                       "Runs from DOS.",
        "machine": "ibm-pc",
        "os": "dos",
        "source": REPO + "reference/host/x86/romsel",
        "files": {"romsel.exe": {}},
    },
}

# Where each kind lives. The manifest key differs because the two sections of
# the site mean different things to someone reading it.
KINDS = {
    "rom":   {"manifest": "roms.json",        "key": "roms"},
    "retro": {"manifest": "retro-apps.json",  "key": "apps"},
}


def die(msg):
    sys.exit("publish: " + msg)


def read_json(path):
    with open(path) as f:
        return json.load(f)


def write_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=4)
        f.write("\n")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            h.update(block)
    return h.hexdigest()


def check_images(path):
    for name in ("roms.json", "retro-apps.json", "index.html"):
        if not os.path.isfile(os.path.join(path, name)):
            die("%s does not look like a one-rom-images checkout, no %s"
                % (path, name))


def entries_of(manifest, kind):
    """The list of applications, whichever manifest this is."""
    key = KINDS[kind]["key"]
    if kind == "rom":
        for collection in manifest.get("collections", []):
            if collection.get("id") == COLLECTION:
                return collection.setdefault(key, [])
        die("roms.json has no %s collection" % COLLECTION)
    return manifest.setdefault(key, [])


def version_key(version):
    """Sorts vX.Y.Z newest first. Anything else sorts after them."""
    parts = version.lstrip("v").split(".")
    try:
        return (0, tuple(-int(n) for n in parts))
    except ValueError:
        return (1, version)


def order(manifest, kind):
    """Newest version first, and applications in the order APPS lists them."""
    entries = entries_of(manifest, kind)
    for e in entries:
        e["versions"].sort(key=lambda v: version_key(v["version"]))
    ids = list(APPS)
    entries.sort(key=lambda e: ids.index(e["id"]) if e["id"] in ids else len(ids))


def find(entries, field, value):
    for e in entries:
        if e.get(field) == value:
            return e
    return None


def publish(images, app_id, version, binaries):
    if app_id not in APPS:
        die("no application called %s, add one to APPS in this script" % app_id)
    app = APPS[app_id]

    files = []
    for binary in binaries:
        if not os.path.isfile(binary):
            die("no such file: %s" % binary)
        name = os.path.basename(binary)
        if name not in app["files"]:
            die("%s does not publish %s, it publishes %s"
                % (app_id, name, ", ".join(sorted(app["files"]))))
        entry = {"file": name}
        entry.update(app["files"][name])
        entry["sha256"] = sha256(binary)
        files.append((binary, entry))

    kind = app["kind"]
    root = "roms/" + COLLECTION if kind == "rom" else "retro-apps"
    manifest_path = os.path.join(images, KINDS[kind]["manifest"])
    manifest = read_json(manifest_path)
    entries = entries_of(manifest, kind)

    published = [e for _, e in files]
    entry = find(entries, "id", app_id)

    # The mistake worth catching. A version already listed described different
    # bytes, which means a change was built and is about to go out under the
    # number it had before.
    if entry:
        was = find(entry.get("versions", []), "version", version)
        if was:
            before = {f["file"]: f["sha256"] for f in was.get("files", [])}
            for f in published:
                old = before.get(f["file"])
                if old and old != f["sha256"]:
                    die("%s %s is already published, and %s differs from it.\n"
                        "         published %s\n"
                        "         this file %s\n"
                        "         Raise the version, or publish what is "
                        "already there."
                        % (app_id, version, f["file"], old, f["sha256"]))

    dest = os.path.join(images, root, app_id, version)
    os.makedirs(dest, exist_ok=True)
    for binary, f in files:
        shutil.copyfile(binary, os.path.join(dest, f["file"]))
    print("%s/%s/%s: %s" % (root, app_id, version,
                            ", ".join(f["file"] for f in published)))

    if not entry:
        entry = {"id": app_id}
        for field in ("name", "description", "machine", "os", "source"):
            if field in app:
                entry[field] = app[field]
        entry["latest"] = version
        entry["versions"] = []
        entries.append(entry)

    was = find(entry["versions"], "version", version)
    if was:
        entry["versions"][entry["versions"].index(was)] = \
            {"version": version, "files": published}
    else:
        entry["versions"].append({"version": version, "files": published})

    # Publishing an older version does not move latest backwards.
    entry["latest"] = min((v["version"] for v in entry["versions"]),
                          key=version_key)

    # The latest alias is a copy, because GitHub Pages cannot redirect a
    # binary and will not follow a symlink. It is rewritten from whichever
    # version is now latest, which is not always the one just published.
    latest = find(entry["versions"], "version", entry["latest"])
    alias = os.path.join(images, root, app_id, "latest")
    source = os.path.join(images, root, app_id, entry["latest"])
    if os.path.isdir(alias):
        shutil.rmtree(alias)
    os.makedirs(alias)
    for f in latest["files"]:
        shutil.copyfile(os.path.join(source, f["file"]),
                        os.path.join(alias, f["file"]))
    print("%s/%s/latest: %s from %s"
          % (root, app_id, ", ".join(f["file"] for f in latest["files"]),
             entry["latest"]))

    order(manifest, kind)
    write_json(manifest_path, manifest)
    print("%s: %s %s" % (KINDS[kind]["manifest"], app_id, version))


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("images", help="path to a one-rom-images checkout")
    sub = p.add_subparsers(dest="command", required=True)

    app = sub.add_parser("app", help="publish one application's built files")
    app.add_argument("id", help="application id, for example romsel")
    app.add_argument("version", help="its own version, for example v0.1.0")
    app.add_argument("binary", nargs="+", help="the built files")

    args = p.parse_args()
    check_images(args.images)
    publish(args.images, args.id, args.version, args.binary)


if __name__ == "__main__":
    main()
