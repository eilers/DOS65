"""BDOS calls SuperCalc 2 actually makes, compared with the CP/M model.

PEM is the DOS/65 Primitive Execution Module.  BDOS is the CP/M Basic Disk
Operating System.  An FCB is a file control block.  The screen test checks
the 80 by 24 cell grid after the ADM-3A cursor sequences, not the raw bytes.
"""

import tempfile
from pathlib import Path

from bench.layout import BASE, FUNC, REASON, REASON_USER, SCREEN, SCREEN_BYTES, STOPPED
from bench.sim.cpm import CPMMachine
from tests.harness import COM, peek, run_loaded


def mem(machine, addr: int) -> int:
    if hasattr(machine, "mem"):
        return machine.mem[addr]
    return peek(machine, addr)


def both(program: bytes, tail: str, *, files=None, script=b"", limit=2_000_000):
    files = files or {}
    ours = run_loaded(Path(tempfile.mkdtemp()), program, tail=tail,
                      files=files, script=script, limit=limit)
    root = Path(tempfile.mkdtemp())
    for name, data in files.items():
        (root / name).write_bytes(data)
    cpm = CPMMachine(root)
    cpm.console.input = bytearray(script)
    cpm.load(program, tail.split(" ", 1)[1] if " " in tail else "")
    cpm.run()
    return ours, cpm


def screen(machine) -> bytes:
    return bytes(machine.bank(4)[SCREEN:SCREEN + SCREEN_BYTES])


def adm(stream: bytes) -> bytes:
    """The same ADM-3A rules run8080 applies to BDOS function 6 output."""
    cells = bytearray(b" " * (80 * 24))
    row = col = state = 0

    def put(value):
        nonlocal row, col
        cells[row * 80 + col] = value
        col += 1
        if col == 80:
            col = 0
            linefeed()

    def linefeed():
        nonlocal row, col
        col = 0
        if row < 23:
            row += 1
            return
        del cells[:80]
        cells.extend(b" " * 80)

    for byte in stream:
        if state == 1:
            state = 2 if byte == 0x3D else 0
            continue
        if state == 2:
            row = min(23, max(0, byte - 32))
            state = 3
            continue
        if state == 3:
            col = min(79, max(0, byte - 32))
            state = 0
            continue
        if byte == 0x1A:
            cells[:] = b" " * len(cells)
            row = col = 0
        elif byte == 0x1B:
            state = 1
        elif byte == 0x0D:
            col = 0
        elif byte == 0x0A:
            linefeed()
        elif byte >= 0x20:
            put(byte)
    return bytes(cells)


def test_version_is_22_and_does_not_use_pem_12():
    program = bytes([
        0x0E, 0x0C, 0xCD, 0x05, 0x00,
        0x32, 0x00, 0x04, 0x7D, 0x32, 0x01, 0x04, 0x7C, 0x32, 0x02, 0x04,
        0xC3, 0x00, 0x00,
    ])
    ours, cpm = both(program, "ver")
    assert ours.exit_reason == "exit"
    assert mem(ours, 0x400) == mem(cpm, 0x400) == 0x22
    assert mem(ours, 0x401) == 0x22 and mem(ours, 0x402) == 0
    assert all(function != 12 for function, _address in ours.pem_log)


def test_print_string_matches_cpm():
    program = bytes([0x0E, 9, 0x11, 0x10, 0x01, 0xCD, 0x05, 0x00, 0xC3, 0, 0])
    program += bytes(0x10 - len(program)) + b"Hello$"
    ours, cpm = both(program, "pr")
    assert ours.console.text() == cpm.console.text() == "Hello"


def test_console_status_and_cursor_keys():
    program = bytes([
        0x0E, 6, 0x1E, 0xFE, 0xCD, 0x05, 0x00, 0x32, 0x00, 0x02,
        0x0E, 6, 0x1E, 0xFF, 0xCD, 0x05, 0x00, 0x32, 0x01, 0x02,
        0xC3, 0x00, 0x00,
    ])
    ours, _cpm = both(program, "key", script=b"\x91")
    assert peek(ours, 0x200) == 0xFF
    assert peek(ours, 0x201) == 0x0B


