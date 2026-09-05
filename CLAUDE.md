# Working in this repository

## Never commit

Do not run `git commit` or `git push`. Stage if asked, and supply the message
text. The commit is the user's.

## Nothing personal in a repository file

No home directories, no machine-specific paths, no defaults inferred from where
the user happens to keep things. A script that needs a path takes it as an
argument. Symlinks that point outside the repository are not a solution to
anything.

## A test that fabricates its inputs is not a test

If a harness cannot get what it needs, it says what is missing and stops. It
does not substitute something made up and then report a pass. Applies to ROM
images, device responses and anything else a test stands on.

## What a document says

Documents state what is true today. Never write a promise about future work
into a README, a changelog, a specification, a commit message or a comment —
not "comes later", not "to be added", however hedged. Say it in chat instead.

An application that has not run on real hardware says so at the top of its own
README, and nowhere else.

## Adding an application

Adding one under `reference/host/` means all of:

- a job in `.github/workflows/build.yml`, and its binaries in `release.yml` if
  they are a deliverable
- an entry in `README.md`, in `reference/host/README.md`, and in
  `reference/host/<arch>/README.md` — all three
- its own README, covering what it does, what it needs, how to build it and
  how to test it

## Layout

- `spec/` — the protocol. Another session may be working in here. Do not touch
  it unless the task is the specification itself.
- `reference/host/6502/rbcp/` — the 6502 library: `rbcp_core.s` plus one module
  per command under `cmd/`, built into `rbcp.lib` with `ar65` so a host links
  only the commands it calls. Adding a command means adding a file.
- `reference/host/6502/<app>/` — one application each, with `rbcp_config.s`
  holding its ROM address, size, command page and back-channel region.
- `reference/host/68k/` — the same for 68K hosts, where the library is a single
  file included by the application.
- `reference/host/x86/romsel/` — a DOS application, built with Open Watcom's
  `wmake`. `GNUmakefile` catches `make` and says to use `wmake`.
- `host-apps/` — applications that are not reference implementations.
- `tools/publish.py` — copies release artefacts into a `one-rom-images`
  checkout and updates its manifests. See `RELEASE.md`.

`build/` is ignored everywhere. Nothing else is generated into the tree.

## Toolchains

- 6502: cc65 (`ca65`, `ld65`, `ar65`), from `brew install cc65` or `apt install
  cc65`.
- 68K: `vasmm68k_mot`, built from the tarball at
  http://sun.hasenbraten.de/vasm/ with `make CPU=m68k SYNTAX=mot`.
- Apple II testing: MAME, plus the machine's ROM files, which are not in the
  repository and must be supplied as a path.
- C64 testing: VICE. `c1541` builds the `.d64` targets and is not on the
  user's `PATH` by default.

## Before saying it works

Build it. Run it. Say which of the two you did, and on what. "It should work"
is not a report.
