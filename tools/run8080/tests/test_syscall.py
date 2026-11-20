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
    """The 80 by 24 grid as ASCII: screen codes $01-$1A are the lowercase letters."""
    raw = machine.bank(4)[SCREEN:SCREEN + SCREEN_BYTES]
    def decode(code):
        if 1 <= code <= 0x1A:
            return code + 0x60
        if code == 0x1E:
            return 0x5E          # the caret is stored as the up-arrow glyph
        return code
    return bytes(decode(code) for code in raw)


def adm(stream: bytes) -> bytes:
    """The same ADM-3A/ADM-31 rules run8080 applies to console output."""
    cells = bytearray(b" " * (80 * 24))
    row = col = state = 0

    def advance():
        nonlocal col
        col += 1
        if col == 80:
            col = 0
            linefeed()

    def put(value):
        cells[row * 80 + col] = value
        advance()

    def linefeed():
        nonlocal row
        if row < 23:
            row += 1
            return
        del cells[:80]
        cells.extend(b" " * 80)

    for byte in stream:
        if state == 1:
            state = 2 if byte == 0x3D else 0
            if byte in b"*+":
                cells[:] = b" " * len(cells)
                row = col = 0
            elif byte in b"Tt":
                cells[row * 80 + col:row * 80 + 80] = b" " * (80 - col)
            elif byte in b"Yy":
                cells[row * 80 + col:] = b" " * (len(cells) - row * 80 - col)
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
        elif byte == 0x08:
            col = max(0, col - 1)
        elif byte == 0x0B:
            row = max(0, row - 1)
        elif byte == 0x0C:
            advance()
        elif byte == 0x1E:
            row = col = 0
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
    # PETSCII from the MEGA65 keyboard: up, down, left, right.
    program = bytes([
        0x0E, 6, 0x1E, 0xFE, 0xCD, 0x05, 0x00, 0x32, 0x00, 0x02,
        0x0E, 6, 0x1E, 0xFF, 0xCD, 0x05, 0x00, 0x32, 0x01, 0x02,
        0x0E, 6, 0x1E, 0xFF, 0xCD, 0x05, 0x00, 0x32, 0x02, 0x02,
        0x0E, 6, 0x1E, 0xFF, 0xCD, 0x05, 0x00, 0x32, 0x03, 0x02,
        0x0E, 6, 0x1E, 0xFF, 0xCD, 0x05, 0x00, 0x32, 0x04, 0x02,
        0xC3, 0x00, 0x00,
    ])
    ours, _cpm = both(program, "key", script=bytes([0x91, 0x11, 0x9D, 0x1D]))
    assert peek(ours, 0x200) == 0xFF
    assert [peek(ours, 0x201 + i) for i in range(4)] == [0x0B, 0x0A, 0x08, 0x0C]


def test_startup_clears_the_screen_and_marks_the_cursor():
    # One caret, then back to DOS/65.  Screen code $1E is the up-arrow glyph.
    # curmark, just before the $C5 $7E tag, holds the blink and reverse attribute.
    program = bytes([0x0E, 6, 0x1E, ord("^"), 0xCD, 0x05, 0x00, 0xC3, 0x00, 0x00])
    ours, _cpm = both(bytes(program), "caret")
    assert ours.exit_reason == "exit"
    raw = ours.bank(4)[SCREEN:SCREEN + 80 * 50]
    assert raw[0] == 0x1E
    assert screen(ours)[0] == ord("^")
    assert set(raw[1:]) == {0x20}
    blob = bytes(ours.memory)
    assert blob[blob.find(bytes([0xC5, 0x7E])) - 1] == 0x30
    assert not ours.attic_fault


def test_lowercase_letters_are_stored_as_lowercase_screen_codes():
    program = bytearray()
    for value in b"aZz":
        program += bytes([0x0E, 6, 0x1E, value, 0xCD, 0x05, 0x00])
    program += bytes([0xC3, 0x00, 0x00])
    ours, _cpm = both(bytes(program), "lower")
    assert ours.exit_reason == "exit"
    assert bytes(ours.bank(4)[SCREEN:SCREEN + 3]) == bytes([0x01, 0x5A, 0x01 + 25])
    assert screen(ours)[:3] == b"aZz"


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