def test_adm3a_screen_matches_the_cpm_byte_stream():
    sequence = [0x1A, 0x1B, ord("="), 32 + 2, 32 + 5, ord("Z"), 0x0A]
    program = bytearray()
    for value in sequence:
        program += bytes([0x0E, 6, 0x1E, value, 0xCD, 0x05, 0x00])
    program += bytes([0xC3, 0x00, 0x00])
    ours, cpm = both(bytes(program), "adm")
    assert ours.exit_reason == "exit"
    assert screen(ours) == adm(bytes(cpm.console.output))
    assert screen(ours)[2 * 80 + 5] == ord("Z")
    assert screen(ours)[0] == 0x20
    assert not any(ours.bank(4)[:SCREEN])


def test_read_buffer():
    program = bytes([
        0x21, 0x80, 0x00, 0x36, 20,
        0x0E, 10, 0x11, 0x80, 0x00, 0xCD, 0x05, 0x00,
        0xC3, 0x00, 0x00,
    ])
    ours, cpm = both(program, "line", script=b"Hi\r")
    assert mem(ours, 0x81) == mem(cpm, 0x81) == 2
    assert mem(ours, 0x82) == ord("H") and mem(ours, 0x83) == ord("i")


def test_sequential_and_random_read_into_the_bank4_window():
    data = bytes(i & 0xFF for i in range(300))
    sequential = bytes([
        0x0E, 15, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00, 0x32, 0x00, 0x03,
        0x0E, 26, 0x11, 0x00, 0x40, 0xCD, 0x05, 0x00,
        0x0E, 20, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00, 0x32, 0x01, 0x03,
        0xC3, 0x00, 0x00,
    ])
    ours, cpm = both(sequential, "readf data.bin", files={"DATA.BIN": data})
    assert mem(ours, 0x300) == mem(cpm, 0x300) == 0
    assert bytes(mem(ours, 0x4000 + i) for i in range(128)) == data[:128]
    assert bytes(mem(cpm, 0x4000 + i) for i in range(128)) == data[:128]
    random_read = bytes([
        0x21, 0x5C + 33, 0x00, 0x36, 1, 0x23, 0x36, 0, 0x23, 0x36, 0,
        0x0E, 15, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00,
        0x0E, 26, 0x11, 0x00, 0x40, 0xCD, 0x05, 0x00,
        0x0E, 33, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00, 0x32, 0x00, 0x03,
        0xC3, 0x00, 0x00,
    ])
    ours, cpm = both(random_read, "rand data.bin", files={"DATA.BIN": data})
    assert mem(ours, 0x300) == 0
    got = bytes(mem(ours, 0x4000 + i) for i in range(128))
    expected = bytes(mem(cpm, 0x4000 + i) for i in range(128))
    assert got == expected == data[128:256]


def test_make_write_close_matches_cpm_bytes():
    program = bytes([
        0x0E, 22, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00,
        0x0E, 26, 0x11, 0x00, 0x02, 0xCD, 0x05, 0x00,
        0x21, 0x00, 0x02, 0x36, 0x11, 0x23, 0x7D, 0xFE, 0x80, 0xC2, 0x13, 0x01,
        0x0E, 21, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00, 0x32, 0x00, 0x03,
        0x0E, 16, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00,
        0xC3, 0x00, 0x00,
    ])
    ours, cpm = both(program, "wr out.dat")
    assert mem(ours, 0x300) == mem(cpm, 0x300) == 0
    assert (ours.fs.root / "OUT.DAT").read_bytes() == (cpm.fs.root / "OUT.DAT").read_bytes()
    assert (ours.fs.root / "OUT.DAT").read_bytes() == bytes([0x11]) * 128


def test_file_size_and_disk_parameter_block():
    data = bytes(range(128)) * 3
    size = bytes([
        0x0E, 35, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00,
        0xC3, 0x00, 0x00,
    ])
    ours, cpm = both(size, "sz data.bin", files={"DATA.BIN": data})
    assert [mem(ours, 0x5C + 33 + i) for i in range(3)] == [3, 0, 0]
    assert [mem(cpm, 0x5C + 33 + i) for i in range(3)] == [3, 0, 0]
    dpb = bytes([
        0x0E, 31, 0xCD, 0x05, 0x00,
        0x22, 0x00, 0x03,
        0xC3, 0x00, 0x00,
    ])
    ours, _cpm = both(dpb, "dpb")
    assert mem(ours, 0x300) == 0x00 and mem(ours, 0x301) == 0xF0
    assert bytes(peek(ours, 0xF000 + i) for i in range(15)) == bytes([
        0x1A, 0x00, 0x03, 0x07, 0x00, 0xF2, 0x00, 0x3F, 0x00,
        0xC0, 0x00, 0x10, 0x00, 0x02, 0x00,
    ])


