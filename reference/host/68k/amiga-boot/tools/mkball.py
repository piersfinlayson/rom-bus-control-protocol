#!/usr/bin/env python3
"""Draw a Boing-style checkered sphere as blitter object data that spins by
cycling its colour registers.

The bitmap is drawn once and never changes.  The ball's surface is cut into
bands of longitude, all the same angular width, and each band is drawn in a pen
chosen by its band number.  Rotating the ball by exactly one band width maps
every band boundary onto the boundary next door, so the picture on screen is
the one already in the bitmap and only the colours have moved along by one.
Writing the eight colour registers from the next row of the cycle table is
therefore a real rotation of the sphere, not an approximation of one.

Two things make it read as a sphere rather than a rolling cylinder.  A band's
edge sits at x = R * sin(longitude), so bands near the silhouette are narrow
and bands near the middle are wide.  And the ball is cut into rows of latitude
as well, tilted over so the rows curve, which is what stops the checks reading
as a barber pole.

Latitude cannot rotate, only longitude.  The original had the same limit.  Each
row of latitude is offset by half a check so the two colours interlock, and
that offset belongs to the row, untouched by spinning about the axis.

Eight registers can hold the colour pattern only if it repeats every eight
bands, so a check is four bands wide and two checks make one turn of the cycle.
One step turns the ball by one band, a quarter of a check, and eight steps
bring the registers back to where they began.

Output
------
Four bitplanes interleaved a row at a time — plane 0's words for the row, then
plane 1's, 2's, 3's, then the next row — which is how the blitter reads an
object most cheaply.  Every row carries one extra blank word on the right so
the object can be blitted at any pixel position and the barrel shifter has
somewhere to push the overhang.  The mask is a single plane in the same shape.
Big-endian throughout.

The INCBIN paths written into the assembler source are the binary paths exactly
as given on the command line, because vasm resolves them against the directory
the assembler runs in.  Run the assembler from that directory, or pass
--incbin-dir.

    mkball.py assets/ball.bin assets/ball_mask.bin assets/ball.s
              [--colours ONE TWO] [--incbin-dir <dir>] [--preview <file.png>]

The colours are the ball's alone.  Nothing else on the screen shares its pens,
so recolouring it changes only the cycle table and leaves both bitmaps as they
were.

The optional PNG is a horizontal strip of every step of the cycle, for checking
the result outside the Amiga.  It is not part of the build.
"""
import argparse
import math
import struct
import sys
import zlib

# The ball, in pixels.  A whole number of 16-bit words across before the margin
# word is added.
DIAMETER = 64

# Blank words added to the right of every row, for the blitter's barrel
# shifter.
MARGIN_WORDS = 1

# The pens the ball may use.  Pen 0 is the transparent background and pens 1 to
# 5 and 14 to 15 belong to other artwork on the same screen.
PEN_FIRST = 6
PENS = 8

# Checks of colour around the whole sphere, so half this many are in view.
# Must be even, or the checks do not meet where longitude wraps.  Eight is the
# classic look and is as fine as 64 pixels across will carry.
CHECKS_AROUND = 8

# Rows of latitude from pole to pole.  Six rows keeps the checks close to
# square while still bending enough near the poles to show the curve.
LAT_ROWS = 6

# How far the axis leans away from vertical, in degrees, top towards the right.
# Without it the rows of latitude are straight lines and the ball reads flat.
TILT_DEG = 17.0

# Bands of longitude per check.  Fixed by the pen count: the pattern repeats
# every two checks, and that repeat has to fit in the registers exactly.
BANDS_PER_CHECK = PENS // 2
BANDS_AROUND = CHECKS_AROUND * BANDS_PER_CHECK

# One step per register, after which the registers hold what they started with.
STEPS = PENS

# The two colours of the checks, unless the command line says otherwise.
# One ROM gold, the same $0FB0 the logo and the tagline use, against white.
DEFAULT_COLOURS = (0x0FB0, 0x0FFF)

# Samples per pixel per axis.  A 64-pixel circle drawn by testing pixel centres
# alone has visibly flat spots on the diagonals.
SUPERSAMPLE = 4

