"""The C128 CP/M 1581 disk format (.d81), which the MEGA65 SIM 1.01 reads.

A .d81 image holds 80 tracks of 40 sectors with 256 bytes each. The first
20 sectors of track 40 carry the CBM (Commodore DOS) header, BAM (block
availability map) and directory; CP/M leaves them alone. Everything else is
CP/M data in plain sector order, starting at track 1 sector 0.

The disk parameters come from the C128 CP/M BIOS (CPM+.SYS): 40 records of
128 bytes per track, that is one half of a 1581 track, no system tracks,
2 KB blocks, highest block 396, 128 directory entries in blocks 0 and 1.
Half track 78 is the CBM half of track 40, so CP/M track t is half track t,
and from track 78 on half track t + 1. Block numbers are 16 bits wide, so a
directory entry maps 8 blocks, one 16 KB extent.
"""

from __future__ import annotations

TRACKS = 80
SECTORS = 40
SECTOR = 256
SIZE = TRACKS * SECTORS * SECTOR
CBM_TRACK = 40
CBM_HALF_TRACK = (CBM_TRACK - 1) * 2

RECORD = 128
RECORDS_PER_TRACK = 40
CPM_TRACKS = TRACKS * 2 - 1
BLOCK = 2048
RECORDS_PER_BLOCK = BLOCK // RECORD
BLOCKS = 397
DIR_ENTRIES = 128
DIR_BLOCKS = DIR_ENTRIES * 32 // BLOCK
BLOCKS_PER_ENTRY = 8
EXTENT_RECORDS = 128


def sector_offset(track: int, sector: int) -> int:
    """Byte offset of a 1581 sector; tracks count from 1, sectors from 0."""
    if not (1 <= track <= TRACKS and 0 <= sector < SECTORS):
        raise ValueError(f"track {track} sector {sector} is not on a 1581 disk")
    return ((track - 1) * SECTORS + sector) * SECTOR


def physical(track: int, sector: int) -> tuple[int, int]:
    """1581 track and sector of CP/M track `track`, host sector 0-19."""
    half = track + 1 if track >= CBM_HALF_TRACK else track
    return half // 2 + 1, (half % 2) * 20 + sector


def record_offset(record: int) -> int:
    """Byte offset of a CP/M record, counted from the start of track 0."""
    track, rec = divmod(record, RECORDS_PER_TRACK)
    if track >= CPM_TRACKS:
        raise ValueError(f"record {record} is beyond the disk")
    return sector_offset(*physical(track, rec // 2)) + (rec % 2) * RECORD


def is_cpm_1581(data: bytes) -> bool:
    """A 1581 image with a CBM header ('D' format, DOS version '3D')."""
    if len(data) != SIZE:
        return False
    header = data[sector_offset(CBM_TRACK, 0):]
    return header[2] == ord("D") and header[0x19:0x1B] == b"3D"


def read_block(data: bytes, number: int) -> bytes:
    first = number * RECORDS_PER_BLOCK
    return b"".join(data[record_offset(first + i):record_offset(first + i) + RECORD]
                    for i in range(RECORDS_PER_BLOCK))


def _petscii_name(text: str, length: int) -> bytes:
    raw = text.upper().encode("ascii")[:length]
    return raw + b"\xa0" * (length - len(raw))


def _put_sector(image: bytearray, track: int, sector: int, data: bytes) -> None:
    offset = sector_offset(track, sector)
    image[offset:offset + SECTOR] = data


def _cbm_half_track(image: bytearray, name: str, disk_id: str) -> None:
    header = bytearray(SECTOR)
    header[0:3] = bytes([CBM_TRACK, 3, ord("D")])
    header[4:0x14] = _petscii_name(name, 16)
    header[0x14:0x16] = b"\xa0\xa0"
    header[0x16:0x18] = disk_id.upper().encode("ascii")[:2].ljust(2, b"0")
    header[0x18] = 0xA0
    header[0x19:0x1B] = b"3D"
    header[0x1B:0x1D] = b"\xa0\xa0"
    _put_sector(image, CBM_TRACK, 0, header)
    for side, link in ((1, (CBM_TRACK, 2)), (2, (0, 0xFF))):
        bam = bytearray(SECTOR)
        bam[0:2] = bytes(link)
        bam[2] = ord("D")
        bam[3] = 0xBB
        bam[4:6] = header[0x16:0x18]
        bam[6] = 0xC0
        # The 40 track entries stay zero: no free sectors.
        _put_sector(image, CBM_TRACK, side, bam)
    _put_sector(image, CBM_TRACK, 3, b"\x00\xff" + bytes(SECTOR - 2))
    for sector in range(4, 20):
        _put_sector(image, CBM_TRACK, sector, bytes(SECTOR))


def _cpm_name(name: str) -> bytes:
    base, _, ext = name.upper().partition(".")
    if not base or len(base) > 8 or len(ext) > 3:
        raise ValueError(f"{name!r} is not a CP/M file name")
    return base.ljust(8).encode("ascii") + ext.ljust(3).encode("ascii")


def build(files: dict[str, bytes], name: str = "DOS65", disk_id: str = "65") -> bytes:
    """A C128 CP/M 1581 image holding the given files in user area 0."""
    image = bytearray(b"\xe5" * SIZE)
    _cbm_half_track(image, name, disk_id)
    entries: list[bytes] = []
    next_block = DIR_BLOCKS
    for file_name in sorted(files):
        data = files[file_name]
        records = (len(data) + RECORD - 1) // RECORD
        data = data + b"\x1a" * (records * RECORD - len(data))
        extents = max(1, (records + EXTENT_RECORDS - 1) // EXTENT_RECORDS)
        for extent in range(extents):
            ext_records = min(EXTENT_RECORDS, records - extent * EXTENT_RECORDS)
            blocks = []
            for i in range((ext_records + RECORDS_PER_BLOCK - 1) // RECORDS_PER_BLOCK):
                if next_block >= BLOCKS:
                    raise ValueError("the files do not fit on the disk")
                first_record = extent * EXTENT_RECORDS + i * RECORDS_PER_BLOCK
                for r in range(min(RECORDS_PER_BLOCK, records - first_record)):
                    chunk = data[(first_record + r) * RECORD:(first_record + r + 1) * RECORD]
                    off = record_offset(next_block * RECORDS_PER_BLOCK + r)
                    image[off:off + RECORD] = chunk
                blocks.append(next_block)
                next_block += 1
            pointers = b"".join(b.to_bytes(2, "little") for b in blocks)
            entries.append(bytes([0]) + _cpm_name(file_name)
                           + bytes([extent, 0, 0, ext_records])
                           + pointers.ljust(16, b"\x00"))
    if len(entries) > DIR_ENTRIES:
        raise ValueError("the files need more than 128 directory entries")
    directory = b"".join(entries).ljust(DIR_ENTRIES * 32, b"\xe5")
    for r in range(DIR_ENTRIES * 32 // RECORD):
        off = record_offset(r)
        image[off:off + RECORD] = directory[r * RECORD:(r + 1) * RECORD]
    return bytes(image)
