#!/usr/bin/env python3
# mkimage.py — convert artwork into Amiga blitter objects
# Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
#
# Turns a PNG, or a line of TrueType text, into interleaved 4-bitplane data
# for a 16-colour lores screen, plus a single-plane mask and a vasm source
# file that declares the sizes and pulls the binaries in with INCBIN.
#
# Every path is an argument.  Nothing about any particular machine, checkout
# or piece of artwork is built in.
#
# Run "mkimage.py --help", or see README.md in this directory.

import argparse
import os
import sys
import textwrap

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFont
except ImportError:
    sys.exit("mkimage.py needs Pillow: pip install pillow")


PLANES = 4
SUPERSAMPLE = 4         # glyphs are rendered this much larger, then reduced


def fail(message):
    print(f"mkimage.py: {message}", file=sys.stderr)
    sys.exit(1)


def need_file(path, what):
    if not os.path.isfile(path):
        fail(f"{what} not found: {path}")
    return path


# ---------------------------------------------------------------- palette --

def quantise(rgb):
    """Drop 24-bit RGB to the 4 bits per gun the Amiga actually displays."""
    return tuple((c >> 4) * 0x11 for c in rgb)


def amiga_word(rgb):
    r, g, b = (c >> 4 for c in rgb)
    return (r << 8) | (g << 4) | b


def parse_pen(text):
    """--pen 2=FFB700 -> (2, (255, 183, 0))"""
    if "=" not in text:
        fail(f"--pen wants PEN=RRGGBB, got {text!r}")
    index, colour = text.split("=", 1)
    try:
        pen = int(index, 0)
    except ValueError:
        fail(f"--pen index is not a number: {index!r}")
    colour = colour.lstrip("#$")
    if len(colour) != 6:
        fail(f"--pen colour wants six hex digits, got {colour!r}")
    try:
        value = int(colour, 16)
    except ValueError:
        fail(f"--pen colour is not hex: {colour!r}")
    if not 0 <= pen < 16:
        fail(f"--pen index out of range 0..15: {pen}")
    return pen, ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def build_palette(pen_args):
    pens = {}
    for text in pen_args:
        pen, rgb = parse_pen(text)
        if pen in pens:
            fail(f"pen {pen} given twice")
        pens[pen] = quantise(rgb)
    if 0 not in pens:
        pens[0] = (0, 0, 0)
    return pens


def nearest_pen(rgb, pens):
    """Closest pen to one RGB triple, by squared distance."""
    best, best_d = 0, None
    for pen, colour in pens.items():
        d = sum((a - b) ** 2 for a, b in zip(rgb, colour))
        if best_d is None or d < best_d:
            best, best_d = pen, d
    return best


def parse_coverage(text):
    """--pen-coverage 5=0.25 -> (5, 0.25)"""
    if "=" not in text:
        fail(f"--pen-coverage wants PEN=FRACTION, got {text!r}")
    index, fraction = text.split("=", 1)
    try:
        pen = int(index, 0)
    except ValueError:
        fail(f"--pen-coverage pen is not a number: {index!r}")
    try:
        value = float(fraction)
    except ValueError:
        fail(f"--pen-coverage fraction is not a number: {fraction!r}")
    if not 0.0 < value <= 1.0:
        fail(f"--pen-coverage fraction must be above 0 and at most 1: {value}")
    return pen, value