# Pixels per pixel in the preview PNG, and the gap between steps in the strip.
PREVIEW_SCALE = 4
PREVIEW_GAP = 8
PREVIEW_BACKDROP = (0x18, 0x18, 0x18)

RADIUS = DIAMETER / 2.0
WIDTH_W = DIAMETER // 16 + MARGIN_WORDS
ROW_BYTES = WIDTH_W * 2
PLANES = 4


def sphere_colour(band, colours):
    """The colour of a band of longitude on the ball itself, as a $0RGB word.

    Only the band number within one repeat of the pattern matters, which is
    why eight registers can hold the lot.
    """
    return colours[(band % PENS) // BANDS_PER_CHECK]


def pen_index(px, py):
    """The pen, 0 to PENS-1, for a point this far from the centre in pixels.

    Returns None outside the silhouette.  x is right and y is down, as on the
    screen.
    """
    r2 = px * px + py * py
    if r2 > RADIUS * RADIUS:
        return None

    tilt = math.radians(TILT_DEG)
    # Front surface of the sphere, in a frame with y up and z towards the eye.
    pz = math.sqrt(RADIUS * RADIUS - r2)
    uy = -py

    # The axis leans by the tilt, and the two vectors below span the equator.
    # At the middle of the disc this gives longitude 0, and with no tilt it
    # reduces to x = R * sin(longitude) exactly.
    axis_h = px * math.sin(tilt) + uy * math.cos(tilt)
    equ_u = px * math.cos(tilt) - uy * math.sin(tilt)

    longitude = math.atan2(equ_u, pz)
    band = int(math.floor(longitude / (2.0 * math.pi / BANDS_AROUND)))

    latitude = math.asin(max(-1.0, min(1.0, axis_h / RADIUS)))
    row = int((latitude + math.pi / 2.0) / (math.pi / LAT_ROWS))
    row = max(0, min(LAT_ROWS - 1, row))

    # Odd rows are offset by half a repeat, which is one check, so the two
    # colours interlock instead of running in columns.
    return (band + BANDS_PER_CHECK * (row % 2)) % PENS


def draw():
    """Return DIAMETER rows of DIAMETER pen indices, None where transparent."""
    grid = []
    half = SUPERSAMPLE * SUPERSAMPLE / 2.0
    for y in range(DIAMETER):
        row = []
        for x in range(DIAMETER):
            votes = {}
            inside = 0
            for sy in range(SUPERSAMPLE):
                for sx in range(SUPERSAMPLE):
                    px = x + (sx + 0.5) / SUPERSAMPLE - RADIUS
                    py = y + (sy + 0.5) / SUPERSAMPLE - RADIUS
                    pen = pen_index(px, py)
                    if pen is not None:
                        inside += 1
                        votes[pen] = votes.get(pen, 0) + 1
            if inside < half or not votes:
                row.append(None)
            else:
                row.append(max(votes, key=lambda p: (votes[p], -p)))
        grid.append(row)
    return grid


def planar(grid):
    """Pack the grid into interleaved bitplanes and a single-plane mask."""
    data = bytearray()
    mask = bytearray()
    for row in grid:
        words = []
        opaque = 0
        for plane in range(PLANES):
            bits = 0
            for x in range(DIAMETER):
                pen = row[x]
                value = 0 if pen is None else PEN_FIRST + pen
                bits = (bits << 1) | ((value >> plane) & 1)
            words.append(bits)
        for x in range(DIAMETER):
            opaque = (opaque << 1) | (0 if row[x] is None else 1)

        for plane in range(PLANES):
            data += pack_row(words[plane])
        mask += pack_row(opaque)
    return bytes(data), bytes(mask)


def pack_row(bits):
    """DIAMETER bits, leftmost pixel first, then the blank margin words."""
    out = bytearray()
    for word in range(DIAMETER // 16):
        shift = DIAMETER - 16 * (word + 1)
        out += struct.pack(">H", (bits >> shift) & 0xFFFF)
    out += b"\x00\x00" * MARGIN_WORDS
    return out


def cycle(colours):
    """The colour words to write to the ball's registers, one row per step.

    At step s the register holding pen index i shows the band the ball has
    turned into that place, which is band i - s.  Stepping forward turns the
    front of the ball towards the right of the screen.
    """
    return [[sphere_colour(i - step, colours) for i in range(PENS)]
            for step in range(STEPS)]


def check(grid, data, mask, colours):
    """Verify the object before it is written, and return its numbers."""
    if len(data) != DIAMETER * PLANES * ROW_BYTES:
        sys.exit("mkball: bitplane data is the wrong size")
    if len(mask) != DIAMETER * ROW_BYTES:
        sys.exit("mkball: mask is the wrong size")

    for row in range(DIAMETER):
        for plane in range(PLANES):
            at = (row * PLANES + plane) * ROW_BYTES + DIAMETER // 8
            if data[at:at + 2 * MARGIN_WORDS] != b"\x00" * (2 * MARGIN_WORDS):
                sys.exit("mkball: the margin is not blank, row %d" % row)
        at = row * ROW_BYTES + DIAMETER // 8
        if mask[at:at + 2 * MARGIN_WORDS] != b"\x00" * (2 * MARGIN_WORDS):
            sys.exit("mkball: the mask margin is not blank, row %d" % row)

    opaque = 0
    used = set()
    for y in range(DIAMETER):
        for x in range(DIAMETER):
            pen = grid[y][x]
            if pen is None:
                continue
            opaque += 1
            used.add(PEN_FIRST + pen)
            bit = (mask[y * ROW_BYTES + x // 8] >> (7 - x % 8)) & 1
            if not bit:
                sys.exit("mkball: mask and bitmap disagree at %d,%d" % (x, y))

    if used != set(range(PEN_FIRST, PEN_FIRST + PENS)):
        sys.exit("mkball: the ball uses pens %s, not %d to %d"
                 % (sorted(used), PEN_FIRST, PEN_FIRST + PENS - 1))

    area = math.pi * RADIUS * RADIUS
    if abs(opaque - area) > 0.02 * area:
        sys.exit("mkball: the silhouette is not a circle, %d pixels against "
                 "%d expected" % (opaque, round(area)))

    if colours[0] == colours[1]:
        sys.exit("mkball: both checks are the same colour, there is nothing "
                 "to see turning")

    table = cycle(colours)
    if len(set(tuple(row) for row in table)) != STEPS:
        sys.exit("mkball: the cycle repeats itself inside %d steps" % STEPS)
    for row in table:
        if row.count(colours[0]) != PENS // 2:
            sys.exit("mkball: a step of the cycle is not half and half")

    return {"opaque": opaque, "pens": sorted(used)}


ASM = """\
; {name} — Boing-style ball, a blitter object spun by cycling its colours
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Generated by tools/mkball.py.  Edit the generator, not this file.
;
; {diameter}x{diameter} pixels in {planes} bitplanes, interleaved a row at a time — plane 0's
; {row_bytes} bytes for the row, then plane 1's, 2's, 3's, then the next row.  Every row
; carries {margin} blank word on the right so the object can be blitted at any
; pixel position, which makes a row {row_stride} bytes over all four planes.  The mask
; is a single plane in the same shape, 1 where the ball is opaque.
;
; The bitmap never changes.  The ball's surface is cut into bands of longitude
; all {band_deg:.3f} degrees wide, each drawn in its own pen, so turning the ball by one
; band lands every boundary where the one next door was.  Writing the next row
; of BallCycle to COLOR{pen_first:02d} upwards is that turn.  {steps} steps take the ball round
; by {cycle_deg:.1f} degrees and leave the registers as they started, so the table loops.
;
; The ball uses pens {pen_first} to {pen_last} and nothing else.  Pen 0 shows through as the
; background.  Checks are {checks} around the sphere and {rows} rows of latitude, the axis
; leaning {tilt:.0f} degrees.  Latitude does not turn, only longitude.
;
; The checks are ${colour_one:03X} against ${colour_two:03X}.  Only this table carries them — the
; bitmaps hold pen numbers, so recolouring the ball leaves both binaries alone.
;
; Both halves of the object are word aligned, so the blitter can be pointed
; straight at them.
; ---------------------------------------------------------------------------

BALL_WIDTH_W        EQU {width_w}                   ; words per bitplane row, margin included
BALL_WIDTH_PX       EQU {diameter}                  ; the ball itself, without the margin
BALL_HEIGHT         EQU {diameter}                  ; pixel rows
BALL_PLANES         EQU {planes}
BALL_ROW_BYTES      EQU BALL_WIDTH_W*2      ; {row_bytes} bytes, one plane of one row
BALL_ROW_STRIDE     EQU BALL_ROW_BYTES*BALL_PLANES  ; {row_stride} bytes, all planes of a row
BALL_BYTES          EQU BALL_ROW_STRIDE*BALL_HEIGHT ; {size}
BALL_MASK_BYTES     EQU BALL_ROW_BYTES*BALL_HEIGHT  ; {mask_size}

BALL_PEN_FIRST      EQU {pen_first}                   ; lowest colour register it uses
BALL_PENS           EQU {pens}                   ; registers {pen_first} to {pen_last} inclusive
BALL_STEPS          EQU {steps}                   ; rows in BallCycle
BALL_STEP_BYTES     EQU BALL_PENS*2         ; one row of BallCycle
BALL_CYCLE_BYTES    EQU BALL_STEP_BYTES*BALL_STEPS

                    CNOP    0,2
BallData:
                    INCBIN  "{incbin_data}"
BallDataEnd:

                    CNOP    0,2
BallMask:
                    INCBIN  "{incbin_mask}"
BallMaskEnd:

; One row per step, {pens} words a row, to be written to COLOR{pen_first:02d} upwards.
                    CNOP    0,2
BallCycle:
{cycle}BallCycleEnd:
"""


def write_source(path, incbin_data, incbin_mask, size, mask_size, colours):
    rows = []
    for step, entry in enumerate(cycle(colours)):
        words = ",".join("${:03X}".format(c) for c in entry)
        rows.append("                    dc.w    %s   ; step %d\n"
                    % (words, step))

    with open(path, "w") as f:
        f.write(ASM.format(
            name=path.rsplit("/", 1)[-1],
            diameter=DIAMETER,
            planes=PLANES,
            width_w=WIDTH_W,
            row_bytes=ROW_BYTES,
            row_stride=ROW_BYTES * PLANES,
            margin=MARGIN_WORDS,
            size=size,
            mask_size=mask_size,
            pen_first=PEN_FIRST,
            pen_last=PEN_FIRST + PENS - 1,
            pens=PENS,
            steps=STEPS,
            checks=CHECKS_AROUND,
            rows=LAT_ROWS,
            tilt=TILT_DEG,
            band_deg=360.0 / BANDS_AROUND,
            cycle_deg=360.0 * STEPS / BANDS_AROUND,
            colour_one=colours[0],
            colour_two=colours[1],
            incbin_data=incbin_data,
            incbin_mask=incbin_mask,
            cycle="".join(rows),
        ))


def rgb(word):
    """A 12-bit $0RGB word as the eight-bit triple a PNG wants."""
    return (((word >> 8) & 0xF) * 0x11,
            ((word >> 4) & 0xF) * 0x11,
            (word & 0xF) * 0x11)


def write_png(path, grid, colours):
    """A horizontal strip of every step of the cycle, one ball per step."""
    table = cycle(colours)
    ball = DIAMETER * PREVIEW_SCALE
    width = STEPS * ball + (STEPS - 1) * PREVIEW_GAP
    height = ball

    raw = bytearray()
    for y in range(height):
        raw.append(0)
        line = bytearray()
        for step in range(STEPS):
            if step:
                line += bytes(PREVIEW_BACKDROP) * PREVIEW_GAP
            row = grid[y // PREVIEW_SCALE]
            for x in range(ball):
                pen = row[x // PREVIEW_SCALE]
                if pen is None:
                    line += bytes(PREVIEW_BACKDROP)
                else:
                    line += bytes(rgb(table[step][pen]))
        raw += line

    def chunk(tag, body):
        return (struct.pack(">I", len(body)) + tag + body
                + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR",
                      struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


def parse_colour(text):
    """A colour as RGB or RRGGBB hex, with or without a # or $, to $0RGB.

    Six digits are the colour a paint program shows.  They are rounded to the
    four bits a gun actually has, so what comes out is what the Amiga
    displays, not what was asked for.
    """
    digits = text.lstrip("#$").strip()
    try:
        value = int(digits, 16)
    except ValueError:
        sys.exit("mkball: %r is not a hex colour" % text)

    if len(digits) in (3, 4):
        return value & 0x0FFF
    if len(digits) == 6:
        return ((round(((value >> 16) & 0xFF) / 255.0 * 15) << 8)
                | (round(((value >> 8) & 0xFF) / 255.0 * 15) << 4)
                | round((value & 0xFF) / 255.0 * 15))
    sys.exit("mkball: %r is not 3, 4 or 6 hex digits" % text)


def main():
    ap = argparse.ArgumentParser(
        description="Generate the Amiga Boing-style ball object.")
    ap.add_argument("binary", help="raw interleaved bitplane data to write")
    ap.add_argument("mask", help="raw single-plane mask to write")
    ap.add_argument("source", help="assembler source to write")
    ap.add_argument("--colours", nargs=2, metavar=("ONE", "TWO"),
                    default=["%03X" % c for c in DEFAULT_COLOURS],
                    help="the two colours of the checks, as RGB or RRGGBB "
                         "hex, default %(default)s")
    ap.add_argument("--incbin-dir", help="directory to put in front of the "
                                         "binaries' names in the INCBIN "
                                         "paths, if not the paths as given")
    ap.add_argument("--preview", help="also write a PNG strip of the cycle")
    args = ap.parse_args()

    colours = [parse_colour(c) for c in args.colours]

    if CHECKS_AROUND % 2:
        sys.exit("mkball: an odd number of checks cannot meet where the "
                 "longitude wraps")
    if DIAMETER % 16:
        sys.exit("mkball: the diameter must be a whole number of words")

    grid = draw()
    data, mask = planar(grid)
    numbers = check(grid, data, mask, colours)

    with open(args.binary, "wb") as f:
        f.write(data)
    with open(args.mask, "wb") as f:
        f.write(mask)

    def incbin(path):
        if not args.incbin_dir:
            return path
        return args.incbin_dir.rstrip("/") + "/" + path.rsplit("/", 1)[-1]

    write_source(args.source, incbin(args.binary), incbin(args.mask),
                 len(data), len(mask), colours)

    if args.preview:
        write_png(args.preview, grid, colours)

    print("%s: %d bytes, %dx%d in %d planes, %d words a row with the margin"
          % (args.binary, len(data), DIAMETER, DIAMETER, PLANES, WIDTH_W))
    print("%s: %d bytes" % (args.mask, len(mask)))
    print("%s: %d cycle steps, %d words a step, pens %d to %d"
          % (args.source, STEPS, PENS, numbers["pens"][0], numbers["pens"][-1]))
    print("checks $%03X against $%03X, as #%s against #%s on screen"
          % (colours[0], colours[1],
             "".join("%02X" % v for v in rgb(colours[0])),
             "".join("%02X" % v for v in rgb(colours[1]))))
    print("%d bands of %.3f degrees, %d checks around, %d rows of latitude, "
          "axis tilted %.0f degrees"
          % (BANDS_AROUND, 360.0 / BANDS_AROUND, CHECKS_AROUND, LAT_ROWS,
             TILT_DEG))
    print("one step turns the ball %.3f degrees, the cycle turns it %.1f"
          % (360.0 / BANDS_AROUND, 360.0 * STEPS / BANDS_AROUND))
    print("%d opaque pixels against %d for a circle"
          % (numbers["opaque"], round(math.pi * RADIUS * RADIUS)))


if __name__ == "__main__":
    main()
