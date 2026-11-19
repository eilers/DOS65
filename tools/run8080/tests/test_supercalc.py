"""SuperCalc 2: sign-on, load SAMPLE.CAL, type one value, save.

The commercial disk image stays outside the repository.  The test skips
when prod/SuperCalc_v2.d81 is not there.  BDOS is the CP/M disk system;
the screen compare is the 80 by 24 ADM-3A grid, not the raw escape bytes.
"""

import tempfile
from pathlib import Path

import pytest

from bench.diskimage import CpmImage
from bench.sim.cpm import CPMMachine
from bench.sim.devices import Console
from bench.sim.dos65 import DOS65Machine
from bench.testdata import cpm_dir
from tests.harness import COM
from tests.test_syscall import adm, screen


def _image():
    path = cpm_dir() / "prod" / "SuperCalc_v2.d81"
    if not path.exists():
        pytest.skip(f"{path} missing (set CPM2DOS65_CPM_DIR)")
    return CpmImage.open(path)


class Guest:
    def __init__(self, root: Path, kind: str):
        self.con = Console(b"", idle_polls=1500)
        self.kind = kind
        if kind == "dos":
            self.machine = DOS65Machine(root, console=self.con)
            self.machine.load(COM, "sc2")
        else:
            self.machine = CPMMachine(root, console=self.con)
            self.machine.load((root / "SC2.COM").read_bytes(), "")
            # SuperCalc sizes its sheet from the address stored at byte 6.
            # run8080 reports $E000 there.  Point the model at the same place
            # and bounce the call to the real trap.
            mem = self.machine.mem
            mem[5:8] = bytes([0xC3, 0x00, 0xE0])
            mem[0xE000:0xE003] = bytes([0xC3, 0x06, 0xE4])
        self.reason = ""

    def _budget(self, limit: int) -> int:
        # The CP/M model counts 8080 instructions.  run8080 counts 45GS02 steps.
        return limit if self.kind == "dos" else 15_000_000

    def run(self, limit: int) -> str:
        self.reason = self.machine.run(self._budget(limit))
        return self.reason

    def send(self, value: int, limit: int = 8_000_000, idle: int = 1500) -> str:
        self.con.idle_polls = idle
        self.con._empty_polls = 0
        self.con.input = bytearray([value])
        return self.run(limit)

    def grid(self) -> bytes:
        if self.kind == "dos":
            return screen(self.machine)
        return adm(bytes(self.con.output))

    def row(self, number: int) -> str:
        return self.grid()[number * 80:(number + 1) * 80].decode("latin-1")


def _prepare(img: CpmImage) -> Path:
    root = Path(tempfile.mkdtemp())
    for name in ("SC2.COM", "SC2.OVL", "SC2.HLP", "SAMPLE.CAL"):
        (root / name).write_bytes(img.read(name))
    return root


def _until_sheet(guest: Guest) -> None:
    guest.run(15_000_000)
    guest.send(0x0D, limit=25_000_000, idle=4000)
    for byte in b"/LSAMPLE\r":
        guest.send(byte, limit=8_000_000, idle=2000)
    guest.con.idle_polls = 20_000
    guest.con._empty_polls = 0
    guest.con.input = bytearray(b"A")
    for _ in range(14):
        guest.run(40_000_000)
        status = guest.row(22)
        if guest.reason == "input" and "Last Col" in status and b"JAN" in guest.grid():
            return
        guest.con._empty_polls = 0
        guest.con.input = bytearray()
    raise AssertionError(guest.row(22) + " / " + guest.reason)


def test_supercalc_loads_edits_and_saves():
    img = _image()
    ours = Guest(_prepare(img), "dos")
    ref = Guest(_prepare(img), "cpm")
    _until_sheet(ours)
    _until_sheet(ref)
    assert b"JAN" in ours.grid() and b"JAN" in ref.grid()

    for byte in b"7\r":
        ours.send(byte, limit=40_000_000, idle=20_000)
        ref.send(byte, limit=40_000_000, idle=20_000)
    for _ in range(6):
        if ours.reason == "input" and ref.reason == "input":
            break
        ours.run(40_000_000)
        ref.run(40_000_000)
    assert b"7" in ours.grid(), ours.row(1) + " / " + ours.row(23)

    for byte in b"/SSAMPLE\r":
        ours.send(byte, limit=30_000_000, idle=20_000)
        ref.send(byte, limit=30_000_000, idle=20_000)
    for _ in range(8):
        done = True
        for guest in (ours, ref):
            text = guest.row(22) + guest.row(23)
            if "A(ll)" in text:
                guest.send(ord("A"), limit=30_000_000, idle=20_000)
                done = False
            elif "verwrite" in text or "C(hange" in text or "C, B" in text:
                guest.send(ord("O"), limit=30_000_000, idle=20_000)
                done = False
            elif "Last Col" not in guest.row(22):
                guest.run(30_000_000)
                done = False
        if done:
            break

    saved_ours = (ours.machine.fs.root / "SAMPLE.CAL").read_bytes()
    saved_ref = (ref.machine.fs.root / "SAMPLE.CAL").read_bytes()
    original = img.read("SAMPLE.CAL")
    assert saved_ours == saved_ref, (ours.row(22), ours.row(23), ref.row(22), ref.row(23))
    assert saved_ours != original, (ours.row(22), ours.row(23), ref.row(22), ref.row(23))
    assert ours.grid() == ref.grid()
