#!/usr/bin/env python3
"""Gathers a release into one zip of built artefacts per platform and writes
the release body.

    release_assets.py zips <output-directory>
    release_assets.py notes <version> [<changelog>]

Run from the root of the repository. RELEASE lists every file a release
carries, so adding an image means adding it there. A listed file that is
missing stops the run rather than shipping a zip an image short.

The body is the changelog's section for the version being released, followed
by the applications each zip holds. See RELEASE.md.
"""

import argparse
import os
import sys
import zipfile

# Platform, application, the directory the build writes to, and the files
# taken from it. A zip holds one platform's files in a flat layout under the
# names the build gave them.
RELEASE = [
    ("amiga", "amiga-boot", "reference/host/68k/amiga-boot/build", [
        "amiga_boot_256k.bin",
        "amiga_boot_512k.bin",
    ]),
    ("amiga", "amiga-rbcp-stress", "reference/host/68k/amiga-rbcp-stress/build", [
        "amiga_meter_256k.bin",
        "amiga_meter_512k.bin",
    ]),
    ("amiga", "amiga-pipe-test", "reference/host/68k/amiga-pipe-test/build", [
        "amiga_pipe_256k.bin",
        "amiga_pipe_512k.bin",
    ]),
    ("amiga", "amiga-rbcp-term", "reference/host/68k/amiga-rbcp-term/build", [
        "amiga_term_256k.bin",
        "amiga_term_512k.bin",
    ]),
    ("amiga", "amiga-aux-io", "reference/host/68k/amiga-aux-io/build", [
        "amiga_auxio_256k.bin",
        "amiga_auxio_512k.bin",
    ]),
    ("amiga", "amiga-led-test", "reference/host/68k/amiga-led-test/build", [
        "amiga_led_test_256k.bin",
        "amiga_led_test_512k.bin",
    ]),
    ("apple2", "apple2-boot", "reference/host/6502/apple2-boot/build", [
        "apple2_boot_f8.bin",
        "apple2_boot_ef.bin",
    ]),
    ("apple2", "apple2-rbcp-stress", "reference/host/6502/apple2-rbcp-stress/build", [
        "apple2_meter.bin",
    ]),
    ("apple2", "apple2-aux-io", "reference/host/6502/apple2-aux-io/build", [
        "apple2_auxio.bin",
    ]),
    ("apple2", "apple2-rbcp-term", "reference/host/6502/apple2-rbcp-term/build", [
        "apple2_term.bin",
    ]),
    ("apple2", "apple2-pipe-test", "reference/host/6502/apple2-pipe-test/build", [
        "apple2_pipe_pal.bin",
        "apple2_pipe_ntsc.bin",
    ]),
    ("c64", "c64-boot", "reference/host/6502/c64-boot/build", [
        "c64_boot.bin",
    ]),
    ("c64", "c64-rbcp-stress", "reference/host/6502/c64-rbcp-stress/build", [
        "c64_meter_kernal.bin",
        "c64_meter_basic.bin",
        "c64_meter_combined.bin",
    ]),
    ("c64", "c64-aux-io", "reference/host/6502/c64-aux-io/build", [
        "c64_auxio_kernal.bin",
        "c64_auxio_basic.bin",
        "c64_auxio_combined.bin",
    ]),
    ("c64", "c64-rbcp-term", "reference/host/6502/c64-rbcp-term/build", [
        "c64_term_kernal.bin",
        "c64_term_basic.bin",
        "c64_term_combined.bin",
    ]),
    ("c64", "c64-pipe-test", "reference/host/6502/c64-pipe-test/build", [
        "c64_pipe_kernal.bin",
        "c64_pipe_basic.bin",
        "c64_pipe_combined.bin",
    ]),
    ("c64", "c64-led-test", "reference/host/6502/c64-led-test/build", [
        "rbcp_led_test.prg",
        "rbcp-led-test.d64",
    ]),
    ("vic20", "vic20-boot", "reference/host/6502/vic20-boot/build", [
        "vic20_boot_pal.bin",
        "vic20_boot_ntsc.bin",
    ]),
    ("vic20", "vic20-rbcp-stress", "reference/host/6502/vic20-rbcp-stress/build", [
        "vic20_meter_pal.bin",
        "vic20_meter_ntsc.bin",
    ]),
    ("vic20", "vic20-aux-io", "reference/host/6502/vic20-aux-io/build", [
        "vic20_auxio_pal.bin",
        "vic20_auxio_ntsc.bin",
    ]),
    ("vic20", "vic20-rbcp-term", "reference/host/6502/vic20-rbcp-term/build", [
        "vic20_term_pal.bin",
        "vic20_term_ntsc.bin",
    ]),
    ("vic20", "vic20-pipe-test", "reference/host/6502/vic20-pipe-test/build", [
        "vic20_pipe_pal.bin",
        "vic20_pipe_ntsc.bin",
    ]),
    ("x86", "romsel", "reference/host/x86/romsel/build", [
        "romsel.exe",
    ]),
]

CHANGELOG = "spec/CHANGELOG.md"


def die(message):
    sys.exit("release_assets.py: " + message)


def platforms():
    """Maps each platform to its (app, path) pairs, in RELEASE's order."""
    out = {}
    for platform, app, directory, names in RELEASE:
        for name in names:
            out.setdefault(platform, []).append((app, os.path.join(directory, name)))
    return out


def build_zips(outdir):
    os.makedirs(outdir, exist_ok=True)
    for platform, members in platforms().items():
        seen = {}
        for _, path in members:
            name = os.path.basename(path)
            if not os.path.isfile(path):
                die("%s is listed for %s and was not built" % (path, platform))
            if name in seen:
                die("%s and %s would both be %s in %s.zip"
                    % (seen[name], path, name, platform))
            seen[name] = path
        archive = os.path.join(outdir, platform + ".zip")
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
            for name in sorted(seen):
                z.write(seen[name], name)
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
        apps = sorted({app for app, _ in members})
        out.append("- `%s.zip` — %s" % (platform, ", ".join(apps)))
    print("\n".join(out))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    z = sub.add_parser("zips", help="write one zip per platform")
    z.add_argument("outdir")
    n = sub.add_parser("notes", help="write the release body to stdout")
    n.add_argument("version")
    n.add_argument("changelog", nargs="?", default=CHANGELOG)
    args = parser.parse_args()
    if args.command == "zips":
        build_zips(args.outdir)
    else:
        notes(args.version, args.changelog)


if __name__ == "__main__":
    main()
