"""Load RUN8080.COM and look at the emulated 8080 from Python."""

from __future__ import annotations

from pathlib import Path

from bench.layout import (
    BASE, BC, DE, DMAAD, HL, INS, MAXHI, MAXLO, OPCODE, PC, RA, REASON, RF,
    SP, STOPPED, UNLIM,
)
from bench.sim.dos65 import DOS65Machine
from bench.sim.i8080 import CPU8080

ROOT = Path(__file__).resolve().parents[1]
COM = (ROOT / "RUN8080.COM").read_bytes()
CORE = 0x203


def poke(machine: DOS65Machine, addr: int, value: int) -> None:
    if addr < 0xE000:
        machine.bank(4)[(addr + 0x2000) & 0xFFFF] = value & 0xFF
    else:
        off = addr - 0xE000
        if off < len(machine.attic):
            machine.attic[off] = value & 0xFF


def peek(machine: DOS65Machine, addr: int) -> int:
    if addr < 0xE000:
        return machine.bank(4)[(addr + 0x2000) & 0xFFFF]
    return machine.attic[addr - 0xE000]


def set_pointer(machine: DOS65Machine, zp: int, value: int) -> None:
    value &= 0xFFFF
    if value < 0xE000:
        raw = bytes([value & 0xFF, ((value >> 8) + 0x20) & 0xFF, 0x04, 0x00])
    else:
        raw = bytes([value & 0xFF, ((value >> 8) - 0xE0) & 0xFF, 0x00, 0x08])
    machine.memory[BASE + zp:BASE + zp + 4] = raw


def pointer(machine: DOS65Machine, zp: int) -> int:
    mem = machine.memory
    lo = mem[BASE + zp]
    hi = mem[BASE + zp + 1]
    if mem[BASE + zp + 3] == 0x08:
        return lo | ((hi + 0xE0) & 0xFF) << 8
    return lo | ((hi - 0x20) & 0xFF) << 8


def write_image(machine: DOS65Machine, memory: bytes) -> None:
    bank = machine.bank(4)
    for addr, value in enumerate(memory):
        if addr < 0xE000:
            bank[(addr + 0x2000) & 0xFFFF] = value
        elif addr - 0xE000 < len(machine.attic):
            machine.attic[addr - 0xE000] = value


def read_image(machine: DOS65Machine) -> bytearray:
    out = bytearray(65536)
    bank = machine.bank(4)
    for addr in range(0xE000):
        out[addr] = bank[(addr + 0x2000) & 0xFFFF]
    for addr in range(0xE000, 0x10000):
        off = addr - 0xE000
        if off < len(machine.attic):
            out[addr] = machine.attic[off]
    return out


def regs(machine: DOS65Machine) -> dict:
    mem = machine.memory
    bc = pointer(machine, BC)
    de = pointer(machine, DE)
    hl = pointer(machine, HL)
    return {
        "a": mem[BASE + RA], "f": mem[BASE + RF],
        "b": bc >> 8, "c": bc & 0xFF, "d": de >> 8, "e": de & 0xFF,
        "h": hl >> 8, "l": hl & 0xFF,
        "sp": pointer(machine, SP), "pc": pointer(machine, PC),
    }


def run_one(root, state: dict, memory: bytearray, limit: int = 8000) -> DOS65Machine:
    machine = DOS65Machine(root)
    machine.memory[0x200:0x200 + len(COM)] = COM
    write_image(machine, memory)
    mem = machine.memory
    set_pointer(machine, PC, state["pc"])
    set_pointer(machine, SP, state["sp"])
    set_pointer(machine, HL, state["h"] << 8 | state["l"])
    set_pointer(machine, DE, state["d"] << 8 | state["e"])
    set_pointer(machine, BC, state["b"] << 8 | state["c"])
    mem[BASE + RA] = state["a"]
    mem[BASE + RF] = (state["f"] & 0xD5) | 0x02
    mem[BASE + UNLIM] = 0
    mem[BASE + MAXLO] = 1
    mem[BASE + MAXHI] = 0
    mem[BASE + STOPPED] = 0
    mem[BASE + DMAAD] = 0x80
    mem[BASE + DMAAD + 1] = 0
    machine.mpu.pc = CORE
    machine.run(limit)
    return machine


def run_loaded(root, program: bytes, *, script: bytes = b"", tail: str = "",
               files: dict[str, bytes] | None = None,
               limit: int = 2_000_000) -> DOS65Machine:
    for name, data in (files or {}).items():
        (root / name).write_bytes(data)
    guest = tail.split()[0].split(":")[-1].upper() if tail.split() else "GUEST"
    if "." not in guest:
        guest += ".COM"
    (root / guest).write_bytes(program)
    machine = DOS65Machine(root)
    machine.console.input = bytearray(script)
    machine.load(COM, tail)
    machine.run(limit)
    return machine


def reference(state: dict, memory: bytearray) -> tuple[dict, bytearray]:
    cpu = CPU8080(bytearray(memory))
    cpu.set_state(**state)
    cpu.step()
    return cpu.state(), cpu.mem
