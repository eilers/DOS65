"""What the MEGA65 kernel and its disk actually return, measured in xemu.

The host tests answer the kernel calls themselves. These tests run
the same calls inside the emulator and read back the bytes. Each
test is one claim the host model used to invent.

Opening a drive that is not attached (unit 11) did not return from
the kernel in this emulator, so that case is not run here. The copy
programs still treat carry and accumulator 5 as "device not present",
which is the kernel's own error when OPEN does return.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
BSA = REPO / "bsa" / "bsa"
XMEGA65 = Path(
    os.environ.get(
        "XMEGA65",
        "/Users/stefan/Developer/c65/xemu_gurce/build/bin/xmega65.native",
    )
)


def _need(path: Path, program: str) -> None:
    if path.is_file() and os.access(path, os.X_OK):
        return
    pytest.skip(f"{program} is not available ({path})")


def _pairs(lines: list[str]) -> list[tuple[int, int]]:
    found = []
    for line in lines:
        if line.startswith(("C=", "ST=")) or " " not in line:
            continue
        status, byte = line.split()
        found.append((int(status, 16), int(byte, 16)))
    return found


def _text(lines: list[str]) -> str:
    return "".join(chr(byte) for _status, byte in _pairs(lines) if byte != 13)


@pytest.fixture(scope="module")
def kernel_log(tmp_path_factory: pytest.TempPathFactory) -> dict[str, list[str]]:
    """One xemu boot. The log is the kernel's own BASIN and READST pairs."""
    _need(XMEGA65, "xmega65")
    c1541 = shutil.which("c1541")
    if not c1541:
        pytest.skip("c1541 is not available")
    work = tmp_path_factory.mktemp("kernel")
    # The assembler takes a file name in the working directory, not a path.
    shutil.copy(HERE / "kernel_probe.asm", work / "kernel_probe.asm")
    subprocess.run([str(BSA), "kernel_probe.asm"], cwd=work, check=True)
    disk = work / "probe.d81"
    one = work / "a.seq"
    ten = work / "ten.seq"
    hun = work / "hun.seq"
    one.write_bytes(b"A")
    ten.write_bytes(bytes([0x11]) * (10 * 254))
    hun.write_bytes(bytes([0x22]) * (110 * 254))
    subprocess.run([c1541, "-format", "probe,kp", "d81", str(disk)], check=True)
    subprocess.run(
        [
            c1541, "-attach", str(disk),
            "-write", str(one), "a,s",
            "-write", str(ten), "ten,s",
            "-write", str(hun), "hun,s",
        ],
        check=True,
    )
    probe = work / "kernel_probe.prg"
    # $42 written to $D6CF asks xemu to quit. It reports that request
    # as process status 66, which is 42 hex, and the log is already
    # closed on the disk by then.
    ran = subprocess.run(
        [
            str(XMEGA65),
            "-headless", "-sleepless", "-nosound", "-besure", "-fastboot",
            "-testing",
            "-prg", str(probe),
            "-prgtest", "SYS8192",
            "-8", str(disk),
        ],
        timeout=60,
    )
    assert ran.returncode in (0, 66)
    log_path = work / "log.txt"
    subprocess.run(
        [c1541, "-attach", str(disk), "-read", "log,s", str(log_path)],
        check=True,
    )
    sections: dict[str, list[str]] = {}
    name = ""
    for line in log_path.read_text("latin1").splitlines():
        if line.startswith(">"):
            name = line[1:]
            sections[name] = []
        elif name:
            sections[name].append(line)
    assert sections["DONE"] == []
    return sections


def test_the_last_byte_arrives_with_status_40(kernel_log):
    data = _pairs(kernel_log["ONE"])
    # The three stored bytes, then the kernel's extra carriage return.
    assert (0x00, 0x01) in data
    assert (0x00, 0x08) in data
    end = data.index((0x40, 0x5A))
    assert data[end + 1] == (0x40, 0x0D)
    assert all(status != 0x42 for status, _byte in data)


def test_reselecting_the_file_is_a_timeout(kernel_log):
    assert kernel_log["RESELECT"][0] == "ST=00"
    assert _pairs(kernel_log["RESELECT"])[:2] == [(0x02, 0x00), (0x02, 0x0D)]


def test_an_empty_file_is_one_carriage_return(kernel_log):
    lines = kernel_log["EMPTY"]
    reading = lines[lines.index("ST=00"):]
    assert _pairs(reading)[0] == (0x40, 0x0D)


def test_a_missing_file_is_status_62_without_open_failing(kernel_log):
    lines = kernel_log["GONE"]
    assert lines[0] == "C=0 A=52"
    assert _text(lines).startswith("62,FILE NOT FOUND,00,00")
    assert (0x40, 0x0D) in _pairs(lines)


def test_opening_an_existing_file_for_write_does_not_replace_it(kernel_log):
    lines = kernel_log["EXISTS"]
    assert lines[0].startswith("C=0 ")
    assert "63,FILE EXISTS,00,00" in _text(lines)
    assert _pairs(lines)[-4:] == [
        (0x00, 0x01), (0x00, 0x08), (0x40, 0x5A), (0x40, 0x0D),
    ]


def test_scratch_reports_one_file(kernel_log):
    assert _text(kernel_log["SCRATCH"]).startswith("01,FILES SCRATCHED,01,00")


def test_directory_spaces_follow_the_number_of_digits(kernel_log):
    data = bytes(byte for _status, byte in _pairs(kernel_log["DIR"]))
    lines = []
    start = 0
    while True:
        link = data.find(b"\x44\x4a", start)
        if link < 0:
            break
        blocks = data[link + 2] | (data[link + 3] << 8)
        end = data.find(b"\x00", link + 4)
        lines.append((blocks, data[link + 4:end]))
        start = link + 2
    by_count = {blocks: text for blocks, text in lines}
    assert by_count[1].split(b'"', 1)[0] == b" " * 3
    assert by_count[10].split(b'"', 1)[0] == b" " * 2
    assert by_count[110].split(b'"', 1)[0] == b" " * 1
    assert b"SEQ" in by_count[1] and b"SEQ" in by_count[10] and b"SEQ" in by_count[110]
    free = by_count[3037]
    assert free.startswith(b"BLOCKS FREE")
    assert not free.startswith(b"BLOCKS FREE.")
