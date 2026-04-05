#!/usr/bin/env python3
"""
Merge two D64 images into one hybrid image:

- C64 side:
  * directory/BAM from the C64 image
  * all sectors referenced by C64 directory entries

- CP/M side:
  * everything else stays from the CP/M image

This assumes the CP/M formatter/layout leaves the C64-visible sectors
(track 18 + C64 file chains) available for overlay.

Usage:
    python3 merge_d64.py --c64 c64_side.d64 --cpm cpm_side.d64 --out hybrid.d64
"""

from __future__ import annotations

import argparse
import os
import sys
from typing import List, Set, Tuple

SECTOR_SIZE = 256

# Standard 35-track D64 layout
SECTORS_PER_TRACK: List[int] = (
    [0] +                 # dummy for 1-based track indexing
    [21] * 17 +           # tracks 1-17
    [19] * 7 +            # tracks 18-24
    [18] * 6 +            # tracks 25-30
    [17] * 5              # tracks 31-35
)

TOTAL_TRACKS = 35
TOTAL_SECTORS = sum(SECTORS_PER_TRACK[1:])
D64_SIZE = TOTAL_SECTORS * SECTOR_SIZE


def ts_to_index(track: int, sector: int) -> int:
    if track < 1 or track > TOTAL_TRACKS:
        raise ValueError(f"invalid track {track}")
    max_sector = SECTORS_PER_TRACK[track]
    if sector < 0 or sector >= max_sector:
        raise ValueError(f"invalid sector {track}/{sector}")
    return sum(SECTORS_PER_TRACK[1:track]) + sector


def ts_to_offset(track: int, sector: int) -> int:
    return ts_to_index(track, sector) * SECTOR_SIZE


def read_sector(image: bytes, track: int, sector: int) -> bytes:
    off = ts_to_offset(track, sector)
    return image[off:off + SECTOR_SIZE]


def write_sector(image: bytearray, track: int, sector: int, data: bytes) -> None:
    if len(data) != SECTOR_SIZE:
        raise ValueError("sector data must be exactly 256 bytes")
    off = ts_to_offset(track, sector)
    image[off:off + SECTOR_SIZE] = data


def validate_d64(path: str) -> None:
    size = os.path.getsize(path)
    if size != D64_SIZE:
        raise ValueError(
            f"{path}: unsupported size {size} bytes "
            f"(expected standard 35-track D64: {D64_SIZE} bytes)"
        )


def iter_directory_entries(image: bytes):
    """
    Iterate all active directory entries.

    Directory starts at 18/1 and is chained sector-by-sector:
      byte 0 = next dir track
      byte 1 = next dir sector
      entries from offset 2, every 32 bytes
    """
    visited: Set[Tuple[int, int]] = set()
    track, sector = 18, 1

    while track != 0:
        if (track, sector) in visited:
            raise RuntimeError(f"directory loop detected at {track}/{sector}")
        visited.add((track, sector))

        sec = read_sector(image, track, sector)
        next_track = sec[0]
        next_sector = sec[1]

        for entry_off in range(2, SECTOR_SIZE, 32):
            entry = sec[entry_off:entry_off + 32]
            file_type = entry[0]

            # 0x00 = unused
            if file_type == 0x00:
                continue

            # Commodore DOS: low 3 bits are file type, 0 means DEL
            # If type nibble is 0, ignore as deleted/unused-ish entry.
            if (file_type & 0x07) == 0:
                continue

            start_track = entry[1]
            start_sector = entry[2]

            if start_track == 0:
                continue

            yield {
                "dir_ts": (track, sector),
                "entry_offset": entry_off,
                "file_type": file_type,
                "start_ts": (start_track, start_sector),
                "raw": entry,
            }

        track, sector = next_track, next_sector


def collect_c64_file_sectors(image: bytes) -> Set[Tuple[int, int]]:
    """
    Follow all file chains referenced by directory entries.
    """
    used: Set[Tuple[int, int]] = set()

    for entry in iter_directory_entries(image):
        track, sector = entry["start_ts"]

        while track != 0:
            ts = (track, sector)
            if ts in used:
                # A sector was already seen. This can happen with malformed
                # images or deliberate overlap tricks. Stop following this chain.
                break

            used.add(ts)
            sec = read_sector(image, track, sector)
            next_track = sec[0]
            next_sector = sec[1]

            if next_track == 0:
                # last sector
                break

            track, sector = next_track, next_sector

    return used


def collect_track_18() -> Set[Tuple[int, int]]:
    return {(18, s) for s in range(SECTORS_PER_TRACK[18])}


def merge_images(c64_image: bytes, cpm_image: bytes) -> Tuple[bytearray, Set[Tuple[int, int]]]:
    out = bytearray(cpm_image)

    sectors_to_overlay = set()
    sectors_to_overlay |= collect_track_18()
    sectors_to_overlay |= collect_c64_file_sectors(c64_image)

    for track, sector in sorted(sectors_to_overlay):
        sec = read_sector(c64_image, track, sector)
        write_sector(out, track, sector, sec)

    return out, sectors_to_overlay


def main() -> int:
    parser = argparse.ArgumentParser(description="Merge C64 and CP/M D64 images")
    parser.add_argument("--c64", required=True, help="D64 image containing the C64 boot/program side")
    parser.add_argument("--cpm", required=True, help="D64 image containing the CP/M side")
    parser.add_argument("--out", required=True, help="Output merged D64 image")
    args = parser.parse_args()

    try:
        validate_d64(args.c64)
        validate_d64(args.cpm)

        with open(args.c64, "rb") as f:
            c64_image = f.read()
        with open(args.cpm, "rb") as f:
            cpm_image = f.read()

        merged, overlaid = merge_images(c64_image, cpm_image)

        with open(args.out, "wb") as f:
            f.write(merged)

        print(f"[OK] wrote {args.out}")
        print(f"[OK] overlaid {len(overlaid)} sectors from C64 image onto CP/M image")
        return 0

    except Exception as e:
        print(f"[ERROR] {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())