def coverage_map(image, pens, pen, size, alpha_floor):
    """How much of each output pixel is genuinely this pen's colour.

    Averaging a thin light feature on a dark ground pulls it towards the
    ground before any pen is chosen, so a pin leg one source pixel wide
    disappears into the chip body.  This measures the feature instead of the
    average: every source pixel close enough to the pen's own colour counts
    1, everything else counts 0, and the reduction returns the fraction of
    the output pixel those covered.  Returned as an "L" image, 255 = all.

    "Close enough" is half the distance to the nearest other allowed pen, on
    the widest channel, so a source pixel counts for the pen it would be
    snapped to anyway and for no other.
    """
    target = pens[pen]
    others = [c for p, c in pens.items() if p != pen]
    tol = min(max(abs(a - b) for a, b in zip(target, other))
              for other in others) // 2

    red, green, blue, alpha = image.split()
    match = alpha.point(lambda v: 255 if v >= alpha_floor else 0)
    for band, value in ((red, target[0]), (green, target[1]), (blue, target[2])):
        near = band.point(lambda v, t=value: 255 if abs(v - t) <= tol else 0)
        match = ImageChops.multiply(match, near)
    return match.resize(size, Image.BOX)


# ------------------------------------------------------------- bitplanes --

def encode(pixels, mask_rows, width_px):
    """Pack pen indices into interleaved bitplanes and a one-plane mask.

    pixels     list of rows, each a list of pen indices
    mask_rows  list of rows, each a list of 0/1
    width_px   pixel width the rows are padded to, a multiple of 16

    Returns (data, mask, words_per_row).  Plane words for one pixel row run
    plane 0, 1, 2, 3, then the next pixel row starts.  Words are big-endian.
    """
    words = width_px // 16
    data = bytearray()
    mask = bytearray()
    for row, mrow in zip(pixels, mask_rows):
        for plane in range(PLANES):
            bit = 1 << plane
            for word in range(words):
                value = 0
                for i in range(16):
                    if row[word * 16 + i] & bit:
                        value |= 0x8000 >> i
                data += value.to_bytes(2, "big")
        for word in range(words):
            value = 0
            for i in range(16):
                if mrow[word * 16 + i]:
                    value |= 0x8000 >> i
            mask += value.to_bytes(2, "big")
    return bytes(data), bytes(mask), words


def decode_preview(data, words, height, pens, path):
    """Unpack the encoded planes again and write a PNG of what they hold."""
    image = Image.new("RGB", (words * 16, height))
    put = image.load()
    bpr = words * 2
    for y in range(height):
        base = y * PLANES * bpr
        for x in range(words * 16):
            word, bit = divmod(x, 16)
            pen = 0
            for plane in range(PLANES):
                byte = data[base + plane * bpr + word * 2 + (bit >> 3)]
                if byte & (0x80 >> (bit & 7)):
                    pen |= 1 << plane
            put[x, y] = pens.get(pen, (255, 0, 255))
    image.save(path)
    return image.size


# ----------------------------------------------------------------- source --

COL = 20            # directives and EQU start here, as in assets/ball.s


def wrap_comment(paragraphs):
    """Wrap paragraphs into "; " comment lines, blank ones becoming ";"."""
    out = []
    for text in paragraphs:
        if not text:
            out.append(";")
            continue
        out += [f"; {line}" for line in
                textwrap.wrap(text, width=73, break_long_words=False)]
    return out


def equ(prefix, suffix, value, comment):
    # A name at or over the column still needs a space before EQU, or the
    # assembler reads the two run together as one identifier.
    name = f"{prefix}_{suffix}"
    line = name + " " * max(1, COL - len(name)) + f"EQU {value}"
    if not comment:
        return line
    return line + " " * max(2, 48 - len(line)) + f"; {comment}"


