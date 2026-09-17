#!/usr/bin/env python3
"""Synthesise the boot chime as a sample Paula can play.

Two struck bell notes, D4 then A4 a fifth above it, the second hit while the
first is still ringing, so the pair lands as a chord.  Each note is a
fundamental with four partials, the higher ones quieter and dying away faster,
which is what makes a struck thing sound struck rather than blown.  On top of
each hit sits a burst of inharmonic partials lasting about ten milliseconds,
the knock of the hammer.  Everything decays exponentially and the whole sample
is taken to silence by a raised cosine over the last stretch.

Paula wants 8-bit signed mono, an even number of bytes, word aligned, in chip
RAM.  Playback repeats for as long as the channel's DMA is on, so a one-shot
chime means starting the channel, waiting CHIME_MS, and stopping it.  The
sample ends in silence, so the wait can overrun a little without a click.

Writes two files: the raw sample, and an assembler source with the lengths,
the period values and an INCBIN of the raw sample.  The INCBIN path written
into the assembler source is the binary's path exactly as given on the command
line, because vasm resolves it against the directory the assembler runs in.
Run this from that directory, or pass --incbin.

    mkchime.py assets/chime.bin assets/chime.s [--wav <file>]

The optional .wav is for listening and for checking the result outside the
Amiga.  It is not part of the build.
"""
import argparse
import math
import struct
import sys
import wave

# Paula's sample clock.  rate = clock / period, and the period register is
# 9 bits, so 124 is the lowest period that is safe to use on all machines.
PAL_CLOCK = 3546895
NTSC_CLOCK = 3579545

# Chosen for a PAL A500.  3546895 / 250 = 14187.58 Hz, which leaves the fourth
# partial of the upper note well inside Nyquist and keeps half a second under
# eight kilobytes.
PERIOD_PAL = 250
RATE = PAL_CLOCK / PERIOD_PAL

DURATION = 0.50

# Peak sample value.  Short of 127 so that rounding cannot clip and so the
# mixed pair has a little headroom.
PEAK = 120

# Decay time constant of each note's fundamental, in seconds.
TAU = 0.135

# Onset time constant.  Fast enough to sound struck, slow enough that the first
# few samples do not step.
ATTACK = 0.0012

# The whole sample is faded out over this long at the end, so the last sample
# is zero and stopping the channel cannot pop.
RELEASE = 0.070

# (start second, frequency Hz, level).  D4 and A4, a rising perfect fifth.
NOTES = (
    (0.000, 293.665, 1.00),
    (0.130, 440.000, 0.90),
)

# (frequency ratio, level, how much faster than the fundamental it decays).
# The fourth and fifth are stretched off the harmonic series a little, which
# is what gives a bell its shimmer.
PARTIALS = (
    (1.000, 1.000, 1.00),
    (2.000, 0.400, 1.55),
    (3.000, 0.200, 2.10),
    (4.013, 0.100, 2.80),
    (5.432, 0.050, 3.60),
)

# The hammer knock.  (frequency ratio, level), all decaying with STRIKE_TAU.
STRIKE = ((6.81, 0.10), (9.23, 0.07), (11.71, 0.05))
STRIKE_TAU = 0.010

TWO_PI = 2.0 * math.pi


def synthesise(rate, count):
    """Return `count` floating point samples of the chime, unnormalised."""
    out = [0.0] * count
    for start, freq, level in NOTES:
        first = int(start * rate)
        for i in range(first, count):
            t = (i - first) / rate
            env = level * (1.0 - math.exp(-t / ATTACK))
            total = 0.0
            for ratio, amp, fade in PARTIALS:
                total += amp * math.exp(-t * fade / TAU) * math.sin(
                    TWO_PI * freq * ratio * t)
            knock = math.exp(-t / STRIKE_TAU)
            for ratio, amp in STRIKE:
                total += amp * knock * math.sin(TWO_PI * freq * ratio * t)
            out[i] += env * total
    return out


def shape(samples, rate):
    """Fade the tail to zero and scale the result to PEAK."""
    count = len(samples)
    fade_from = count - int(RELEASE * rate)
    if not 0 < fade_from < count:
        sys.exit("mkchime: RELEASE must be more than zero and shorter than "
                 "DURATION")
    for i in range(fade_from, count):
        x = (i - fade_from) / (count - fade_from)
        samples[i] *= 0.5 * (1.0 + math.cos(math.pi * x))

    top = max(abs(s) for s in samples)
    if top == 0.0:
        sys.exit("mkchime: the synthesised chime is silent")
    scale = PEAK / top
    return [s * scale for s in samples]


def quantise(samples):
    """Round to 8-bit signed, kept symmetric by clamping at -127 not -128."""
    out = bytearray()
    for s in samples:
        v = int(round(s))
        v = max(-127, min(127, v))
        out += struct.pack("b", v)
    return bytes(out)