def test_list_output_and_current_drive():
    program = bytes([
        0x0E, 5, 0x1E, ord("Q"), 0xCD, 0x05, 0x00,
        0x0E, 25, 0xCD, 0x05, 0x00, 0x32, 0x00, 0x02,
        0xC3, 0x00, 0x00,
    ])
    ours, cpm = both(program, "lst")
    assert bytes(ours.console.printer) == bytes(cpm.console.printer) == b"Q"
    assert mem(ours, 0x200) == mem(cpm, 0x200) == 0


def test_other_user_number_stops_and_names_the_function():
    program = bytes([0x0E, 32, 0x1E, 1, 0xCD, 0x05, 0x00, 0xC3, 0x00, 0x00])
    ours = run_loaded(Path(tempfile.mkdtemp()), program, tail="usr")
    assert ours.exit_reason == "exit"
    assert ours.memory[BASE + STOPPED] == 1
    assert ours.memory[BASE + REASON] == REASON_USER
    assert ours.memory[BASE + FUNC] == 32
    assert "20 07" in ours.console.text()


def test_loader_places_the_program_and_leaves_bank_zero_alone():
    program = bytes([0x3E, 0x2A, 0x32, 0x00, 0x02, 0xC3, 0x00, 0x00])
    root = Path(tempfile.mkdtemp())
    (root / "TINY.COM").write_bytes(program)
    from bench.sim.dos65 import DOS65Machine
    machine = DOS65Machine(root)
    machine.bank(4)[0] = 0x55
    machine.memory[0] = 0x4C
    machine.load(COM, "tiny")
    machine.run(2_000_000)
    assert machine.exit_reason == "exit"
    assert peek(machine, 0x200) == 0x2A
    assert machine.speed_log == []
    assert machine.memory[0] == 0x4C
    assert 0 not in machine.banks
    assert machine.bank(4)[0] == 0x55
    assert peek(machine, 6) == 0x00 and peek(machine, 7) == 0xE0
    assert peek(machine, 0x5D) == ord(" ")


def test_delete_file_matches_cpm():
    program = bytes([
        0x0E, 19, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00, 0x32, 0x00, 0x03,
        0x0E, 19, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00, 0x32, 0x01, 0x03,
        0xC3, 0x00, 0x00,
    ])
    ours, cpm = both(program, "del victim.dat", files={"VICTIM.DAT": b"x" * 128})
    assert [mem(ours, 0x300), mem(ours, 0x301)] == [mem(cpm, 0x300), mem(cpm, 0x301)]
    assert mem(ours, 0x300) == 0 and mem(ours, 0x301) == 0xFF   # second delete: not found
    assert not (ours.fs.root / "VICTIM.DAT").exists()
    assert not (cpm.fs.root / "VICTIM.DAT").exists()


def test_random_write_matches_cpm_bytes():
    program = bytes([
        0x21, 0x7D, 0x00, 0x36, 1, 0x23, 0x36, 0, 0x23, 0x36, 0,
        0x0E, 22, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00,
        0x0E, 26, 0x11, 0x00, 0x40, 0xCD, 0x05, 0x00,
        0x21, 0x00, 0x40, 0x36, 0x77, 0x23, 0x7D, 0xFE, 0x80, 0xC2, 0x1E, 0x01,
        0x0E, 34, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00, 0x32, 0x00, 0x03,
        0x0E, 16, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00,
        0xC3, 0x00, 0x00,
    ])
    ours, cpm = both(program, "rw out.dat")
    assert mem(ours, 0x300) == mem(cpm, 0x300) == 0
    ours_file = (ours.fs.root / "OUT.DAT").read_bytes()
    assert ours_file == (cpm.fs.root / "OUT.DAT").read_bytes()
    assert ours_file[128:256] == bytes([0x77]) * 128


def test_unsupported_function_30_stops():
    program = bytes([0x0E, 30, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00, 0xC3, 0x00, 0x00])
    ours = run_loaded(Path(tempfile.mkdtemp()), program, tail="f30")
    assert ours.memory[BASE + STOPPED] == 1
    assert ours.memory[BASE + FUNC] == 30


def test_missing_program_file_is_reported_and_nothing_is_run():
    from bench.sim.dos65 import DOS65Machine
    machine = DOS65Machine(Path(tempfile.mkdtemp()))
    machine.load(COM, "nosuch")
    machine.run(2_000_000)
    assert machine.exit_reason == "exit"
    assert machine.console.text().endswith(" 0A")     # reason 10: file not found
