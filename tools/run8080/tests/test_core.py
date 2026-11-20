"""Every 8080 opcode, one random state at a time, against the Python model.

The four Z80 prefixes and the IN and OUT instructions stop.  The Python
model treats some of those bytes as jumps, so they are not compared.
"""

import random
import tempfile
from pathlib import Path

from bench.layout import BASE, REASON, REASON_HLT, REASON_IN, REASON_OUT, REASON_PREFIX, STOPPED
from bench.sim.i8080 import CPU8080
from tests.harness import poke, pointer, read_image, regs, run_one

STOP = {0xD3, 0xDB, 0xCB, 0xDD, 0xED, 0xFD}


def _case(root, op, state, memory):
    cpu = CPU8080(bytearray(memory))
    cpu.set_state(**state)
    writes = []
    cpu.write_hook = lambda address, _value, found=writes: found.append(address)
    cpu.step()
    machine = run_one(root, state, memory)
    return cpu, machine, writes


def test_every_opcode_matches_the_python_model():
    root = Path(tempfile.mkdtemp())
    rng = random.Random(1)
    for op in range(256):
        for _trial in range(2):
            memory = bytearray(rng.randrange(256) for _ in range(65536))
            memory[0x1000] = op
            state = dict(
                a=rng.randrange(256), f=(rng.randrange(256) & 0xD5) | 2,
                b=rng.randrange(256), c=rng.randrange(256),
                d=rng.randrange(256), e=rng.randrange(256),
                h=rng.randrange(0x20, 0xD0), l=rng.randrange(256),
                sp=rng.randrange(0x2000, 0x6000) & 0xFFFE, pc=0x1000,
            )
            cpu, machine, writes = _case(root, op, state, memory)
            assert not str(machine.exit_reason).startswith("gs:"), machine.exit_reason
            if op in STOP or any(address >= 0xE000 for address in writes):
                assert machine.memory[BASE + STOPPED]
                continue
            if op == 0x76:
                assert pointer(machine, 0) == 0x1000
                assert machine.memory[BASE + REASON] == REASON_HLT
                continue
            assert regs(machine) == cpu.state()
            assert read_image(machine) == cpu.mem


def test_hlt_in_and_out_and_prefixes_stop():
    root = Path(tempfile.mkdtemp())
    state = dict(a=0, f=2, b=0, c=0, d=0, e=0, h=0x20, l=0, sp=0x4000, pc=0x1000)
    memory = bytearray(65536)
    memory[0x1000] = 0x76
    _cpu, machine, _writes = _case(root, 0x76, state, memory)
    assert machine.memory[BASE + REASON] == REASON_HLT
    memory[0x1000] = 0xDB
    _cpu, machine, _writes = _case(root, 0xDB, state, memory)
    assert machine.memory[BASE + REASON] == REASON_IN
    memory[0x1000:0x1003] = bytes([0xD3, 0x00, 0x00])
    _cpu, machine, _writes = _case(root, 0xD3, state, memory)
    assert machine.memory[BASE + REASON] == REASON_OUT
    memory[0x1000] = 0xED
    _cpu, machine, _writes = _case(root, 0xED, state, memory)
    assert machine.memory[BASE + REASON] == REASON_PREFIX


def test_fetch_on_each_side_of_the_attic_boundary():
    root = Path(tempfile.mkdtemp())
    state = dict(a=0, f=2, b=0, c=0, d=0, e=0, h=0x20, l=0, sp=0x4000, pc=0xDFFF)
    memory = bytearray(65536)
    machine = run_one(root, state, memory)
    assert regs(machine)["pc"] == 0xE000
    assert machine.memory[BASE + STOPPED] == 0
    state["pc"] = 0xE000
    poke(machine, 0xE000, 0)
    machine = run_one(root, state, memory)
    assert regs(machine)["pc"] == 0xE001


def test_pointer_wraps_at_both_ends_and_a_high_write_stops():
    root = Path(tempfile.mkdtemp())
    base = dict(a=0x55, f=2, b=0, c=0, d=0, e=0, h=0x20, l=0, sp=0x4000, pc=0x1000)

    def once(**over):
        state = dict(base)
        state.update(over)
        memory = bytearray(65536)
        memory[0x1000] = over.pop("op")
        return run_one(root, state, memory)

    machine = once(op=0x03, b=0xDF, c=0xFF)
    assert (regs(machine)["b"] << 8 | regs(machine)["c"]) == 0xE000
    machine = once(op=0x0B, b=0xE0, c=0x00)
    assert (regs(machine)["b"] << 8 | regs(machine)["c"]) == 0xDFFF
    machine = once(op=0x03, b=0xFF, c=0xFF)
    assert (regs(machine)["b"] << 8 | regs(machine)["c"]) == 0x0000
    machine = once(op=0x0B, b=0x00, c=0x00)
    assert (regs(machine)["b"] << 8 | regs(machine)["c"]) == 0xFFFF
    memory = bytearray(65536)
    memory[0x1000:0x1003] = bytes([0x32, 0x00, 0xE0])
    machine = run_one(root, base, memory)
    assert machine.memory[BASE + STOPPED] == 1
    assert machine.attic[0] != 0x55