def emit_source(path, name, words, height, pens, data_name, mask_name,
                incbin_dir, title, note):
    prefix = name.upper()
    label = "".join(part.capitalize()
                    for part in name.replace("-", "_").split("_"))

    def incbin(filename):
        return os.path.join(incbin_dir, filename) if incbin_dir else filename

    lines = [
        f"; {os.path.basename(path)} — {title}",
        "; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>",
        ";",
        "; Generated by tools/mkimage.py.  Edit the generator and re-run it, not",
        "; this file.  tools/README.md has the command.",
        ";",
    ]
    lines += wrap_comment(note)
    lines += [";"] + wrap_comment([
        f"{(words - 1) * 16}x{height} pixels in {PLANES} bitplanes, interleaved a "
        f"row at a time — plane 0's {words * 2} bytes for the row, then plane 1's, "
        f"2's, 3's, then the next row.  Every row carries 1 blank word on the "
        f"right so the object can be blitted at any pixel position, which makes a "
        f"row {words * 2 * PLANES} bytes over all four planes.  The mask is a "
        f"single plane in the same shape, 1 where the object is opaque and 0 where "
        f"the background shows through.  Words are big-endian.",
        "",
        "Both halves of the object are word aligned, so the blitter can be pointed "
        "straight at them.",
    ]) + [
        "; " + "-" * 73,
        "",
        equ(prefix, "WIDTH_W", words,
            "words per bitplane row, margin included"),
        equ(prefix, "WIDTH_PX", (words - 1) * 16,
            "the object itself, without the margin"),
        equ(prefix, "HEIGHT", height, "pixel rows"),
        equ(prefix, "PLANES", PLANES, None),
        equ(prefix, "ROW_BYTES", f"{prefix}_WIDTH_W*2",
            f"{words * 2} bytes, one plane of one row"),
        equ(prefix, "ROW_STRIDE", f"{prefix}_ROW_BYTES*{prefix}_PLANES",
            f"{words * 2 * PLANES} bytes, all planes of a row"),
        equ(prefix, "BYTES", f"{prefix}_ROW_STRIDE*{prefix}_HEIGHT",
            str(height * PLANES * words * 2)),
        equ(prefix, "MASK_BYTES", f"{prefix}_ROW_BYTES*{prefix}_HEIGHT",
            str(height * words * 2)),
        equ(prefix, "BLIT_ROWS", f"{prefix}_HEIGHT*{prefix}_PLANES",
            f"{height * PLANES}, one blit copies all four planes"),
        "",
        "; Colour registers, $0RGB.  The object uses these pens and no others.",
    ]
    for pen in sorted(pens):
        rgb = pens[pen]
        lines.append(equ(prefix, f"PEN{pen}", f"${amiga_word(rgb):04X}",
                         f"#{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}"))
    lines += [
        "",
        " " * COL + "CNOP    0,2",
        f"{label}Data:",
        " " * COL + f'INCBIN  "{incbin(data_name)}"',
        f"{label}DataEnd:",
        "",
        " " * COL + "CNOP    0,2",
        f"{label}Mask:",
        " " * COL + f'INCBIN  "{incbin(mask_name)}"',
        f"{label}MaskEnd:",
        "",
    ]
    with open(path, "w") as handle:
        handle.write("\n".join(lines))
    return label


def write_object(out_dir, name, pixels, mask_rows, width_px, height, pens,
                 incbin_dir, title, note, preview):
    os.makedirs(out_dir, exist_ok=True)
    data, mask, words = encode(pixels, mask_rows, width_px)
    data_name, mask_name = f"{name}.bin", f"{name}_mask.bin"
    with open(os.path.join(out_dir, data_name), "wb") as handle:
        handle.write(data)
    with open(os.path.join(out_dir, mask_name), "wb") as handle:
        handle.write(mask)
    source = os.path.join(out_dir, f"{name}.s")
    label = emit_source(source, name, words, height, pens, data_name,
                        mask_name, incbin_dir, title, note)

    print(f"{name}: {(words - 1) * 16}x{height} pixels plus a margin word, "
          f"{words} words per plane row")
    print(f"  {data_name}  {len(data)} bytes")
    print(f"  {mask_name}  {len(mask)} bytes")
    print(f"  {name}.s     labels {label}Data, {label}Mask")
    used = sorted({pen for row in pixels for pen in row})
    print(f"  pens used: {', '.join(str(p) for p in used)}")
    if preview:
        size = decode_preview(data, words, height, pens, preview)
        print(f"  preview {preview} {size[0]}x{size[1]} (decoded from {data_name})")


