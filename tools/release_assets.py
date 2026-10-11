#!/usr/bin/env python3
"""Build and zip a GitHub release's applications and write its body.

    release_assets.py build
    release_assets.py zips <output-directory>
    release_assets.py notes <version> [<changelog>]

Each application in the release has an app.json in its directory. The
app.json contains the zip's name, the build command and the file names of the
binaries.

- build runs each application's build command in the application's directory.
- zips writes one zip per platform to <output-directory>. It fails if a binary
  is missing or two in one zip have the same name. The binaries are at the top
  level of each zip.
- notes writes the release body to stdout. The body is <changelog>'s section
  for <version> and the applications in each zip. <changelog> is
  spec/CHANGELOG.md by default.

See RELEASE.md.
"""

import argparse
import os
import shlex
import subprocess
import sys
import zipfile

import apps

CHANGELOG = os.path.join(apps.ROOT, "spec", "CHANGELOG.md")


def die(message):
    sys.exit("release_assets.py: " + message)


def released():
    return {k: v for k, v in apps.load().items() if "zip" in v}


def platforms():
    """Maps each platform to its (app, path) pairs, in platform then app order.
    A path is relative to the root of the repository."""
    out = {}
    for app_id, app in released().items():
        for name in app["files"]:
            path = os.path.join(app["dir"], "build", name)
            out.setdefault(app["zip"], []).append((app_id, path))
    return dict(sorted(out.items()))


def build():
    for app_id, app in released().items():
        print("%s: %s" % (app_id, app["build"]), flush=True)
        try:
            done = subprocess.run(shlex.split(app["build"]),
                                  cwd=os.path.join(apps.ROOT, app["dir"]))
        except OSError as e:
            die("%s: %s" % (app_id, e))
        if done.returncode:
            die("%s: %s failed" % (app_id, app["build"]))


def build_zips(outdir):
    os.makedirs(outdir, exist_ok=True)
    for platform, members in platforms().items():
        seen = {}
        for _, path in members:
            name = os.path.basename(path)
            if not os.path.isfile(os.path.join(apps.ROOT, path)):
                die("%s is listed for %s and was not built" % (path, platform))
            if name in seen:
                die("%s and %s would both be %s in %s.zip"
                    % (seen[name], path, name, platform))
            seen[name] = path
        archive = os.path.join(outdir, platform + ".zip")
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
            for name in sorted(seen):
                z.write(os.path.join(apps.ROOT, seen[name]), name)
        print("%s: %s" % (archive, ", ".join(sorted(seen))))


def section(text, version):
    """The body of the changelog's section for a version, without its heading."""
    wanted = version.lstrip("v")
    body = []
    found = False
    for line in text.splitlines():
        if line.startswith("## "):
            if found:
                break
            heading = line[3:].split(" - ")[0].strip()
            found = heading.lstrip("v") == wanted
            continue
        if found:
            body.append(line)
    if not found:
        return None
    return "\n".join(body).strip()


def notes(version, changelog):
    try:
        with open(changelog) as f:
            text = f.read()
    except OSError as e:
        die(str(e))
    changes = section(text, version)
    if changes is None:
        die("%s has no section for %s" % (changelog, version))
    out = ["## Specification %s" % version, "", changes, "",
           "The specification is the attached `rbcp.md`.", "",
           "## Applications", ""]
    for platform, members in platforms().items():
        ids = sorted({app for app, _ in members})
        out.append("- `%s.zip` — %s" % (platform, ", ".join(ids)))
    print("\n".join(out))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("build", help="build every application in the release")
    z = sub.add_parser("zips", help="write one zip per platform")
    z.add_argument("outdir")
    n = sub.add_parser("notes", help="write the release body to stdout")
    n.add_argument("version")
    n.add_argument("changelog", nargs="?", default=CHANGELOG)
    args = parser.parse_args()
    if args.command == "build":
        build()
    elif args.command == "zips":
        build_zips(args.outdir)
    else:
        notes(args.version, args.changelog)


if __name__ == "__main__":
    main()
