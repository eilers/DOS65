"""DOS2CBM, CBM2DOS, and CBMDIR, run as 6502 programs.

The Primitive Execution Module (PEM) is DOS/65's call gate at $103.
The kernel is the Commodore ROM: open, read, write, and the status
byte. READST is that status. Bit 6 ($40) is raised on the last real
byte of a file, so the byte is kept. The next read, and the first
read of an empty file, comes back as $42 (end of file and the read
timeout together) and that byte is not data.

A Commodore directory line already contains the spaces that line the
names up, counted for a block count printed as digits and one space.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest
from py65.devices.mpu6502 import MPU

REPO = Path(__file__).resolve().parents[3]
SRC = REPO / "src"
BSA = REPO / "bsa" / "bsa"
TEA = 0x200
PEM = 0x103
HALT = 0xF800
DFLBUF = 0x128
RECORD = 128
CTZ = 0x1A

# Kernel entries the programs call. Each one is an RTS. The test
# handles the call, then lets the processor execute that RTS.
KERNEL = {
    0xFFB7: "readst",
    0xFFBA: "setlfs",
    0xFFBD: "setnam",
    0xFFC0: "open",
    0xFFC3: "close",
    0xFFC6: "chkin",
    0xFFC9: "ckout",
    0xFFCC: "clrch",
    0xFFCF: "basin",
    0xFFD2: "bsout",
}

LF_DATA = 3
LF_CMD = 4
SA_DATA = 3
SA_DIR = 0
SA_CMD = 15


def _assemble(name: str) -> bytes:
    if not BSA.is_file():
        pytest.fail(f"assembler missing at {BSA}")
    subprocess.run(
        [str(BSA), "-i", f"../{name}.ASM"],
        cwd=SRC / "c65",
        check=True,
        capture_output=True,
        text=True,
    )
    return (SRC / "c65" / "disk" / f"{name}.COM").read_bytes()


@pytest.fixture(scope="module")
def programs():
    return {name: _assemble(name) for name in ("DOS2CBM", "CBM2DOS", "CBMDIR")}


class CommodoreMachine:
    """PEM and a small Commodore drive, in front of one program."""

    def __init__(self, image: bytes):
        self.mpu = MPU(memory=[0] * 0x10000)
        self.mem = self.mpu.memory
        for index, byte in enumerate(image):
            self.mem[TEA + index] = byte
        for address in KERNEL:
            self.mem[address] = 0x60
        self.mem[PEM] = 0x60
        self.mem[HALT] = 0x00

        self.console = bytearray()
        self.dos = {}
        self.cbm = {}
        self.blocks = {}
        self.present = {8, 9}
        self.fail_write_after = None
        self.fail_dos_write = False
        self.opened = []
        self.commands = []

        self._la = 0
        self._fa = 0
        self._sa = 0
        self._name = b""
        self._input = None
        self._output = None
        self._status = 0
        self._error = b"00, OK,00,00\r"
        self._error_at = 0
        self._cmd = bytearray()
        self._dma = 0
        self._data_at = 0
        self._dir = b""
        self._writes = 0

    def dos_put(self, key: bytes, records):
        self.dos[key] = [bytearray(record) for record in records]

    def cbm_put(self, name: str, data: bytes, blocks: int | None = None):
        self.cbm[name] = bytearray(data)
        if blocks is not None:
            self.blocks[name] = blocks

    def run(self, which: str, programs, command: str):
        image = programs[which]
        for index, byte in enumerate(image):
            self.mem[TEA + index] = byte
        raw = command.encode("ascii")
        self.mem[DFLBUF] = len(raw)
        for index, byte in enumerate(raw, start=1):
            self.mem[DFLBUF + index] = byte
        self.mpu.stPushWord(HALT - 1)
        self.mpu.pc = TEA
        steps = 0
        while self.mpu.pc != HALT:
            service = KERNEL.get(self.mpu.pc)
            if self.mpu.pc == PEM:
                self._pem()
                self.mpu.step()
            elif service is not None:
                getattr(self, f"_{service}")()
                self.mpu.step()
            else:
                if self.mem[self.mpu.pc] == 0x00:
                    raise AssertionError(
                        f"stopped at ${self.mpu.pc:04X}, console {self.text!r}"
                    )
                self.mpu.step()
            steps += 1
            if steps > 250000:
                raise AssertionError(f"did not return, console {self.text!r}")
        return self

    @property
    def text(self) -> str:
        return self.console.decode("latin1")

    def _carry(self, flag: bool):
        if flag:
            self.mpu.p |= MPU.CARRY
        else:
            self.mpu.p &= ~MPU.CARRY

    def _address(self) -> int:
        return self.mpu.a | (self.mpu.y << 8)

    def _fcb_key(self, fcb: int) -> bytes:
        return bytes(self.mem[fcb + 1:fcb + 12])

    def _say(self, address: int):
        while self.mem[address] != ord("$"):
            self._emit(self.mem[address])
            address += 1

    def _emit(self, byte: int):
        # PEM asks the keyboard for a key while it prints. With a file
        # selected for input, that read takes a byte from the file.
        if self._input == LF_DATA:
            self._take()
        self.console.append(byte)

    def _pem(self):
        function = self.mpu.x
        if function == 2:
            self._emit(self.mpu.a)
        elif function == 9:
            self._say(self._address())
        elif function == 15:
            self._dos_open()
        elif function == 16:
            self.mpu.a = 0
        elif function == 19:
            self.dos.pop(self._fcb_key(self._address()), None)
            self.mpu.a = 0
        elif function == 20:
            self._dos_read()
        elif function == 21:
            self._dos_write()
        elif function == 22:
            self._dos_make()
        elif function == 26:
            self._dma = self._address()
        else:
            raise AssertionError(f"PEM function {function} was not expected")
        self.mpu.x = 0
        self.mpu.y = 0

    def _dos_open(self):
        fcb = self._address()
        key = self._fcb_key(fcb)
        if key in self.dos:
            self.mem[fcb + 32] = 0
            self.mpu.a = 0
        else:
            self.mpu.a = 255

    def _dos_make(self):
        key = self._fcb_key(self._address())
        if self.fail_dos_write and key in self.dos:
            self.mpu.a = 255
            return
        self.dos[key] = []
        self.mpu.a = 0

    def _dos_read(self):
        fcb = self._address()
        key = self._fcb_key(fcb)
        records = self.dos.get(key, [])
        number = self.mem[fcb + 32]
        if number >= len(records):
            self.mpu.a = 1
            return
        for index, byte in enumerate(records[number]):
            self.mem[self._dma + index] = byte
        self.mem[fcb + 32] = number + 1
        self.mpu.a = 0

    def _dos_write(self):
        fcb = self._address()
        if self.fail_dos_write:
            self.mpu.a = 1
            return
        key = self._fcb_key(fcb)
        record = bytearray(self.mem[self._dma:self._dma + RECORD])
        self.dos.setdefault(key, []).append(record)
        self.mem[fcb + 32] = self.mem[fcb + 32] + 1
        self.mpu.a = 0

    def _setlfs(self):
        self._la = self.mpu.a
        self._fa = self.mpu.x
        self._sa = self.mpu.y

    def _setnam(self):
        length = self.mpu.a
        address = self.mpu.x | (self.mpu.y << 8)
        self._name = bytes(self.mem[address:address + length])

    def _open(self):
        if self._fa not in self.present:
            self.mpu.a = 5
            self._carry(True)
            return
        self.opened.append((self._sa, self._name))
        if self._sa == SA_CMD:
            self._error_at = 0
        elif self._sa == SA_DIR:
            self._dir = _directory(self.cbm, self.blocks)
            self._data_at = 0
            self._error = b"00, OK,00,00\r"
        elif self._name.endswith(b",S,W"):
            base = self._name[:-4].decode("ascii")
            if base in self.cbm:
                self._error = b"63, FILE EXISTS,00,00\r"
            else:
                self.cbm[base] = bytearray()
                self._writes = 0
                self._error = b"00, OK,00,00\r"
        else:
            base = self._name.decode("ascii")
            self._data_at = 0
            if base in self.cbm:
                self._error = b"00, OK,00,00\r"
            else:
                self._error = b"62, FILE NOT FOUND,00,00\r"
        self.mpu.a = 0
        self._carry(False)

    def _close(self):
        if self._input == self.mpu.a:
            self._input = None
        if self._output == self.mpu.a:
            self._output = None
        self.mpu.a = 0

    def _chkin(self):
        self._input = self.mpu.x
        if self.mpu.x == LF_CMD:
            self._error_at = 0
        self._carry(False)

    def _ckout(self):
        self._output = self.mpu.x
        if self.mpu.x == LF_CMD:
            self._cmd = bytearray()
        self._carry(False)

    def _clrch(self):
        self._input = None
        self._output = None

    def _basin(self):
        if self._input == LF_CMD:
            if self._error_at >= len(self._error):
                self.mpu.a = 0x0D
                self._status = 0x42
            else:
                self.mpu.a = self._error[self._error_at]
                self._error_at += 1
                self._status = 0
            return
        data = self._dir if self._sa == SA_DIR else self._open_data()
        if self._data_at >= len(data):
            self.mpu.a = 0x0D
            self._status = 0x42
            return
        self.mpu.a = data[self._data_at]
        self._data_at += 1
        self._status = 0x40 if self._data_at == len(data) else 0

    def _take(self) -> int:
        saved = self.mpu.a
        self._basin()
        byte = self.mpu.a
        self.mpu.a = saved
        return byte

    def _open_data(self) -> bytearray:
        name = self._name.split(b",", 1)[0].decode("ascii")
        return self.cbm.get(name, bytearray())

    def _bsout(self):
        if self._output == LF_CMD:
            self._cmd.append(self.mpu.a)
            if self.mpu.a == 0x0D:
                text = self._cmd.decode("ascii")
                self.commands.append(text)
                if text.startswith("S0:"):
                    self.cbm.pop(text[3:].rstrip("\r"), None)
                    self._error = b"01, FILES SCRATCHED,01,00\r"
            self._status = 0
            return
        name = self._name[:-4].decode("ascii")
        if name not in self.cbm:
            self._status = 1
            return
        if self.fail_write_after is not None and self._writes >= self.fail_write_after:
            self._status = 1
            return
        self.cbm[name].append(self.mpu.a)
        self._writes += 1
        self._status = 0

    def _readst(self):
        # The kernel loads the status and returns, so the zero flag
        # matches A. The copy loop branches on that flag.
        self.mpu.a = self._status
        self.mpu.p &= ~(MPU.ZERO | MPU.NEGATIVE)
        if self.mpu.a == 0:
            self.mpu.p |= MPU.ZERO
        elif self.mpu.a & 0x80:
            self.mpu.p |= MPU.NEGATIVE


def _spaces(blocks: int) -> int:
    if blocks < 10:
        return 3
    if blocks < 100:
        return 2
    if blocks < 1000:
        return 1
    return 0


def _file_text(blocks: int, name: str, kind: str = "PRG") -> bytes:
    padded = name.encode("ascii") + bytes([0xA0]) * (16 - len(name))
    return bytes([0x20] * _spaces(blocks)) + b'"' + padded + b'" ' + kind.encode("ascii")


def _line(blocks: int, text: bytes) -> bytes:
    return bytes([0x01, 0x01, blocks & 0xFF, blocks >> 8]) + text + bytes([0])


def _directory(files: dict, blocks: dict) -> bytes:
    image = bytearray([0x01, 0x04])
    image += _line(0, bytes([0x12]) + b'"DISK NAME" 01 2A')
    for name in files:
        count = blocks.get(name, 1)
        image += _line(count, _file_text(count, name))
    image += _line(1055, b"BLOCKS FREE.")
    image += bytes([0x00, 0x00])
    return bytes(image)


def _machine(programs, which: str, command: str, **ready) -> CommodoreMachine:
    machine = CommodoreMachine(programs[which])
    for key, records in ready.get("dos", {}).items():
        machine.dos_put(key, records)
    for name, data in ready.get("cbm", {}).items():
        machine.cbm_put(name, data, ready.get("blocks", {}).get(name))
    if "present" in ready:
        machine.present = set(ready["present"])
    machine.fail_write_after = ready.get("fail_write_after")
    machine.fail_dos_write = ready.get("fail_dos_write", False)
    return machine.run(which, programs, command)


def _records(machine: CommodoreMachine, key: bytes) -> bytes:
    return b"".join(machine.dos[key])


def test_cbmdir_lines_the_names_up(programs):
    blocks = {"A": 2, "WIDE": 15, "GEOBOOT": 152, "BIG": 1000}
    machine = _machine(
        programs, "CBMDIR", " 9",
        cbm={name: b"x" for name in blocks},
        blocks=blocks,
    )
    lines = [line for line in machine.text.splitlines() if line]
    assert lines[0] == "CBMDIR UNIT 9"
    header = next(line for line in lines if "DISK NAME" in line)
    files = [line for line in lines if line.endswith("PRG")]
    assert header.index('"') < files[0].index('"')
    assert len({line.index('"') for line in files}) == 1
    assert len({line.index('"', line.index('"') + 1) for line in files}) == 1
    assert len({line.index("PRG") for line in files}) == 1
    assert any(line.startswith("1055 ") and "BLOCKS FREE." in line for line in lines)


def test_cbmdir_rejects_a_bad_command(programs):
    extra = _machine(programs, "CBMDIR", " 9 HELLO")
    assert "BAD COMMAND" in extra.text
    assert extra.cbm == {}

    low = _machine(programs, "CBMDIR", " 7")
    assert "BAD DEVICE" in low.text

    missing = _machine(programs, "CBMDIR", " 9", present={8})
    assert "DEVICE NOT PRESENT" in missing.text


def test_dos2cbm_writes_the_whole_record_as_a_sequential_file(programs):
    first = bytes([0x01, 0x08]) + bytes(range(126))
    second = bytes(reversed(range(RECORD)))
    machine = _machine(
        programs, "DOS2CBM", " 9 MY LONG FILE.BAS",
        dos={b"MYLONGFIBAS": [first, second]},
    )
    assert machine.cbm["MY LONG FILE.BAS"] == bytearray(first + second)
    assert (SA_DATA, b"MY LONG FILE.BAS,S,W") in machine.opened
    assert "COPIED" in machine.text
    assert "FILE EXISTS" not in machine.text


def test_dos2cbm_leaves_an_existing_file_and_removes_a_failed_one(programs):
    kept = _machine(
        programs, "DOS2CBM", " 9 NOTES.TXT",
        dos={b"NOTES   TXT": [b"N" * RECORD]},
        cbm={"NOTES.TXT": b"original"},
    )
    assert kept.cbm["NOTES.TXT"] == bytearray(b"original")
    assert "FILE EXISTS" in kept.text
    assert kept.commands == []

    failed = _machine(
        programs, "DOS2CBM", " 9 NOTES.TXT",
        dos={b"NOTES   TXT": [b"N" * RECORD]},
        fail_write_after=10,
    )
    assert "NOTES.TXT" not in failed.cbm
    assert any(command.startswith("S0:NOTES.TXT") for command in failed.commands)
    assert "COPIED" not in failed.text


def test_cbm2dos_keeps_the_last_byte_and_pads_the_short_record(programs):
    machine = _machine(
        programs, "CBM2DOS", " 9 MY LONG FILE.BAS",
        cbm={"MY LONG FILE.BAS": b"AB\x5a"},
    )
    assert _records(machine, b"MYLONGFIBAS") == b"AB\x5a" + bytes([CTZ]) * 125
    assert "COPIED" in machine.text


def test_cbm2dos_empty_file_and_an_exact_record(programs):
    empty = _machine(programs, "CBM2DOS", " 9 EMPTY.SEQ", cbm={"EMPTY.SEQ": b""})
    assert empty.dos[b"EMPTY   SEQ"] == []
    assert "COPIED" in empty.text

    exact = bytes([0x5A]) * RECORD
    full = _machine(programs, "CBM2DOS", " 9 FULL.BIN", cbm={"FULL.BIN": exact})
    assert _records(full, b"FULL    BIN") == exact
    assert len(full.dos[b"FULL    BIN"]) == 1


def test_cbm2dos_refuses_an_existing_file_and_removes_a_full_disk(programs):
    original = [b"K" * RECORD]
    kept = _machine(
        programs, "CBM2DOS", " 9 NOTES.TXT",
        dos={b"NOTES   TXT": original},
        cbm={"NOTES.TXT": b"new"},
    )
    assert kept.dos[b"NOTES   TXT"] == [bytearray(b"K" * RECORD)]
    assert "FILE EXISTS" in kept.text

    full = _machine(
        programs, "CBM2DOS", " 9 NOTES.TXT",
        cbm={"NOTES.TXT": b"abc"},
        fail_dos_write=True,
    )
    assert b"NOTES   TXT" not in full.dos
    assert "DISK FULL" in full.text
    assert full.cbm["NOTES.TXT"] == bytearray(b"abc")


def test_a_long_name_and_a_rejected_character(programs):
    bad = _machine(programs, "DOS2CBM", " 9 BAD:NAME.BAS", dos={})
    assert "BAD FILE NAME" in bad.text
    assert bad.cbm == {}

    missing = _machine(programs, "CBM2DOS", " 9 GONE.TXT")
    assert "FILE NOT FOUND" in missing.text
    assert missing.dos == {}
