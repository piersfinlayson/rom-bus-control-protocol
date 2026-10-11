#!/usr/bin/env python3
"""Read each application's app.json.

    apps.py check

An application's id is the name of the directory its app.json is in.

- check fails if:
  - an app.json is malformed
  - build.yml doesn't build an application whose source is here
  - build.yml doesn't run an application's test/run.sh

See RELEASE.md.
"""

import argparse
import json
import os
import re
import sys

# This repository's root.
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MANIFEST = "app.json"
REQUIRED = ("kind", "name", "description", "machine", "files")
OPTIONAL = ("os", "source", "zip", "build")
FILE_FIELDS = ("variant",)

WORKFLOW = ".github/workflows/build.yml"


def die(msg):
    sys.exit("%s: %s" % (os.path.basename(sys.argv[0]), msg))


def read(path):
    where = os.path.relpath(path, ROOT)
    try:
        with open(path) as f:
            app = json.load(f)
    except (OSError, ValueError) as e:
        die("%s: %s" % (where, e))
    if not isinstance(app, dict):
        die("%s isn't a JSON object" % where)
    missing = [k for k in REQUIRED if k not in app]
    if missing:
        die("%s doesn't have %s" % (where, ", ".join(missing)))
    unknown = [k for k in app if k not in REQUIRED + OPTIONAL]
    if unknown:
        die("%s: unknown field %s" % (where, ", ".join(unknown)))
    if ("zip" in app) != ("build" in app):
        die("%s: zip requires build and build requires zip" % where)
    if not isinstance(app["files"], dict) or not app["files"]:
        die("%s: files must be an object with one entry per binary" % where)
    for name, f in app["files"].items():
        unknown = [k for k in f if k not in FILE_FIELDS]
        if unknown:
            die("%s: %s: unknown field %s" % (where, name, ", ".join(unknown)))
    return app


def load():
    """Every application's app.json by id, in id order. Each has its directory
    relative to ROOT added as dir."""
    found = {}
    for d, dirs, files in os.walk(ROOT):
        dirs[:] = [x for x in dirs if x != "build" and not x.startswith(".")]
        if MANIFEST not in files:
            continue
        app_id = os.path.basename(d)
        rel = os.path.relpath(d, ROOT)
        if app_id in found:
            die("%s and %s have the same name" % (found[app_id]["dir"], rel))
        app = read(os.path.join(d, MANIFEST))
        app["dir"] = rel
        found[app_id] = app
    return dict(sorted(found.items()))


def check():
    apps = load()
    with open(os.path.join(ROOT, WORKFLOW)) as f:
        text = f.read()
    lines = [l for l in text.split("\n") if not l.lstrip().startswith("#")]
    jobs = re.split(r"^  [\w-]+:$", "\n".join(lines).split("\njobs:\n", 1)[1],
                    flags=re.M)

    # An application counts as built if its id appears in a job and as tested
    # if that job also runs test/run.sh.
    built, tested = set(), set()
    for job in jobs:
        for app_id in apps:
            if re.search(r"(?<![\w-])%s(?![\w-])" % re.escape(app_id), job):
                built.add(app_id)
                if "test/run.sh" in job:
                    tested.add(app_id)

    faults = []
    for app_id, app in apps.items():
        if "source" in app:
            continue
        if app_id not in built:
            faults.append("%s doesn't build %s" % (WORKFLOW, app_id))
        if (os.path.isfile(os.path.join(ROOT, app["dir"], "test", "run.sh"))
                and app_id not in tested):
            faults.append("%s doesn't run %s/test/run.sh" % (WORKFLOW, app_id))
    for fault in faults:
        print("%s: %s" % (os.path.basename(sys.argv[0]), fault), file=sys.stderr)
    if faults:
        sys.exit(1)
    print("%s: builds %d applications and runs %d tests"
          % (WORKFLOW, len(built), len(tested)))


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("check", help="check each app.json and build.yml")
    p.parse_args()
    check()


if __name__ == "__main__":
    main()
