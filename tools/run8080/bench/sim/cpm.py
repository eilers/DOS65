"""CP/M 2.2 emulator: 8080 simulator plus BDOS and BIOS written in Python."""

from __future__ import annotations

from pathlib import Path

from .devices import Console, InputExhausted, ProgramExit, RawDisk, parse_command_tail
from .hostfs import HostFS
from .i8080 import CPU8080

BDOS_ENTRY = 0xE406
BIOS_BASE = 0xF200
BIOS_STUBS = BIOS_BASE + 0x40
DPH_ADDR = BIOS_BASE + 0x80
DPB_ADDR = BIOS_BASE + 0xA0
DIRBUF_ADDR = BIOS_BASE + 0xC0
ALV_ADDR = BIOS_BASE + 0x140
CSV_ADDR = BIOS_BASE + 0x180


class CPMMachine:
    def __init__(self, root: Path, console: Console | None = None,
                 disk: RawDisk | None = None, cpu: CPU8080 | None = None):
        self.cpu = cpu or CPU8080()
        self.mem = self.cpu.mem
        self.fs = HostFS(root)
        self.console = console or Console()
        self.disk = disk or RawDisk()
        self.dma = 0x80
        self.iobyte = 0
        self.user = 0
        self.bdos_log: list[tuple[int, int]] = []
        self.exit_reason = ""
        self._disk_track = self._disk_sector = 0
        self._disk_dma = 0x80
        mem = self.mem
        mem[0:3] = bytes([0xC3, (BIOS_BASE + 3) & 0xFF, (BIOS_BASE + 3) >> 8])
        mem[5:8] = bytes([0xC3, BDOS_ENTRY & 0xFF, BDOS_ENTRY >> 8])
        mem[BDOS_ENTRY] = 0xC9
        self.cpu.traps[BDOS_ENTRY] = self._bdos_trap
        for i in range(17):
            # JMP table like a real BIOS (programs copy the targets), the
            # targets are trapped RET stubs
            stub = BIOS_STUBS + i
            mem[BIOS_BASE + 3 * i:BIOS_BASE + 3 * i + 3] = bytes([0xC3, stub & 0xFF, stub >> 8])
            mem[stub] = 0xC9
            self.cpu.traps[stub] = (lambda cpu, n=i: self._bios_trap(n))
        self._write_disk_tables()

    # ----- setup ------------------------------------------------------------
    def _write_disk_tables(self) -> None:
        """DPH and DPB describing self.disk (1K blocks, 64 directory entries,
        2 system tracks)."""
        mem = self.mem
        dph = [0, 0, 0, 0, DIRBUF_ADDR, DPB_ADDR, CSV_ADDR, ALV_ADDR]
        for i, word in enumerate(dph):
            mem[DPH_ADDR + 2 * i] = word & 0xFF
            mem[DPH_ADDR + 2 * i + 1] = word >> 8
        records = (self.disk.tracks - 2) * self.disk.sectors
        dsm = records // 8 - 1
        dpb = [self.disk.sectors & 0xFF, self.disk.sectors >> 8, 3, 7, 0,
               dsm & 0xFF, dsm >> 8, 63, 0, 0xC0, 0x00, 16, 0, 2, 0]
        mem[DPB_ADDR:DPB_ADDR + 15] = bytes(dpb)

    def load(self, program: bytes, tail: str = "", origin: int = 0x100) -> None:
        self.mem[origin:origin + len(program)] = program
        fcb1, fcb2, buffer = parse_command_tail(tail)
        self.mem[0x5C:0x6C] = fcb1
        self.mem[0x6C:0x7C] = fcb2
        self.mem[0x7C:0x80] = bytes(4)
        self.mem[0x80:0x80 + len(buffer)] = buffer
        cpu = self.cpu
        cpu.sp = BDOS_ENTRY - 0x20
        cpu.push(0x0000)
        cpu.pc = origin
        cpu.traps[0x0000] = self._warm_boot_trap

    def run(self, max_steps: int = 50_000_000) -> str:
        try:
            self.cpu.run(max_steps)
            self.exit_reason = "halt" if self.cpu.halted else "steps"
        except ProgramExit:
            self.exit_reason = "exit"
        except InputExhausted:
            self.exit_reason = "input"
        return self.exit_reason

    # ----- traps ------------------------------------------------------------
    def _warm_boot_trap(self, cpu: CPU8080) -> None:
        raise ProgramExit()

    def _return(self, value: int | None = None, word: int | None = None) -> None:
        cpu = self.cpu
        if word is not None:
            cpu.h, cpu.l = word >> 8 & 0xFF, word & 0xFF
            cpu.a, cpu.b = cpu.l, cpu.h
        elif value is not None:
            cpu.a = cpu.l = value & 0xFF
            cpu.b = cpu.h = 0
        cpu.pc = cpu.pop()

    def _bdos_trap(self, cpu: CPU8080) -> None:
        function, de, e = cpu.c, cpu.de, cpu.e
        self.bdos_log.append((function, de))
        mem, fs, con = self.mem, self.fs, self.console
        result: int | None = 0
        word = None
        if function == 0:
            raise ProgramExit()
        elif function == 1:
            result = con.read()
            if con.echoes(result):
                con.write_cooked(result)
        elif function == 2:
            con.write_cooked(e)
        elif function == 3:
            result = con.reader.pop(0) if con.reader else 0x1A
        elif function == 4:
            con.punch.append(e)
        elif function == 5:
            con.printer.append(e)
        elif function == 6:
            if e == 0xFF:
                result = con.read() if con.status() else 0
            elif e == 0xFE:
                result = 0xFF if con.status() else 0
            else:
                con.write_raw(e)
        elif function == 7:
            result = self.iobyte
        elif function == 8:
            self.iobyte = e
        elif function == 9:
            addr = de
            while mem[addr] != ord("$"):
                con.write_cooked(mem[addr])
                addr = (addr + 1) & 0xFFFF
        elif function == 10:
            self._read_buffer(de)
        elif function == 11:
            result = 0xFF if con.status() else 0
        elif function == 12:
            word = 0x0022
        elif function == 13:
            fs.current_drive = 0
            self.dma = 0x80
        elif function == 14:
            fs.current_drive = e
        elif function == 15:
            result = fs.open(mem, de)
        elif function == 16:
            result = fs.close(mem, de)
        elif function == 17:
            result = fs.search_first(mem, de, self.dma)
        elif function == 18:
            result = fs.search_next(mem, self.dma)
        elif function == 19:
            result = fs.delete(mem, de)
        elif function == 20:
            result = fs.read_seq(mem, de, self.dma)
        elif function == 21:
            result = fs.write_seq(mem, de, self.dma)
        elif function == 22:
            result = fs.make(mem, de)
        elif function == 23:
            result = fs.rename(mem, de)
        elif function == 24:
            word = 1
        elif function == 25:
            result = fs.current_drive
        elif function == 26:
            self.dma = de
        elif function == 27:
            word = ALV_ADDR
        elif function == 28:
            pass
        elif function == 29:
            word = 0
        elif function == 30:
            result = 0
        elif function == 31:
            word = DPB_ADDR
        elif function == 32:
            if e == 0xFF:
                result = self.user
            else:
                self.user = e & 0x0F
        elif function == 33:
            result = fs.read_random(mem, de, self.dma)
        elif function in (34, 40):
            result = fs.write_random(mem, de, self.dma)
        elif function == 35:
            result = fs.file_size(mem, de)
        elif function == 36:
            fs.set_random(mem, de)
        elif function == 37:
            result = 0
        else:
            result = 0
        self._return(result, word)

    def _read_buffer(self, addr: int) -> None:
        mem, con = self.mem, self.console
        maximum = mem[addr]
        count = 0
        while True:
            char = con.read()
            if char in (0x0D, 0x0A):
                con.write_raw(0x0D)
                break
            if char in (0x08, 0x7F):
                if count:
                    count -= 1
                    con.write_raw(0x08)
                    con.write_raw(0x20)
                    con.write_raw(0x08)
                continue
            if count < maximum:
                mem[addr + 2 + count] = char
                count += 1
                con.write_cooked(char)
        mem[addr + 1] = count

    def _bios_trap(self, entry: int) -> None:
        cpu, con = self.cpu, self.console
        result = None
        word = None
        if entry in (0, 1):
            raise ProgramExit()
        elif entry == 2:
            result = 0xFF if con.status() else 0
        elif entry == 3:
            result = con.read()
        elif entry == 4:
            con.write_raw(cpu.c)
        elif entry == 5:
            con.printer.append(cpu.c)
        elif entry == 6:
            con.punch.append(cpu.c)
        elif entry == 7:
            result = con.reader.pop(0) if con.reader else 0x1A
        elif entry == 8:
            self._disk_track = 0
        elif entry == 9:
            word = DPH_ADDR if cpu.c == 0 else 0
        elif entry == 10:
            self._disk_track = cpu.bc
        elif entry == 11:
            self._disk_sector = cpu.bc
        elif entry == 12:
            self._disk_dma = cpu.bc
        elif entry == 13:
            data = self.disk.read(self._disk_track, self._disk_sector)
            if data is None:
                result = 1
            else:
                self.mem[self._disk_dma:self._disk_dma + 128] = data
                result = 0
        elif entry == 14:
            ok = self.disk.write(self._disk_track, self._disk_sector,
                                 bytes(self.mem[self._disk_dma:self._disk_dma + 128]))
            result = 0 if ok else 1
        elif entry == 15:
            result = 0xFF
        elif entry == 16:
            word = cpu.bc
        if word is not None:
            cpu.h, cpu.l = word >> 8, word & 0xFF
        if result is not None:
            cpu.a = result & 0xFF
        cpu.pc = cpu.pop()


def run_cpm(program: bytes, root: Path, script: bytes = b"", tail: str = "",
            max_steps: int = 50_000_000, pace: int = 0, cpu: str = "8080") -> CPMMachine:
    from .z80 import CPUZ80
    machine = CPMMachine(root, Console(script, pace=pace),
                         cpu=CPUZ80() if cpu == "z80" else None)
    machine.load(program, tail)
    machine.run(max_steps)
    return machine