def pad_row(row, width_px, fill=0):
    return row + [fill] * (width_px - len(row))


# ------------------------------------------------------------------ image --

def report_colours(path):
    image = Image.open(need_file(path, "image")).convert("RGBA")
    tally = image.getcolors(maxcolors=image.width * image.height)
    counts = {}
    for count, (r, g, b, a) in tally:
        if a < 128:
            continue
        key = quantise((r, g, b))
        counts[key] = counts.get(key, 0) + count
    total = sum(counts.values())
    print(f"{path}: {image.width}x{image.height}, {len(counts)} opaque "
          f"colours after 12-bit quantisation")
    for rgb, count in sorted(counts.items(), key=lambda kv: -kv[1]):
        share = 100.0 * count / total
        if share < 0.05:
            break
        print(f"  #{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}  ${amiga_word(rgb):04X}  "
              f"{count:9d}  {share:5.2f}%")


def cmd_image(args):
    pens = build_palette(args.pen)
    if len(pens) < 2:
        fail("give at least one --pen besides pen 0")

    image = Image.open(need_file(args.png, "image")).convert("RGBA")
    if args.trim:
        box = image.getchannel("A").point(lambda v: 255 if v > 128 else 0).getbbox()
        if box is None:
            fail("the image is fully transparent")
        image = image.crop(box)

    if args.width % 16:
        fail(f"--width must be a multiple of 16, got {args.width}")
    height = args.height or max(1, round(image.height * args.width / image.width))

    # Area-average the whole footprint of each output pixel.  The artwork is
    # flat colour over a huge reduction, so averaging and then snapping to the
    # nearest pen keeps edges continuous.  Point sampling drops thin features
    # such as the pin legs in and out from row to row and looks like speckle.
    small = image.resize((args.width, height), Image.BOX)

    # Pens that win on coverage rather than on the average.  Checked in
    # descending order of how much they cover, so the strongest claim wins
    # when two overlap.
    wanted = {}
    for text in args.pen_coverage:
        pen, fraction = parse_coverage(text)
        if pen not in pens:
            fail(f"--pen-coverage names pen {pen}, which has no --pen")
        wanted[pen] = fraction
    # Coverage is measured for every pen, not just the ones with a rule,
    # because a rule may only claim a pixel it covers more of than anything
    # else does.  Without that test a sliver of a light feature takes a pixel
    # that is almost all outline, and the outline disappears.
    covers = {pen: coverage_map(image, pens, pen, (args.width, height),
                                args.alpha).load()
              for pen in (pens if wanted else {})}

    pixels, mask_rows = [], []
    width_px = args.width + 16          # one blank margin word on the right
    forced = 0
    for y in range(height):
        row, mrow = [], []
        for x in range(args.width):
            claims = sorted(((covers[pen][x, y], pen)
                             for pen, fraction in wanted.items()
                             if covers[pen][x, y] >= fraction * 255
                             and covers[pen][x, y] >= max(
                                 covers[other][x, y] for other in covers
                                 if other != pen)),
                            reverse=True)
            if claims:
                # This pixel really is mostly that pen's colour, so it keeps
                # it, and it is opaque because the feature is there.
                row.append(claims[0][1])
                mrow.append(1)
                forced += 1
                continue
            r, g, b, a = small.getpixel((x, y))
            opaque = a >= args.alpha
            # Average against black so a part-covered edge pixel darkens
            # towards the background rather than keeping full colour.
            blended = tuple(round(c * a / 255.0) for c in (r, g, b))
            row.append(nearest_pen(blended, pens) if opaque else 0)
            mrow.append(1 if opaque else 0)
        pixels.append(pad_row(row, width_px))
        mask_rows.append(pad_row(mrow, width_px))
    if wanted:
        print(f"  coverage rule kept {forced} pixels for pens "
              f"{', '.join(str(p) for p in sorted(wanted))}")

    note = [f"From {os.path.basename(args.png)}, area-averaged to "
            f"{args.width}x{height} and then snapped to the nearest of the pens "
            f"below, so the object holds no colour outside them."]
    if wanted:
        note.append(
            "Averaging alone loses a feature only a source pixel or two wide "
            "on a dark ground, because the average slides towards the ground "
            "before any pen is picked.  "
            + "  ".join(f"A pixel at least {int(f * 100)}% covered by pen "
                        f"{p}'s colour is therefore held at pen {p}."
                        for p, f in sorted(wanted.items())))
    write_object(args.out, args.name, pixels, mask_rows, width_px, height,
                 pens, args.incbin_dir, args.title, note, args.preview)


