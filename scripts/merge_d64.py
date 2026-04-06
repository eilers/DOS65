#!/usr/bin/env python3
"""
Merge two D64 images into one hybrid image, with collision detection.

Overlay source:
- C64 directory/BAM (track 18)
- all sectors referenced by C64 directory entries

Base image:
- CP/M disk with files already written

Collision detection:
- compare a freshly formatted CP/M image (--cpm-base) with the populated CP/M image (--cpm)
- any sector that differs is considered used by CP/M
- if a C64 overlay sector would overwrite such a sector with different bytes, abort

Usage:
    python3 merge_d64.py \
        --c64 c64_side.d64 \
        --cpm cpm_side.d64 \
        --cpm-base cpm_empty.d64 \
        --out hybrid.d64
"""

from __future__ import annotations

import argparse
import os
import sys
from typing import Dict, Iterable, List, Set, Tuple

SECTOR_SIZE = 256

SECTORS_PER_TRACK: List[int] = (
    [0] +
    [21] * 17 +
    [19] * 7 +
    [18] * 6 +
    [17] * 5
)

TOTAL_TRACKS = 35
TOTAL_SECTORS = sum(SECTORS_PER_TRACK[1:])
D64_SIZE = TOTAL_SECTORS * SECTOR_SIZE


class MergeError(Exception):
    pass


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


def all_ts() -> Iterable[Tuple[int, int]]:
    for track in range(1, TOTAL_TRACKS + 1):
        for sector in range(SECTORS_PER_TRACK[track]):
            yield (track, sector)


def iter_directory_entries(image: bytes):
    visited: Set[Tuple[int, int]] = set()
    track, sector = 18, 1

    while track != 0:
        if (track, sector) in visited:
            raise MergeError(f"directory loop detected at {track}/{sector}")
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


def collect_c64_overlay_sectors(c64_image: bytes) -> Set[Tuple[int, int]]:
    sectors = set()
    sectors |= collect_track_18()
    sectors |= collect_c64_file_sectors(c64_image)
    return sectors


def collect_cpm_used_sectors(cpm_base: bytes, cpm_populated: bytes) -> Set[Tuple[int, int]]:
    """
    Conservative CP/M allocation detection:
    every sector whose bytes changed after files were copied to the CP/M disk
    is considered used by CP/M content.
    """
    used: Set[Tuple[int, int]] = set()

    for track, sector in all_ts():
        base_sec = read_sector(cpm_base, track, sector)
        pop_sec = read_sector(cpm_populated, track, sector)
        if base_sec != pop_sec:
            used.add((track, sector))

    return used


def detect_collisions(
    c64_image: bytes,
    cpm_image: bytes,
    cpm_base: bytes,
    overlay_sectors: Set[Tuple[int, int]],
) -> List[Tuple[int, int]]:
    cpm_used = collect_cpm_used_sectors(cpm_base, cpm_image)
    collisions: List[Tuple[int, int]] = []

    for track, sector in sorted(overlay_sectors):
        if (track, sector) not in cpm_used:
            continue

        c64_sec = read_sector(c64_image, track, sector)
        cpm_sec = read_sector(cpm_image, track, sector)

        if c64_sec != cpm_sec:
            collisions.append((track, sector))

    return collisions


def merge_images(
    c64_image: bytes,
    cpm_image: bytes,
    cpm_base: bytes,
) -> Tuple[bytearray, Set[Tuple[int, int]]]:
    out = bytearray(cpm_image)

    overlay_sectors = collect_c64_overlay_sectors(c64_image)
    collisions = detect_collisions(c64_image, cpm_image, cpm_base, overlay_sectors)

    if collisions:
        lines = ", ".join(f"{t}/{s}" for t, s in collisions[:32])
        more = ""
        if len(collisions) > 32:
            more = f" ... (+{len(collisions) - 32} more)"
        raise MergeError(
            "C64 boot disk would overwrite CP/M program data in sectors: "
            f"{lines}{more}"
        )

    for track, sector in sorted(overlay_sectors):
        sec = read_sector(c64_image, track, sector)
        write_sector(out, track, sector, sec)

    return out, overlay_sectors


def main() -> int:
    parser = argparse.ArgumentParser(description="Merge C64 and CP/M D64 images")
    parser.add_argument("--c64", required=True, help="D64 image containing the C64 boot/program side")
    parser.add_argument("--cpm", required=True, help="D64 image containing the populated CP/M side")
    parser.add_argument("--cpm-base", required=True, help="freshly formatted empty CP/M D64 used for collision detection")
    parser.add_argument("--out", required=True, help="output merged D64 image")
    args = parser.parse_args()

    try:
        validate_d64(args.c64)
        validate_d64(args.cpm)
        validate_d64(args.cpm_base)

        with open(args.c64, "rb") as f:
            c64_image = f.read()
        with open(args.cpm, "rb") as f:
            cpm_image = f.read()
        with open(args.cpm_base, "rb") as f:
            cpm_base = f.read()

        merged, overlaid = merge_images(c64_image, cpm_image, cpm_base)

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