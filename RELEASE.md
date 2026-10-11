# Releasing

The specification and the applications are versioned separately. The
specification's version is the tag. Every application has its own version,
and [images.onerom.org](https://images.onerom.org) lists each application at
its own version, never at the tag.

`tools/publish.py` does the publishing. Its first argument is the path to a
`one-rom-images` checkout, and it requires only python3.

## A full RBCP release

1. Set the version at the top of `spec/rbcp.md`, and record the changes in
   `spec/CHANGELOG.md` under a heading with that version. That section opens
   the release body, so a version without a section of its own fails the
   release.
2. Raise the version of every application whose code changed since the last
   release, as in **An application release**.
3. Tag and push. `release.yml` builds the ROM images and `romsel.exe` and
   attaches one zip per platform to a GitHub release, with the specification.
   The release fails if a binary listed in an `app.json` wasn't built.

   ```
   git tag v0.1.2
   git push origin v0.1.2
   ```

4. Publish each application that changed, one command each, as below.

The tag reaches the GitHub release. It does not reach images.onerom.org.

## An application release

An application is published when its own version changes, which need not be
at an RBCP release.

1. Raise `APP_VERSION` in the application's source, or `CFG_VERSION` for
   ROMSEL.

2. Build it.

   - The 6502 images: cc65.
   - The Amiga ones: `vasmm68k_mot`. `make images` writes both sizes under the
     names a release uses, already in the device's byte order.
   - ROMSEL: Open Watcom. Use a DOS or Linux machine, or the artefact from the
     `build.yml` run.

3. Publish it.

   ```
   tools/publish.py /path/to/one-rom-images app c64-boot \
       reference/host/6502/c64-boot/build/c64_boot.bin \
       reference/host/6502/c64-boot/build/c64_boot_combined.bin
   ```

   That reads the version from the application's source, then:

   - copies the files to `roms/host-control/c64-boot/v<version>/`
   - copies the newest version's files to `roms/host-control/c64-boot/latest/`
   - records the version and each file's sha256 in `roms.json`

   ROMSEL is copied to `retro-apps/romsel/` and recorded in `retro-apps.json`
   instead.

   Publishing fails if the version is already published with different binaries.

4. Commit and push `one-rom-images`.

## app.json

Every application that is published or released has an `app.json` in its
directory. The directory's name is the application's id.

| Field | Contents |
| --- | --- |
| `kind` | `rom` for a ROM image or `retro` for a program run from disk |
| `name` | Application name |
| `description` | Short description |
| `machine` | Machine it runs on, for example `c64` |
| `os` | Operating system of a `retro` application |
| `source` | URL of source that isn't in this repository |
| `zip` | Release zip name, for example `c64` for `c64.zip`. An application without one isn't released |
| `build` | Build command. It runs in the application's directory and is required with `zip` |
| `files` | Each binary's file name and optional `variant` |

A change to `app.json` takes effect at the application's next publish.
