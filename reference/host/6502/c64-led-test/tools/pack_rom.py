#!/usr/bin/env python3
"""Assemble a ROM image with a packed payload.

ld65 can't pack, so it links two files.  The head contains everything at its
real address and the payload contains CODE and RODATA at their RAM addresses.
The packed payload goes into the head after the boot block.

ld65 can't check the packed size against the socket, so this does.

The format is LZSS.  A flag byte covers the next eight items, lowest bit first.
A set bit is one literal byte.  A clear bit is a two byte match.  The first
byte is the low eight bits of the distance back less one.  The second has the
distance's top four bits in its high nibble and the length less three in its
low nibble.

Usage: pack_rom.py --head <file> --payload <file> --labels <file> --out <file>
"""
import argparse
import sys

MIN_MATCH = 3
MAX_MATCH = 18
MAX_DIST = 4096

LITERAL_BITS = 9                # the flag bit and the byte
MATCH_BITS = 17                 # the flag bit and the two bytes


def longest_matches(data):
    """Each position's longest match and its distance back."""
    chains = {}
    best = [(0, 0)] * len(data)
    for i in range(len(data)):
        if i + MIN_MATCH <= len(data):
            key = data[i:i + MIN_MATCH]
            found_len, found_dist = 0, 0
            for j in reversed(chains.get(key, ())):
                dist = i - j
                if dist > MAX_DIST:
                    break
                n = MIN_MATCH
                limit = min(MAX_MATCH, len(data) - i)
                while n < limit and data[j + n] == data[i + n]:
                    n += 1
                if n > found_len:
                    found_len, found_dist = n, dist
                    if n == limit:
                        break
            best[i] = (found_len, found_dist)
            chains.setdefault(key, []).append(i)
    return best


def pack(data):
    """Pack data into the shortest stream the format allows.

    A match costs the same whatever its distance, so the optimal parse comes
    from one backward pass over the bits needed to finish from each position.
    """
    best = longest_matches(data)
    n = len(data)
    cost = [0] * (n + 1)
    take = [0] * n                      # the match length used, or 0 for a literal
    for i in range(n - 1, -1, -1):
        cost[i] = LITERAL_BITS + cost[i + 1]
        found_len, _ = best[i]
        for length in range(MIN_MATCH, found_len + 1):
            here = MATCH_BITS + cost[i + length]
            if here < cost[i]:
                cost[i] = here
                take[i] = length

    out = bytearray()
    flags_at = None
    flag = 0
    bit = 0
    i = 0
    while i < n:
        if bit == 0:
            flags_at = len(out)
            out.append(0)
            flag = 0
        length = take[i]
        if length:
            dist = best[i][1] - 1
            out.append(dist & 0xFF)
            out.append((dist >> 8) << 4 | (length - MIN_MATCH))
            i += length
        else:
            flag |= 1 << bit
            out.append(data[i])
            i += 1
        out[flags_at] = flag
        bit = (bit + 1) & 7
    return bytes(out)


def unpack(stream, size):
    """boot.s's unpack, step for step, so each build checks the round trip."""
    out = bytearray()
    src = 0
    flags = 0
    left = 0
    while len(out) < size:
        if left == 0:
            flags = stream[src]
            src += 1
            left = 8
        left -= 1
        if flags & 1:
            out.append(stream[src])
            src += 1
        else:
            dist = stream[src] | (stream[src + 1] >> 4) << 8
            length = (stream[src + 1] & 0x0F) + MIN_MATCH
            src += 2
            at = len(out) - dist - 1
            for k in range(length):
                out.append(out[at + k])
        flags >>= 1
    return bytes(out)


def read_labels(path):
    """Symbol addresses from ld65's VICE label file."""
    labels = {}
    for line in open(path):
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "al":
            labels[parts[2].lstrip(".")] = int(parts[1], 16)
    return labels


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--head", required=True)
    ap.add_argument("--payload", required=True)
    ap.add_argument("--labels", required=True)
    ap.add_argument("-o", "--out", required=True)
    args = ap.parse_args()

    head = bytearray(open(args.head, "rb").read())
    payload = open(args.payload, "rb").read()
    labels = read_labels(args.labels)

    for name in ("__FILL_LOAD__", "__BOOT_LOAD__", "__BOOT_SIZE__",
                 "__CODE_SIZE__", "__RODATA_SIZE__"):
        if name not in labels:
            sys.exit("%s: %s isn't in it — the segment requires define = yes"
                     % (args.labels, name))

    base = labels["__FILL_LOAD__"]      # FILL is at file offset 0
    start = labels["__BOOT_LOAD__"] + labels["__BOOT_SIZE__"] - base
    want = labels["__CODE_SIZE__"] + labels["__RODATA_SIZE__"]
    if len(payload) != want:
        sys.exit("%s: %d bytes, but CODE and RODATA come to %d"
                 % (args.payload, len(payload), want))

    stream = pack(payload)
    if unpack(stream, len(payload)) != payload:
        sys.exit("%s: the packed payload does not come back the same" % args.out)

    # The stream must end before the vectors.
    end = labels.get("__VECTORS_LOAD__")
    end = len(head) if end is None else end - base
    over = start + len(stream) - end
    if over > 0:
        sys.exit("%s: the packed image overflows the socket by %d bytes"
                 % (args.out, over))

    head[start:start + len(stream)] = stream
    open(args.out, "wb").write(head)
    print("Output: %s (%d bytes, %d packed from %d, %d free)"
          % (args.out, len(head), len(stream), len(payload), end - start - len(stream)))


if __name__ == "__main__":
    main()
