"""Read-only access to CP/M files on Commodore disk images.

Supported layouts:
- C128 CP/M on 1541 (.d64, single sided) and 1571 (.d71, double sided):
  1 KB / 2 KB blocks on the zoned GCR (Group Coded Recording) tracks, sector
  mapping as in ctools (ctools/src/bios.cc).
- C128 CP/M on 1581 (.d81), also the DOS/65 1581 format, see d81.py.
- Raw CP/M images: the directory starts at offset 0, 2 KB blocks, block n
  at offset n * 2048.

Images may be gzip compressed (.gz).
"""

from __future__ import annotations

import gzip
from dataclasses import dataclass
from pathlib import Path

from . import d81

SECTOR = 256
D64_SIZE = 683 * SECTOR
D71_SIZE = 2 * D64_SIZE


def _sectors_per_track(track: int) -> int:
    track = (track - 1) % 35 + 1
    return 21 if track <= 17 else 19 if track <= 24 else 18 if track <= 30 else 17


def _d64_offset(track: int, sector: int) -> int:
    return (sum(_sectors_per_track(t) for t in range(1, track)) + sector) * SECTOR


def _c128_ss(nr: int) -> tuple[int, int]:
    zones = ((1, 21, 357, 2), (18, 19, 133, 1), (25, 18, 108, 0), (31, 17, 85, 0))
    if nr >= 680:
        raise ValueError(f"sector {nr} beyond the disk")
    for first, per_track, size, reserved in zones:
        nr += reserved
        if nr < size:
            return first + nr // per_track, (5 * nr) % per_track
        nr -= size
    raise ValueError(f"sector {nr} beyond the disk")


def _c128_ds(nr: int) -> tuple[int, int]:
    if nr < 680:
        return _c128_ss(nr)
    track, sector = _c128_ss(nr - 680)
    return track + 35, sector


@dataclass
class Layout:
    name: str
    block_size: int
    dir_entries: int
    wide_pointers: bool        # 16 bit block numbers (8 per directory entry)


class CpmImage:
    def __init__(self, data: bytes):
        self.data = data
        self._read_block = None
        if d81.is_cpm_1581(data):
            self.layout = Layout("c128-1581", d81.BLOCK, d81.DIR_ENTRIES, True)
            self._translate = None
            self._read_block = lambda number: d81.read_block(self.data, number)
        elif len(data) in (D71_SIZE, D71_SIZE + 1366) and data[_d64_offset(1, 0):][:3] == b"CBM":
            self.layout = Layout("c128-1571", 2048, 128, False)
            self._translate = _c128_ds
        elif len(data) in (D64_SIZE, D64_SIZE + 683) and data[_d64_offset(1, 0):][:3] == b"CBM":
            self.layout = Layout("c128-1541", 1024, 64, False)
            self._translate = _c128_ss
        else:
            self.layout = Layout("raw", 2048, self._raw_dir_entries(), True)
            self._translate = None

    @classmethod
    def open(cls, path: str | Path) -> "CpmImage":
        raw = Path(path).read_bytes()
        if raw[:2] == b"\x1f\x8b":
            raw = gzip.decompress(raw)
        return cls(raw)

    def _raw_dir_entries(self) -> int:
        """Directory entries up to the first block used by a file."""
        first_block = None
        count = 0
        while count * 32 < len(self.data):
            entry = self.data[count * 32:count * 32 + 32]
            if entry[0] <= 15:
                blocks = [entry[16 + 2 * i] | entry[17 + 2 * i] << 8 for i in range(8)]
                used = [b for b in blocks if b]
                if used:
                    low = min(used)
                    first_block = low if first_block is None else min(first_block, low)
            count += 1
            if first_block is not None and count * 32 >= first_block * 2048:
                break
            if count >= 2048:
                break
        return count

    def block(self, number: int) -> bytes:
        size = self.layout.block_size
        if self._read_block is not None:
            return self._read_block(number)
        if self._translate is None:
            return self.data[number * size:(number + 1) * size]
        per_block = size // SECTOR
        out = bytearray()
        for i in range(per_block):
            track, sector = self._translate(number * per_block + i)
            off = _d64_offset(track, sector)
            out += self.data[off:off + SECTOR]
        return bytes(out)

    def _directory(self) -> bytes:
        size = self.layout.dir_entries * 32
        blocks = (size + self.layout.block_size - 1) // self.layout.block_size
        return b"".join(self.block(n) for n in range(blocks))[:size]

    def entries(self) -> list[tuple[int, str, int, int, list[int]]]:
        """(user, name, extent, records, blocks) of all used directory entries."""
        result = []
        directory = self._directory()
        for i in range(0, len(directory), 32):
            e = directory[i:i + 32]
            if e[0] > 15:
                continue
            name = bytes(c & 0x7F for c in e[1:9]).decode("ascii").rstrip()
            ext = bytes(c & 0x7F for c in e[9:12]).decode("ascii").rstrip()
            if self.layout.wide_pointers:
                blocks = [e[16 + 2 * k] | e[17 + 2 * k] << 8 for k in range(8)]
            else:
                blocks = list(e[16:32])
            extent = e[12] + 32 * e[14]
            result.append((e[0], f"{name}.{ext}" if ext else name, extent, e[15],
                           [b for b in blocks if b]))
        return result

    def files(self, user: int = 0) -> list[str]:
        return sorted({name for u, name, *_ in self.entries() if u == user})

    def read(self, name: str, user: int = 0) -> bytes:
        name = name.upper()
        parts = sorted((ext, rec, blocks) for u, n, ext, rec, blocks in self.entries()
                       if u == user and n == name)
        if not parts:
            raise FileNotFoundError(name)
        records_per_block = self.layout.block_size // 128
        logical_per_entry = 8 if self.layout.wide_pointers else 16
        extents_per_entry = logical_per_entry * records_per_block // 128 or 1
        out = bytearray()
        last_ext, last_rec, _ = parts[-1]
        for ext, rec, blocks in parts:
            data = b"".join(self.block(b) for b in blocks)
            out[(ext // extents_per_entry) * 128 * 128 * extents_per_entry:] = data
        total = (last_ext % extents_per_entry) * 128 + last_rec
        total += (last_ext // extents_per_entry) * 128 * extents_per_entry
        return bytes(out[:total * 128])
