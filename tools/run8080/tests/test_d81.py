"""The C128 CP/M 1581 disk format written by bench.d81 and mkd81.py."""

import pytest

from bench import d81
from bench.diskimage import CpmImage
from bench.testdata import cpm_dir


def test_cpm_tracks_are_half_tracks_and_skip_the_cbm_half():
    assert d81.record_offset(0) == d81.sector_offset(1, 0)
    assert d81.record_offset(1) == d81.sector_offset(1, 0) + 128
    assert d81.record_offset(39) == d81.sector_offset(1, 19) + 128
    assert d81.record_offset(40) == d81.sector_offset(1, 20)
    assert d81.record_offset(77 * 40) == d81.sector_offset(39, 20)
    assert d81.record_offset(78 * 40) == d81.sector_offset(40, 20)
    assert d81.record_offset(79 * 40) == d81.sector_offset(41, 0)
    assert d81.record_offset(158 * 40 + 39) == d81.sector_offset(80, 39) + 128
    with pytest.raises(ValueError):
        d81.record_offset(159 * 40)


def test_sim_track_mapping():
    # The same arithmetic as hcom in c65sim.asm.
    def hcom(track, sector):
        if track >= 78:
            track += 1
        return track // 2 + 1, sector + 20 * (track & 1)
    for track in range(d81.CPM_TRACKS):
        for sector in (0, 19):
            assert hcom(track, sector) == d81.physical(track, sector)


def test_geometry_matches_the_c128_bios_and_the_sim():
    # CPM+.SYS and c65sim.asm dcba8: 40 records per track, highest block 396,
    # highest directory entry 127.
    assert d81.RECORDS_PER_TRACK == 40
    assert d81.BLOCKS - 1 == 396
    assert d81.DIR_ENTRIES - 1 == 127
    assert d81.BLOCKS * d81.RECORDS_PER_BLOCK <= d81.CPM_TRACKS * d81.RECORDS_PER_TRACK


def test_cbm_header_and_full_bam():
    image = d81.build({"A.TXT": b"x" * 10}, "SUPERCALC", "S2")
    header = image[d81.sector_offset(40, 0):][:256]
    assert header[:3] == bytes([40, 3, ord("D")])
    assert header[4:13] == b"SUPERCALC" and header[13] == 0xA0
    assert header[0x16:0x18] == b"S2" and header[0x19:0x1B] == b"3D"
    for side in (1, 2):
        bam = image[d81.sector_offset(40, side):][:256]
        assert bam[2:4] == b"D\xbb"
        assert bam[0x10:] == bytes(240)   # no free sectors on any track
    assert d81.is_cpm_1581(image)


def test_files_round_trip_with_extents():
    big = bytes(i & 0xFF for i in range(40000))          # three extents
    exact = bytes(range(256)) * 64                       # exactly one extent
    files = {"BIG.DAT": big, "EXACT.BIN": exact, "EMPTY": b"", "PATCHER": b"\x01" * 129}
    img = CpmImage(d81.build(files))
    assert img.layout.name == "c128-1581"
    assert img.files() == sorted(files)
    assert img.read("BIG.DAT") == big + b"\x1a" * (-len(big) % 128)
    assert img.read("EXACT.BIN") == exact
    assert img.read("EMPTY") == b""
    assert img.read("PATCHER") == b"\x01" * 129 + b"\x1a" * 127
    entries = {(name, ext): (rec, blocks) for _u, name, ext, rec, blocks in img.entries()}
    assert entries[("BIG.DAT", 0)][0] == 128 and entries[("BIG.DAT", 2)][0] == 57
    first = entries[("EXACT.BIN", 0)][1][0]
    assert entries[("EXACT.BIN", 0)] == (128, list(range(first, first + 8)))
    assert min(b for *_x, blocks in img.entries() for b in blocks) == d81.DIR_BLOCKS


def test_a_file_across_the_cbm_half_track():
    # Blocks 2-194 fill the space before the CBM half track; the file starts
    # in block 195, the first block behind it.
    filler = b"f" * (193 * d81.BLOCK)
    tail = bytes(range(256)) * 16
    image = d81.build({"A.DAT": filler, "B.DAT": tail})
    b_entry = [blocks for _u, name, _e, _r, blocks in CpmImage(image).entries() if name == "B.DAT"]
    assert b_entry == [[195, 196]]
    assert image[d81.sector_offset(40, 20):][:256] == tail[:256]
    assert image[d81.sector_offset(40, 4):][:256] == bytes(256)
    assert CpmImage(image).read("B.DAT") == tail


def test_unused_directory_entries_are_empty():
    image = d81.build({"A.COM": b"\xc9"})
    directory = b"".join(d81.read_block(image, n) for n in range(d81.DIR_BLOCKS))
    assert directory[0] == 0 and directory[1:12] == b"A       COM"
    assert all(directory[i] == 0xE5 for i in range(32, len(directory), 32))


def test_too_many_files_are_refused():
    files = {f"F{i}.DAT": b"x" for i in range(d81.DIR_ENTRIES + 1)}
    with pytest.raises(ValueError, match="directory"):
        d81.build(files)


def test_too_much_data_is_refused():
    with pytest.raises(ValueError, match="fit"):
        d81.build({"HUGE.DAT": bytes(396 * d81.BLOCK)})


def test_original_c128_disk_reads_with_the_same_layout():
    path = cpm_dir() / "programming" / "TurboPascal.d81.gz"
    if not path.exists():
        pytest.skip(f"{path} missing (set CPM2DOS65_CPM_DIR)")
    img = CpmImage.open(path)
    assert img.layout.name == "c128-1581"
    # These files lie behind the CBM half track (blocks 197-293).
    assert img.read("TRACK.PAS").startswith(b"\r\nprogram track;")
    assert img.read("BJGAME.PAS").startswith(b"program bjgame;")
    assert img.read("GAMES1.PAS").startswith(b"program games;")
