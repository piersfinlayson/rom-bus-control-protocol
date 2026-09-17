# Asset generators

Offline tools that turn artwork into data the bootloader can assemble. They run
on a workstation, not on the Amiga, and are only needed when an asset changes.
The files they write into `../assets/` are checked in, so an ordinary build does
not run them.

| Tool | Writes | Needs |
| --- | --- | --- |
| `mkimage.py` | the logo and the tagline | Pillow |
| `mkball.py` | the bouncing ball | nothing |
| `mkchime.py` | the boot chime | nothing |
| `mkpointer.py` | the mouse pointer sprite | nothing |

Install Pillow with `pip install pillow`, in a virtual environment if the
system Python is managed.

Every object except the pointer is written in the same shape: four bitplanes
interleaved a pixel row at a time, one blank word on the right of each row for
the blitter's barrel shifter, and a single-plane mask beside it. One blit draws
all four planes. The pointer is a hardware sprite and has its own format.

The screen has 16 pens, shared out so the objects can sit on one another:

| Pens | Used by |
| --- | --- |
| 0 | background, and transparent in every object |
| 1 | text |
| 2 | One ROM gold, the ring and the tagline |
| 3, 4, 5 | the logo's outlines, chip body and pins |
| 6-13 | the ball's surface, cycled to spin it |
| 14 | the ball's drop shadow |
| 15 | spare |

Changing a pen means regenerating every asset that uses it.

## mkimage.py

Converts a PNG, or a line of TrueType text, into a blitter object for the
16-colour lores screen: four bitplanes interleaved a pixel row at a time, a
single-plane mask, and a vasm source file that declares the sizes and pulls the
binaries in with `INCBIN`.

Interleaving is what makes the object cheap to draw. Plane 0's words for a row
are followed by plane 1's, 2's and 3's, then the next row, so one blit of
`<NAME>_BLIT_ROWS` rows copies all four planes in a single pass. Every row
carries one extra blank word on the right, which gives the barrel shifter
somewhere to push the last pixels into and lets the object land on any
horizontal pixel, not just a word boundary. Words are big-endian.

The mask is 1 where the object is opaque and 0 where the background shows
through. It comes from the source alpha, so a black outline inside the artwork
stays opaque and covers whatever is behind it rather than letting it leak
through.

### Needs

