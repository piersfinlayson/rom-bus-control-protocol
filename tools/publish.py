#!/usr/bin/env python3
"""Publish an application's binary to one-rom-images.

    publish.py <images-path> app <id> [--version <v>] <binary> [<binary> ...]

Each application that can be published has an app.json in its directory. It
contains the file names of the application's binaries.

- <images-path> is the path to a one-rom-images checkout.
- <id> is the application's directory name, for example c64-boot.
- <binary> is the path to one of its binaries, for example
  reference/host/6502/c64-boot/build/c64_boot.bin.
- --version is the version to publish, for example v0.1.1. Use it only when
  the application's source isn't in this repository. Otherwise the version is
  read from APP_VERSION or CFG_VERSION in the application's source.

Publishing fails if the version is already published with different contents.

See RELEASE.md.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import sys

import apps

REPO = "https://github.com/piersfinlayson/rom-bus-control-protocol/tree/main/"

# The ROM images are grouped under the plugin they need.
COLLECTION = "host-control"

# APP_VERSION or CFG_VERSION as ca65, vasm and C define it.
VERSION_FORMS = (
    r'^\s*\.define\s+(?:APP|CFG)_VERSION\s+"([^"]*)"',
    r'^(?:APP|CFG)_VERSION\s+MACRO\s*\n\s*DC\.B\s+"([^"]*)"',
    r'^\s*#define\s+(?:APP|CFG)_VERSION\s+"([^"]*)"',
)
SOURCE_SUFFIXES = (".s", ".h", ".c", ".inc")

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
    """Sorts each application's versions newest first."""
    for e in entries_of(manifest, kind):
        e["versions"].sort(key=lambda v: version_key(v["version"]))


def find(entries, field, value):
    for e in entries:
        if e.get(field) == value:
            return e
    return None


def source_version(app_id, app):
    """The version defined in the application's directory, as vX.Y.Z, or None
    when its source isn't in this repository."""
    if "source" in app:
        return None
    top = os.path.join(apps.ROOT, app["dir"])
    found = []
    for d, dirs, files in os.walk(top):
        dirs[:] = [x for x in dirs if x != "build"]
        for name in files:
            if not name.endswith(SOURCE_SUFFIXES):
                continue
            path = os.path.join(d, name)
            with open(path, errors="replace") as f:
                text = f.read()
            for form in VERSION_FORMS:
                for m in re.finditer(form, text, re.M):
                    found.append((os.path.relpath(path, apps.ROOT), m.group(1)))
    if len(found) != 1:
        die("%s: %d version definitions in %s, not one: %s"
            % (app_id, len(found), os.path.relpath(top, apps.ROOT),
               ", ".join(p for p, _ in found)))
    return "v" + found[0][1]


def publish(images, app_id, version, binaries):
    app = apps.load().get(app_id)
    if not app:
        die("there isn't an app.json in a directory called %s" % app_id)
    if app["kind"] not in KINDS:
        die("%s: kind %s isn't one of %s"
            % (app_id, app["kind"], ", ".join(KINDS)))

    from_source = source_version(app_id, app)
    if from_source and version:
        die("%s: the version is read from its source. Leave out --version."
            % app_id)
    if not from_source and not version:
        die("%s: its source isn't in this repository, so --version is required"
            % app_id)
    version = version or from_source

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
        entries.append(entry)

    # Copied at every publish so a change to app.json reaches roms.json or
    # retro-apps.json.
    fields = dict(app, source=app.get("source", REPO + app["dir"]))
    for field in ("name", "description", "machine", "os", "source"):
        if field in fields:
            entry[field] = fields[field]
        else:
            entry.pop(field, None)
    entry.setdefault("latest", version)
    entry.setdefault("versions", [])

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
    app.add_argument("--version", help="the version, for example v0.1.0, of "
                     "an application whose source isn't in this repository")
    app.add_argument("binary", nargs="+", help="the built files")

    args = p.parse_args()
    check_images(args.images)
    publish(args.images, args.id, args.version, args.binary)


if __name__ == "__main__":
    main()