def test_adm31_erase_and_cursor_controls():
    # WordStar 4 is installed for the ADM-31: ESC * clears the screen,
    # ESC T erases to the end of the line, ESC Y to the end of the screen.
    def at(row, col):
        return b"\x1b=" + bytes([32 + row, 32 + col])
    stream = (b"\x1b*" + b"AAAAAAAAAA\r\n" * 6
              + at(1, 4) + b"\x1bT"                  # row 1 keeps AAAA
              + at(3, 2) + b"\x1bY"                  # rows 3.. keep AA on row 3
              + at(0, 3) + b"\x08\x08x"              # backspace twice: col 1
              + b"\x0cy" + b"\x0bz"                  # right, then up (stays row 0)
              + b"\x1e" + b"h" + b"\x1b(" + b"\x1b)" + b"\n" + b"L")
    program = bytearray()
    for value in stream:
        program += bytes([0x0E, 6, 0x1E, value, 0xCD, 0x05, 0x00])
    program += bytes([0xC3, 0x00, 0x00])
    ours, cpm = both(bytes(program), "adm31")
    grid = screen(ours)
    assert grid == adm(bytes(cpm.console.output))
    assert grid[0:6] == b"hxAyzA"
    assert grid[80:90] == b"ALAA      "             # line feed keeps the column
    assert grid[2 * 80:2 * 80 + 10] == b"AAAAAAAAAA"
    assert grid[3 * 80:3 * 80 + 10] == b"AA        "
    assert grid[4 * 80:] == b" " * (20 * 80)
    assert grid[80 + 1] == ord("L")


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


def test_random_read_past_the_first_extent():
    # Record 128 is the first record of the second extent (16 KB).
    data = bytes((i * 3) & 0xFF for i in range(129 * 128))
    program = bytes([
        0x21, 0x5C + 33, 0x00, 0x36, 128, 0x23, 0x36, 0, 0x23, 0x36, 0,
        0x0E, 15, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00,
        0x0E, 26, 0x11, 0x00, 0x40, 0xCD, 0x05, 0x00,
        0x0E, 33, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00, 0x32, 0x00, 0x03,
        0xC3, 0x00, 0x00,
    ])
    ours, cpm = both(program, "big data.bin", files={"DATA.BIN": data})
    assert mem(ours, 0x300) == mem(cpm, 0x300) == 0
    got = bytes(mem(ours, 0x4000 + i) for i in range(128))
    expected = bytes(mem(cpm, 0x4000 + i) for i in range(128))
    assert got == expected == data[128 * 128:129 * 128]


def test_bios_console_through_the_copied_jump_target():
    # Like WordStar 4: take the CONOUT target out of the BIOS jump table at
    # (0001)+10 and call it; CONST and CONIN are called through the table.
    sub = 0x012D
    program = bytes([
        0x06, 0x55,                     # MVI B,55H  (BIOS keeps B)
        0x2A, 0x01, 0x00,               # LHLD 0001  -> WBOOT entry
        0x11, 0x0A, 0x00,               # LXI D,10
        0x19,                           # DAD D      -> CONOUT jump operand
        0x5E, 0x23, 0x56, 0xEB,         # HL = CONOUT target
        0x22, (sub + 1) & 0xFF, sub >> 8,  # SHLD sub+1
        0x0E, ord("H"), 0xCD, sub & 0xFF, sub >> 8,
        0x0E, ord("I"), 0xCD, sub & 0xFF, sub >> 8,
        0x78, 0x32, 0x01, 0x02,         # MOV A,B / STA 0201
        0xCD, 0x06, 0xF2, 0x32, 0x00, 0x02,  # CALL CONST / STA 0200
        0xCD, 0x09, 0xF2, 0x32, 0x02, 0x02,  # CALL CONIN / STA 0202
        0xC3, 0x00, 0x00,
    ])
    assert len(program) == sub - 0x100
    program += bytes([0xCD, 0x00, 0x00, 0xC9])
    ours, cpm = both(program, "bios", script=b"\x91")
    assert screen(ours)[:2] == b"HI"
    assert bytes(cpm.console.output)[:2] == b"HI"
    assert peek(ours, 0x201) == 0x55
    assert peek(ours, 0x200) == 0xFF and cpm.mem[0x200] == 0xFF
    assert peek(ours, 0x202) == 0x0B
    assert mem(ours, 1) | mem(ours, 2) << 8 == 0xF203