# ------------------------------------------------------------------- text --

def parse_span(text, length):
    """--pen-span 2=5:1 -> (2, range of character indices)"""
    if "=" not in text:
        fail(f"--pen-span wants PEN=START[:COUNT], got {text!r}")
    index, where = text.split("=", 1)
    try:
        pen = int(index, 0)
    except ValueError:
        fail(f"--pen-span pen is not a number: {index!r}")
    start, _, count = where.partition(":")
    try:
        start = int(start, 0)
        count = int(count, 0) if count else 1
    except ValueError:
        fail(f"--pen-span wants numbers, got {where!r}")
    if count < 1:
        fail(f"--pen-span count must be at least 1, got {count}")
    if not 0 <= start < length or start + count > length:
        fail(f"--pen-span {start}:{count} falls outside the {length} "
             f"characters of --text")
    return pen, range(start, start + count)


def render_lines(font_path, lines, size, leading, threshold, pen_of=None,
                 default_pen=None):
    """Render centred lines at SUPERSAMPLE scale, reduce, threshold to 1 bit.

    The lines are drawn as whole strings, exactly as they would be if every
    character shared a pen, and the finished bitmap is then divided up by
    column: the pixels between where the string layout left the pen before a
    character and where it left it after belong to that character.  Colouring
    a character therefore cannot move, respace or reshape anything, because
    nothing is drawn differently — the same bitmap is simply shared out.

    Returns (bitmap, pen_at) where pen_at(x, y) gives the pen for a lit pixel,
    or (bitmap, None) when pen_of is None.
    """
    font = ImageFont.truetype(font_path, size * SUPERSAMPLE)
    ascent, descent = font.getmetrics()
    step = int(round(size * leading)) * SUPERSAMPLE
    widths = [font.getbbox(line)[2] for line in lines]
    wide = max(widths)
    pad = 4 * SUPERSAMPLE
    canvas = Image.new("L", (wide + 2 * pad, step * (len(lines) - 1)
                             + ascent + descent + 2 * pad), 0)
    draw = ImageDraw.Draw(canvas)
    for i, line in enumerate(lines):
        draw.text((pad + (wide - widths[i]) // 2, pad + i * step), line,
                  font=font, fill=255)
    small = canvas.resize((canvas.width // SUPERSAMPLE,
                           canvas.height // SUPERSAMPLE), Image.BOX)
    cut = small.point(lambda v: 255 if v >= threshold * 255 else 0)
    box = cut.getbbox()
    if box is None:
        return None, None
    bitmap = cut.crop(box)
    if pen_of is None:
        return bitmap, None

    # Which character owns which column, in the reduced and cropped frame.
    owner = {}
    offset = 0                          # index of this line's first character
    for i, line in enumerate(lines):
        left = pad + (wide - widths[i]) // 2
        top = (pad + i * step) // SUPERSAMPLE - box[1]
        bottom = (pad + i * step + ascent + descent) // SUPERSAMPLE - box[1]
        for j in range(len(line)):
            start = int((left + font.getlength(line[:j])) // SUPERSAMPLE) - box[0]
            stop = int((left + font.getlength(line[:j + 1])) // SUPERSAMPLE) - box[0]
            pen = pen_of(offset + j)
            for x in range(start, stop):
                for y in range(top, bottom):
                    owner[(x, y)] = pen
        offset += len(line) + 1         # the newline counts as a character

    def pen_at(x, y):
        return owner.get((x, y), default_pen)

    return bitmap, pen_at


def cmd_text(args):
    pens = build_palette(args.pen)
    inks = sorted(pen for pen in pens if pen != 0)
    if not inks:
        fail("text wants at least one --pen besides pen 0")

    font_path = need_file(args.font, "font")
    text = args.text.replace("\\n", "\n")
    lines = text.split("\n")

    if args.text_pen is not None:
        default = args.text_pen
        if default not in pens:
            fail(f"--text-pen names pen {default}, which has no --pen")
        if default == 0:
            fail("--text-pen cannot be pen 0, which is the background")
    elif len(inks) == 1:
        default = inks[0]
    else:
        fail("more than one ink pen, so --text-pen must say which is the "
             "default for characters no --pen-span covers")

    spans = {}
    for entry in args.pen_span:
        pen, where = parse_span(entry, len(text))
        if pen not in pens:
            fail(f"--pen-span names pen {pen}, which has no --pen")
        if pen == 0:
            fail("--pen-span cannot be pen 0, which is the background")
        for index in where:
            if text[index] == "\n":
                fail(f"--pen-span covers the line break at index {index}")
            spans[index] = pen

    def pen_of(index):
        return spans.get(index, default)

    used = sorted({default} | set(spans.values()))
    if spans:
        print("pens: " + ", ".join(
            f"{pen} for " + ("the rest" if pen == default and not
                             all(spans.get(i) == pen for i in spans)
                             else "")
            + "".join(sorted({text[i] for i in spans if spans[i] == pen}))
            for pen in used))

    if args.size:
        size = args.size
        bitmap, pen_at = render_lines(font_path, lines, size, args.leading,
                                      args.threshold, pen_of, default)
        if bitmap is None:
            fail("the text rendered as nothing")
        if bitmap.width > args.max_width:
            fail(f"--size {size} renders {bitmap.width} pixels wide, "
                 f"over --max-width {args.max_width}")
    else:
        # Largest whole point size whose widest line still fits.
        size, bitmap, pen_at = None, None, None
        for trial in range(args.min_size, args.max_size + 1):
            attempt, owner = render_lines(font_path, lines, trial, args.leading,
                                          args.threshold, pen_of, default)
            if attempt is None or attempt.width > args.max_width:
                break
            size, bitmap, pen_at = trial, attempt, owner
        if bitmap is None:
            fail(f"nothing between --min-size {args.min_size} and "
                 f"--max-size {args.max_size} fits in {args.max_width} pixels")
        print(f"fitted point size {size}")

    ink_w, ink_h = bitmap.width, bitmap.height
    usable = ((ink_w + 15) // 16) * 16                   # whole words of ink
    width_px = usable + 16                               # plus the margin word
    left = (usable - ink_w) // 2                         # centre in those words

    read = bitmap.load()
    pixels, mask_rows, tally = [], [], {}
    for y in range(ink_h):
        row = [0] * left
        for x in range(ink_w):
            if not read[x, y]:
                row.append(0)
                continue
            pen = pen_at(x, y) if pen_at else default
            tally[pen] = tally.get(pen, 0) + 1
            row.append(pen)
        pixels.append(pad_row(row, width_px))
        mask_rows.append(pad_row([1 if v else 0 for v in row], width_px))

    shown = ", ".join(str(pen) for pen in sorted(tally))
    note = [f'"{" / ".join(lines)}" set in {os.path.basename(font_path)} at '
            f"{size} point and thresholded to one bit.  The ink covers "
            f"{ink_w}x{ink_h} pixels, centred in the {width_px - 16}-pixel "
            f"row."]
    if spans:
        note.append(
            "Each line is drawn as one string and the finished bitmap is "
            "then shared out by column, so a character in its own pen is the "
            "same pixels it would have been in any other — nothing moves, "
            "respaces or changes shape.  Pen " + str(default) + " sets the "
            "text, except " + ", ".join(
                f"{text[i]!r} at index {i} in pen {spans[i]}"
                for i in sorted(spans)) + ".")
    note.append(f"Pens {shown} are set, and all four planes are stored so the "
                f"blit matches the other objects on this screen.")
    write_object(args.out, args.name, pixels, mask_rows, width_px,
                 ink_h, pens, args.incbin_dir, args.title, note,
                 args.preview)


# ------------------------------------------------------------------- main --

def main():
    parser = argparse.ArgumentParser(
        description="Convert artwork into Amiga interleaved bitplane objects.")
    subs = parser.add_subparsers(dest="command", required=True)

    def common(sub):
        sub.add_argument("--name", required=True,
                         help="output stem, and the prefix for the EQUs")
        sub.add_argument("--title", default="blitter object",
                         help="one line describing the object, for the top of "
                              "the generated .s")
        sub.add_argument("--out", required=True,
                         help="directory to write the .bin and .s files into")
        sub.add_argument("--pen", action="append", default=[], metavar="N=RRGGBB",
                         help="allow pen N, showing this colour — repeatable")
        sub.add_argument("--incbin-dir", default="",
                         help="path the INCBIN lines are written relative to, "
                              "as the assembler will see it")
        sub.add_argument("--preview", metavar="PNG",
                         help="write a PNG decoded back out of the bitplanes")

    image = subs.add_parser("image", help="convert a PNG")
    image.add_argument("png", help="source image")
    image.add_argument("--width", type=int, required=True,
                       help="output width in pixels, a multiple of 16, "
                            "before the margin word")
    image.add_argument("--height", type=int,
                       help="output height, default keeps the aspect ratio")
    image.add_argument("--alpha", type=int, default=110,
                       help="alpha at or above which a pixel is opaque "
                            "(default 110)")
    image.add_argument("--trim", action="store_true",
                       help="crop to the opaque bounding box first")
    image.add_argument("--pen-coverage", action="append", default=[],
                       metavar="N=FRACTION",
                       help="hold pen N wherever its own colour covers at "
                            "least this much of an output pixel, instead of "
                            "letting the average decide — repeatable")
    image.set_defaults(func=cmd_image)

    text = subs.add_parser("text", help="set a line of TrueType text")
    text.add_argument("font", help="TrueType font file")
    text.add_argument("--text", required=True,
                      help="the text, with \\n between lines")
    text.add_argument("--max-width", type=int, required=True,
                      help="widest the rendered text may be, in pixels")
    text.add_argument("--size", type=int,
                      help="point size, default is the largest that fits")
    text.add_argument("--min-size", type=int, default=6)
    text.add_argument("--max-size", type=int, default=64)
    text.add_argument("--leading", type=float, default=1.35,
                      help="line pitch as a multiple of the point size")
    text.add_argument("--threshold", type=float, default=0.45,
                      help="grey level at which a reduced pixel turns on")
    text.add_argument("--text-pen", type=int, metavar="N",
                      help="pen for characters no --pen-span covers, needed "
                           "once more than one ink pen is allowed")
    text.add_argument("--pen-span", action="append", default=[],
                      metavar="N=START[:COUNT]",
                      help="set COUNT characters from index START in pen N, "
                           "counting from 0 through --text as written — "
                           "repeatable")
    text.set_defaults(func=cmd_text)

    colours = subs.add_parser("colours",
                              help="list the colours in a PNG and stop")
    colours.add_argument("png")
    colours.set_defaults(func=lambda a: report_colours(a.png))

    for sub in (image, text):
        common(sub)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