- Python 3
- [Pillow](https://pypi.org/project/Pillow/) — `pip install pillow`

Every input is an argument. The tool has no built-in paths and no default
artwork.

### Pens

`--pen N=RRGGBB` allows pen `N` and says what colour it shows. Repeat it once
per pen. Colours are reduced to the 4 bits per gun the hardware displays before
anything is matched against them, so what the preview shows is what the Amiga
shows. The generated `.s` carries each one as a `$0RGB` EQU.

Pen 0 is the background and is black unless given otherwise. Only the pens
named on the command line can appear in the output — every source colour is
snapped to the nearest of them.

### Colours in a source image

`colours` lists what is actually in a PNG, so the pen mapping can be chosen from
the file rather than guessed:

```
./mkimage.py colours path/to/artwork.png
```

### Converting an image

Run from the `amiga-boot` directory, so `--incbin-dir` matches the path the
assembler will see:

```
./mkimage.py image path/to/artwork.png \
    --width 112 --trim \
    --name logo --out assets --incbin-dir assets \
    --title "One ROM logo, a blitter object" \
    --preview /tmp/logo.png \
    --pen-coverage 5=0.15 \
    --pen 0=000000 --pen 2=FFB700 --pen 3=111111 \
    --pen 4=333333 --pen 5=DDDDDD
```

`--width` is the object in pixels and must be a multiple of 16. The margin word
is added on top of it. Height keeps the aspect ratio unless `--height` overrides
it. `--trim` crops to the opaque bounding box first.

The image is area-averaged down and each output pixel then snapped to the
nearest allowed pen. Averaging matters at large reductions: point sampling drops
thin features such as pin legs in and out from row to row and the result breaks
up into speckle.

### Thin light features, and --pen-coverage

Averaging has one failure of its own. A feature only a source pixel or two
wide, on a ground much darker than itself, is averaged with that ground before
any pen is chosen, so it arrives at the snap already dragged most of the way to
the background and is snapped to a dark pen. The logo's pin legs are exactly
this: at 112 pixels the chip's far row of legs is under one source pixel wide,
and plain averaging filled them with chip-body grey instead of pin white.

`--pen-coverage N=FRACTION` measures the feature rather than the average.
Every source pixel close enough to pen `N`'s own colour counts 1 and everything
else counts 0, and the reduction gives the fraction of each output pixel those
covered. "Close enough" is half the distance to the nearest other allowed pen,
on the widest channel, so a source pixel counts towards the pen it would have
been snapped to anyway and towards no other.

Pen `N` then holds a pixel when two things are true: its coverage reaches
`FRACTION`, **and** no other pen covers more of that pixel. The second test is
the one that matters. Without it a sliver of a light feature captures a pixel
that is almost entirely the black outline beside it, and the outline vanishes —
a drawn pin becomes a bare stroke. With it, a pen can only take a pixel it
genuinely dominates, so an outline thick enough to own a pixel keeps it. The
fraction is then a floor for the case where nothing much covers the pixel at
all.

Coverage is measured for every pen once any rule is given, because the second
test needs something to compare against. A pixel the rule claims is opaque in
the mask, because the feature is really there.

Repeat the option per pen. The rule only ever hands pixels to the pens named,
so it cannot thicken an outline or fill a gap in some other colour — check the
pen tally the tool prints, and look at the preview.

`5=0.15` is what the logo uses. Against the same conversion with no rule at
all it moves 43 pixels of the 10,304, every one of them from chip-body grey to
pin white. No pen 0 or pen 3 pixel changes, so no outline can have been lost,
and the mask comes out byte for byte the same.

### Setting text

```
./mkimage.py text path/to/Font.ttf \
    --text 'One ROM\nto rule them all' \
    --max-width 160 \
    --name tagline --out assets --incbin-dir assets \
    --title "the tagline, a blitter object" \
    --preview /tmp/tagline.png \
    --pen 0=000000 --pen 2=FFB700
```

`\n` starts a new line and lines are centred on each other. Without `--size` the
tool takes the largest whole point size whose widest line still fits
`--max-width`. Glyphs are rendered four times too large and reduced, then cut to
one bit at `--threshold` — lower thickens the strokes, higher thins them.

All four planes are written whatever the text uses, so the blit is the same
shape as every other object on the screen.

### A pen for some of the characters

With one pen besides pen 0, that pen sets the text and there is nothing to
choose. Allow more and two options share them out:

- `--text-pen N` — the pen for every character no span covers. Required as
  soon as more than one ink pen is allowed, so the default is never a guess.
- `--pen-span N=START[:COUNT]` — `COUNT` characters from index `START` in pen
  `N`, counting from 0 through `--text` exactly as written. `COUNT` defaults to
  1. Repeatable, and a later span wins where two overlap.

The heading uses this to pick out one letter:

```
./mkimage.py text path/to/Font.ttf \
    --text 'One ROM to rule them all' \
    --max-width 288 \
    --name tagline_wide --out assets --incbin-dir assets \
    --title "the tagline on one line, a blitter object" \
    --preview /tmp/tagline_wide.png \
    --pen 0=000000 --pen 2=FFB700 --pen 5=DDDDDD \
    --text-pen 5 --pen-span 2=5:1
```

Read `--pen-span 2=5:1` as pen 2, one character, starting at index 5. The 5
before the `=` is a pen and the 5 after it is a character position — they are
unrelated, and the pen the rest of the text uses happens to be 5 as well.

Index 5 is the `O` of `ROM`. Index 0 is the `O` of `One`, which stays with the
default pen. The tool prints which characters each pen took, so a miscounted
index shows up before the preview does.

The text is on pen 5 rather than pen 1 because pen 1 is `$0FFF` and so are the
ball's light checks, which would swallow the text whenever the ball passed
behind it. Pen 5 is `$0DDD`, which still reads as white and stays separate from
the ball.

A span may not name pen 0, and may not cover a line break. An index outside the
text is refused rather than clamped.

Colouring a character moves nothing. Each line is drawn as one whole string,
exactly as it would be if every character shared a pen, and the finished bitmap
is then shared out by column: the pixels between where the string layout left
the pen before a character and where it left it after belong to that character.
The spacing, kerning and baseline are therefore the single-colour ones by
construction, not by approximation.

### Checking the result

`--preview` writes a PNG decoded back out of the packed bitplanes, not out of
the intermediate image, so it shows what the hardware will actually display.
Look at it before believing a conversion.

### Output

For `--name foo --out assets`:

| File | Contents |
| --- | --- |
| `foo.bin` | interleaved bitplane data |
| `foo_mask.bin` | single-plane mask |
| `foo.s` | size and colour EQUs, and the two `INCBIN`s |

`foo.s` defines `FOO_WIDTH_W`, `FOO_WIDTH_PX`, `FOO_HEIGHT`, `FOO_PLANES`,
`FOO_ROW_BYTES`, `FOO_ROW_STRIDE`, `FOO_BYTES`, `FOO_MASK_BYTES`,
`FOO_BLIT_ROWS` and one `FOO_PENn` per pen, and labels the data `FooData` /
`FooDataEnd` and the mask `FooMask` / `FooMaskEnd`.

A missing input file is reported by name and the tool exits non-zero.

## mkball.py

Draws the Boing-style ball as a blitter object that spins by cycling its colour
registers rather than by storing animation frames.

```
python3 tools/mkball.py assets/ball.bin assets/ball_mask.bin assets/ball.s
```

64x64, eight checks around the sphere, six rows of latitude, the axis leaning
17 degrees. Band edges are taken from the sphere's own geometry, so the checks
compress towards both silhouette edges and the ball reads as a sphere rather
than a rolling cylinder.

`BallCycle` holds eight rows of eight `$0RGB` words. Writing one row to COLOR06
upwards turns the ball 11.25 degrees. Eight rows take it round 90 degrees and
leave the registers as they started, so the table loops. Only longitude turns —
the latitude rows belong to the bitmap and stay put.

The checks are One ROM gold `$0FB0` against white, the same gold as the ring
and the tagline. `--colours ONE TWO` changes them, as `RGB` or `RRGGBB` hex.
Six digits are rounded to the four bits a gun has before anything is written,
so `FFB700` and `FB0` are the same colour on screen and the tool prints what it
used. The bitmaps hold pen numbers rather than colours, so a recolour rewrites
only `BallCycle` and leaves `ball.bin` and `ball_mask.bin` byte for byte as
they were.

Gold against white carries less than half the luminance difference red against
white did, so the checks are softer, most so on a composite or RF display where
the colour smears sideways and the luma barely steps. They still read, because
a check is about 16 pixels across with a hard edge. A darker gold such as
`--colours E90 FFF` puts the bite back at the cost of no longer matching the
ring.

`--preview <file.png>` writes a strip of all eight steps.

## mkchime.py

Synthesises the boot chime Paula plays.

```
python3 tools/mkchime.py assets/chime.bin assets/chime.s
```

Two struck bell notes, D4 then A4, the second hit at 130 ms while the first is
still ringing, so the pair lands as a chord. The partials of each note are
pulled off the harmonic series at the top end, which is what gives a bell its
shimmer, and the upper ones die away faster than the fundamental, which is
what makes it sound struck rather than blown. A short inharmonic knock on each
hit is the hammer. 500 ms, 8-bit signed mono at 14187.6 Hz. 7094 bytes.

`assets/chime.s` carries `CHIME_LEN_WORDS`, `CHIME_LEN_BYTES`, `CHIME_PERIOD`,
`CHIME_PERIOD_NTSC` and `CHIME_MS`. Paula reads over DMA, so the caller copies
the sample to a word aligned chip RAM buffer before starting the channel. DMA
repeats the sample, so one chime is start, wait `CHIME_MS`, stop. The sample
ends in silence, so overrunning the wait makes no sound.

The tool refuses to write a sample that clips, that does not start and end at
zero, or whose tail has not decayed before the fade. `--wav <file>` also writes
the waveform for listening.

## mkpointer.py

Generates the mouse pointer.

```
python3 tools/mkpointer.py assets/pointer.s
```

This one is a hardware sprite, not a blitter object: 16 pixels wide, two
control words, then two words a row — one per sprite bitplane — then two zero
words. Pixel values 1 to 3 pick COLOR17, COLOR18 and COLOR19, and 0 is
transparent. The control words carry the position and are rewritten as the
pointer moves, so the generated ones are zero.

The shape is an ASCII drawing at the top of the tool, `.` transparent, `1`
outline and `2` fill. Edit it there. The tool rejects a row that is not 16
characters or that uses anything else.

There is no binary and no mask — the whole sprite is `dc.w` in the `.s`, with
each row's drawing in the comment beside it.