def test_control_s_is_returned_by_the_bios():
    # PEM (the Primitive Execution Module) treats Control-S, byte $13, as
    # freeze and never returns it.  WordStar's cursor left is that key, so
    # the BIOS must read the SIM (System Interface Module) instead.
    program = bytes([0xCD, 0x09, 0xF2, 0x32, 0x00, 0x02, 0xC3, 0x00, 0x00])
    ours, _cpm = both(bytes(program), "ctl-s", script=b"\x13")
    assert ours.exit_reason == "exit"
    assert peek(ours, 0x200) == 0x13


def _queue_key(machine, code: int, modifier: int) -> None:
    """One key in the MEGA65 hardware queue: character, Commodore code, modifier."""
    machine.io[0x610] = code
    machine.io[0x619] = code
    machine.io[0x60A] = modifier


def test_control_s_is_taken_from_the_hardware_queue():
    # The MEGA65 ROM reader dequeues byte $13 when the control modifier is
    # present and then discards it.  Bit 7 of the modifier is set while the
    # queue is not empty.  The BIOS has to take that key itself.
    from bench.sim.dos65 import DOS65Machine

    program = bytes([
        0xCD, 0x06, 0xF2, 0x32, 0x00, 0x02,
        0xCD, 0x09, 0xF2, 0x32, 0x01, 0x02,
        0xC3, 0x00, 0x00,
    ])
    root = Path(tempfile.mkdtemp())
    (root / "CTL-S.COM").write_bytes(program)
    machine = DOS65Machine(root)
    _queue_key(machine, 0x13, 0x84)
    machine.load(COM, "ctl-s")
    machine.run(2_000_000)
    assert machine.exit_reason == "exit"
    assert peek(machine, 0x200) == 0xFF
    assert peek(machine, 0x201) == 0x13
    assert machine.io[0x610] == 0


def test_home_in_the_hardware_queue_is_left_for_the_rom():
    # HOME is also byte $13, but the control modifier is clear, so the ROM
    # returns it.  run8080 must not remove that key.
    from bench.sim.dos65 import DOS65Machine

    program = bytes([0xCD, 0x09, 0xF2, 0x32, 0x00, 0x02, 0xC3, 0x00, 0x00])
    root = Path(tempfile.mkdtemp())
    (root / "HOME.COM").write_bytes(program)
    machine = DOS65Machine(root)
    machine.console.input = bytearray(b"A")
    _queue_key(machine, 0x13, 0x80)
    machine.load(COM, "home")
    machine.run(2_000_000)
    assert peek(machine, 0x200) == ord("A")
    assert machine.io[0x610] == 0x13


def test_random_record_beyond_512_kb_returns_6():
    # Record 4096 would need the module byte, which DOS/65 does not have.
    program = bytes([
        0x21, 0x5C + 33, 0x00, 0x36, 0, 0x23, 0x36, 0x10, 0x23, 0x36, 0,
        0x0E, 15, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00,
        0x0E, 33, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00, 0x32, 0x00, 0x03,
        0x0E, 34, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00, 0x32, 0x01, 0x03,
        0xC3, 0x00, 0x00,
    ])
    ours, _cpm = both(program, "far data.bin", files={"DATA.BIN": bytes(128)})
    assert mem(ours, 0x300) == 6 and mem(ours, 0x301) == 6
    assert (ours.fs.root / "DATA.BIN").read_bytes() == bytes(128)


def test_random_read_past_the_end_of_the_file_returns_4():
    program = bytes([
        0x21, 0x5C + 33, 0x00, 0x36, 128, 0x23, 0x36, 0, 0x23, 0x36, 0,
        0x0E, 15, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00,
        0x0E, 33, 0x11, 0x5C, 0x00, 0xCD, 0x05, 0x00, 0x32, 0x00, 0x03,
        0xC3, 0x00, 0x00,
    ])
    ours, cpm = both(program, "end data.bin", files={"DATA.BIN": bytes(128)})
    assert mem(ours, 0x300) == mem(cpm, 0x300) == 4


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


def test_random_write_past_the_first_extent_matches_cpm_bytes():
    # Same as the record 1 write, but record 128 has to create the next extent.
    program = bytes([
        0x21, 0x7D, 0x00, 0x36, 128, 0x23, 0x36, 0, 0x23, 0x36, 0,
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
    assert ours_file[128 * 128:129 * 128] == bytes([0x77]) * 128


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