def check(data, rate):
    """Verify the sample is playable without a click, and return its numbers."""
    def rms(block):
        return math.sqrt(sum(v * v for v in block) / len(block))

    values = list(struct.unpack("%db" % len(data), data))
    peak = max(abs(v) for v in values)
    mean = sum(values) / len(values)
    tail_rms = rms(values[-int(0.020 * rate):])

    # How loud the chime still is where the release fade takes over.  If the
    # notes are still ringing here the fade itself is audible as a chop.
    onset = len(values) - int(RELEASE * rate)
    release_rms = rms(values[onset:onset + int(0.010 * rate)])

    if len(data) % 2:
        sys.exit("mkchime: odd byte count, Paula needs whole words")
    # quantise() clamps, so a sample sitting on the rail is one that was
    # clipped on the way in.  Correctly scaled, nothing reaches PEAK, let
    # alone 127.
    if peak >= 127:
        sys.exit("mkchime: clipped, %d samples on the rail — lower PEAK"
                 % sum(1 for v in values if abs(v) >= 127))
    if peak < 100:
        sys.exit("mkchime: peak %d is too quiet to be worth playing" % peak)
    if values[0] != 0 or values[-1] != 0:
        sys.exit("mkchime: sample does not start and end at zero, it will pop")
    if tail_rms > 2.0:
        sys.exit("mkchime: the tail has not decayed, stopping DMA will click")
    if release_rms > 0.2 * peak:
        sys.exit("mkchime: still ringing at %.1f when the fade starts, so the "
                 "fade will be heard — shorten TAU or lengthen DURATION"
                 % release_rms)

    return {
        "peak": peak,
        "first": values[0],
        "last": values[-1],
        "tail_rms": tail_rms,
        "release_rms": release_rms,
        "mean": mean,
        "max_step": max(abs(values[i + 1] - values[i])
                        for i in range(len(values) - 1)),
    }


ASM = """\
; {name} — boot chime sample for Paula
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Generated by tools/mkchime.py.  Edit the generator, not this file.
;
; 8-bit signed mono, {rate:.1f} Hz on a PAL machine.  Paula reads the sample
; over DMA, so the bytes have to be in chip RAM and word aligned — copy
; CHIME_LEN_BYTES from ChimeData to a chip RAM buffer, point the channel at the
; copy, and write CHIME_LEN_WORDS to the channel's length register.
;
; DMA repeats the sample for as long as the channel is on.  One chime is
; start, wait CHIME_MS, stop.  The sample ends in silence, so a wait that
; overruns by a frame or two makes no sound.
; ---------------------------------------------------------------------------

CHIME_LEN_WORDS     EQU {words}         ; channel length register
CHIME_LEN_BYTES     EQU {size}         ; bytes to copy into chip RAM
CHIME_PERIOD        EQU {period_pal}          ; PAL, {rate:.1f} Hz
CHIME_PERIOD_NTSC   EQU {period_ntsc}          ; NTSC, same pitch
CHIME_MS            EQU {ms}          ; play time, about {frames} PAL frames

                    CNOP    0,2
ChimeData:
                    INCBIN  "{incbin}"
ChimeDataEnd:
"""


def write_wav(path, data):
    """Write the same waveform as a .wav.  8-bit wav samples are unsigned."""
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(int(round(RATE)))
        w.writeframes(bytes((b + 128) & 0xFF for b in data))


def main():
    ap = argparse.ArgumentParser(description="Generate the Amiga boot chime.")
    ap.add_argument("binary", help="raw 8-bit signed sample to write")
    ap.add_argument("source", help="assembler source to write")
    ap.add_argument("--incbin", help="INCBIN path to write into the source, "
                                     "if not the binary path as given")
    ap.add_argument("--wav", help="also write the waveform as a .wav")
    args = ap.parse_args()

    count = int(RATE * DURATION)
    count += count % 2

    data = quantise(shape(synthesise(RATE, count), RATE))
    numbers = check(data, RATE)

    with open(args.binary, "wb") as f:
        f.write(data)

    ms = 1000.0 * len(data) / RATE
    with open(args.source, "w") as f:
        f.write(ASM.format(
            name=args.source.rsplit("/", 1)[-1],
            rate=RATE,
            words=len(data) // 2,
            size=len(data),
            period_pal=PERIOD_PAL,
            period_ntsc=int(round(NTSC_CLOCK / RATE)),
            ms=int(math.ceil(ms)),
            frames=int(round(ms / 20.0)),
            incbin=args.incbin or args.binary,
        ))

    if args.wav:
        write_wav(args.wav, data)

    print("%s: %d bytes, %d words, %.1f Hz, %.1f ms"
          % (args.binary, len(data), len(data) // 2, RATE, ms))
    print("peak %d of 127, first %d, last %d, mean %.2f, largest step %d"
          % (numbers["peak"], numbers["first"], numbers["last"],
             numbers["mean"], numbers["max_step"]))
    print("level where the fade starts %.1f, last 20 ms RMS %.3f"
          % (numbers["release_rms"], numbers["tail_rms"]))


if __name__ == "__main__":
    main()
