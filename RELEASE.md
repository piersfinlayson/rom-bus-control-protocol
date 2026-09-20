# Releasing

The specification and the applications are versioned separately. The
specification's version is the tag. Every application carries its own, and
what goes to [images.onerom.org](https://images.onerom.org) is an
application at its own version, never at the tag.

`tools/publish.py` does the publishing. It takes the path to a
`one-rom-images` checkout and needs only python3.

## A full RBCP release

1. Set the version at the top of `spec/rbcp.md`, and record the changes in
   `spec/CHANGELOG.md` under a heading carrying that version. That section
   opens the release body, so a version with no section of its own fails the
   release.
2. Raise the version of every application whose code changed since the last
   release. The section below says where each one lives.
3. Tag and push. `release.yml` builds the ROM images and `romsel.exe` and
   attaches one zip per platform to a GitHub release, with the specification.
   `tools/release_assets.py` holds the list of files each zip carries and stops
   the release if one is missing.

   ```
   git tag v0.1.2
   git push origin v0.1.2
   ```

4. Publish each application that changed, one command each, as below.

The tag reaches the GitHub release. It does not reach images.onerom.org.

## An application release

An application is published when its own version changes, which need not be
at an RBCP release.

1. Raise the version in the application's source:

   | Application | Constant |
   |---|---|
   | `c64-boot` | `APP_VERSION` in `reference/host/6502/c64-boot/src/c64_boot.s` |
   | `vic20-boot` | `APP_VERSION` in `reference/host/6502/vic20-boot/src/vic20_defs.s` |
   | `apple2-boot` | `APP_VERSION` in `reference/host/6502/apple2-boot/src/apple2_defs.s` |
   | `amiga-boot` | `APP_VERSION` in `reference/host/68k/amiga-boot/amiga_boot.s` |
   | `amiga-rbcp-stress` | `APP_VERSION` in `reference/host/68k/amiga-rbcp-stress/amiga_stress.s` |
   | `amiga-pipe-test` | `APP_VERSION` in `reference/host/68k/amiga-pipe-test/amiga_pipe.s` |
   | `amiga-rbcp-term` | `APP_VERSION` in `reference/host/68k/amiga-rbcp-term/amiga_term.s` |
   | `amiga-aux-io` | `APP_VERSION` in `reference/host/68k/amiga-aux-io/amiga_auxio.s` |
   | `amiga-led-test` | `APP_VERSION` in `reference/host/68k/amiga-led-test/amiga_led_test.s` |
   | `romsel` | `CFG_VERSION` in `reference/host/x86/romsel/config.h` |

2. Build it.

   - The 6502 images: cc65.
   - The Amiga ones: `vasmm68k_mot`. `make images` writes both sizes under the
     names a release carries, already in the device's byte order.
   - ROMSEL: Open Watcom, which has no macOS build. Use a DOS or Linux
     machine, or the artefact from the `build.yml` run.

3. Publish the binary.

   ```
   tools/publish.py /path/to/one-rom-images app romsel v0.1.0 build/romsel.exe
   ```

   That copies it to `retro-apps/romsel/v0.1.0/` and over
   `retro-apps/romsel/latest/`, and records the version and its sha256 in
   `retro-apps.json`. A ROM image goes to `roms/host-control/<id>/` and
   `roms.json` instead. An application that builds more than one file takes
   them all at once. Commit and push `one-rom-images`.

   Publishing a version that is already listed, with different bytes, is
   refused. Raise the version.

Publishing an application the script has not seen before means adding an entry
to `APPS` in `tools/publish.py`.
