#!/usr/bin/env python3
"""Trim an MP3 by copying whole frames, without re-encoding.

An MP3 is a sequence of self-describing frames. Each frame header carries the
bitrate and sample rate, which gives its length in bytes and its duration, so a
file can be cut to a time range by copying the frames that fall inside it. No
decoder is involved and the audio is bit-identical to the source.

Used to cut the bundled storm recordings down to single claps: the app's own
strike locator reports where the thunder is, and this copies out that stretch.

Usage:
    python tool/trim_mp3.py <in.mp3> <out.mp3> <start_ms> <end_ms>
"""

import sys

# Bitrates in kbit/s, indexed by the header's 4-bit bitrate field.
BITRATES_MPEG1_L3 = [
    0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0,
]
BITRATES_MPEG2_L3 = [
    0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0,
]

SAMPLE_RATES = {
    3: [44100, 48000, 32000],   # MPEG1
    2: [22050, 24000, 16000],   # MPEG2
    0: [11025, 12000, 8000],    # MPEG2.5
}


def skip_id3(data):
    """Returns the offset of the first audio byte, stepping over any ID3v2 tag."""
    if data[:3] == b"ID3" and len(data) >= 10:
        # The size is stored as four 7-bit bytes.
        size = (
            (data[6] & 0x7F) << 21
            | (data[7] & 0x7F) << 14
            | (data[8] & 0x7F) << 7
            | (data[9] & 0x7F)
        )
        return 10 + size
    return 0


def parse_frame(data, offset):
    """Returns (length_bytes, duration_seconds) for the frame at offset, or None."""
    if offset + 4 > len(data):
        return None

    h = data[offset : offset + 4]
    if h[0] != 0xFF or (h[1] & 0xE0) != 0xE0:
        return None

    version_bits = (h[1] >> 3) & 0x03   # 3=MPEG1, 2=MPEG2, 0=MPEG2.5
    layer_bits = (h[1] >> 1) & 0x03     # 1 = Layer III
    bitrate_index = (h[2] >> 4) & 0x0F
    rate_index = (h[2] >> 2) & 0x03
    padding = (h[2] >> 1) & 0x01

    if version_bits == 1 or layer_bits != 1:
        return None
    if bitrate_index in (0, 15) or rate_index == 3:
        return None

    sample_rate = SAMPLE_RATES[version_bits][rate_index]

    if version_bits == 3:
        bitrate = BITRATES_MPEG1_L3[bitrate_index] * 1000
        samples = 1152
        length = 144 * bitrate // sample_rate + padding
    else:
        bitrate = BITRATES_MPEG2_L3[bitrate_index] * 1000
        samples = 576
        length = 72 * bitrate // sample_rate + padding

    if bitrate == 0 or length <= 4:
        return None

    return length, samples / sample_rate


def trim(src_path, dst_path, start_ms, end_ms, lead_frames=2):
    data = open(src_path, "rb").read()
    offset = skip_id3(data)

    start_s = start_ms / 1000.0
    end_s = end_ms / 1000.0

    frames = []          # (offset, length, start_time)
    elapsed = 0.0

    while offset < len(data):
        parsed = parse_frame(data, offset)
        if parsed is None:
            # Lost sync; hunt for the next frame rather than giving up, since
            # stray tags can appear mid-file.
            nxt = data.find(b"\xff", offset + 1)
            if nxt == -1:
                break
            offset = nxt
            continue

        length, duration = parsed
        frames.append((offset, length, elapsed))
        elapsed += duration
        offset += length

    if not frames:
        raise SystemExit(f"no MP3 frames found in {src_path}")

    keep = [f for f in frames if start_s <= f[2] < end_s]
    if not keep:
        raise SystemExit(
            f"no frames between {start_ms}ms and {end_ms}ms "
            f"(file is {elapsed:.1f}s)"
        )

    # MP3 frames can borrow bits from their predecessors, so a cut can leave the
    # first frame or two thin. Copying a couple of extra frames from before the
    # cut gives the decoder what it needs.
    first_index = frames.index(keep[0])
    lead = frames[max(0, first_index - lead_frames) : first_index]
    keep = lead + keep

    out = bytearray()
    for off, length, _ in keep:
        out += data[off : off + length]

    open(dst_path, "wb").write(out)

    kept_seconds = sum(
        parse_frame(data, off)[1] for off, _, _ in keep
    )
    print(
        f"{dst_path}: {len(keep)} frames, {kept_seconds:.2f}s, "
        f"{len(out) / 1024:.0f} KiB (source {elapsed:.1f}s)"
    )


if __name__ == "__main__":
    if len(sys.argv) != 5:
        raise SystemExit(__doc__)
    trim(sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]))
