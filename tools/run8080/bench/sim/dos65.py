"""DOS/65 emulator: py65 (NMOS 6502) plus PEM and SIM written in Python.

PEM calls are intercepted at PEM_START (reached through JMP at $103), SIM
calls at the entries of the SIM jump table.  The Mega65 specific parts used
by translated programs with --target mega65 are emulated as well:
  LDZ #imm ($A3) and MAP ($5C) select whether I/O is visible,
  absolute STA/STX/STY to $D000-$DFFF go to I/O registers while I/O is
  mapped in, STA $D700 starts a DMAgic job (F018B list, 12 bytes) between
  banks.
"""

from __future__ import annotations

from pathlib import Path

from py65.devices.mpu6502 import MPU

from .. import dos65 as d
from .devices import Console, InputExhausted, ProgramExit, RawDisk, parse_command_tail
from .gs import step as gs_step
from .hostfs import HostFS

CCM_RETURN = d.CCM_START          # RTS from the program lands here
DCB_A = d.SIM_START + 0x100
ALLOC_MAP_A = DCB_A + 0x20


class DOS65Machine:
    def __init__(self, root: Path, console: Console | None = None,
                 disk: RawDisk | None = None):
        self.memory = bytearray(65536)
        self.mpu = MPU(memory=self.memory)
        self.fs = HostFS(root)
        self.console = console or Console()
        self.disk = disk or RawDisk()
        self.dma = d.DEFAULT_BUFFER
        self.iostat = 0
        self.list_echo = 0
        self.read_only = 0
        self.pem_log: list[tuple[int, int]] = []
        self.exit_reason = ""
        self.steps = 0
        self.banks: dict[int, bytearray] = {d.MEGA65_DOS65_BANK: self.memory}
        self.z_register = 0
        self.io_mapped = False
        self.io = bytearray(0x1000)          # $D000-$DFFF while I/O is mapped in
        self.dma_jobs: list[tuple] = []
        self.b = 0
        self.attic = bytearray(8192)
        self.attic_fault = False
        self.speed = 0
        self.speed_log: list[int] = []
        self._sim_track = self._sim_sector = 0
        self._sim_dma = d.DEFAULT_BUFFER
        self._sim_drive = 0
        self.traps = {d.PEM_START: self._pem_trap, CCM_RETURN: self._exit_trap}
        mem = self.memory
        sim = d.SIM_START
        mem[d.BOOT_VECTOR:d.BOOT_VECTOR + 3] = bytes([0x4C, (sim + 3) & 0xFF, (sim + 3) >> 8])
        mem[d.PEM_VECTOR:d.PEM_VECTOR + 3] = bytes([0x4C, d.PEM_START & 0xFF, d.PEM_START >> 8])
        for offset in range(0, 54, 3):
            mem[sim + offset] = 0x60
            self.traps[sim + offset] = (lambda o=offset: self._sim_trap(o))
        sysdef = sim + d.SIM_CONSOLE_DEFINITION_OFFSET
        mem[sysdef:sysdef + 11] = bytes([0, 8, 10, 29, 1, 18, 25, 80, 12, 19, 0])
        self._write_dcb()

    def _write_dcb(self) -> None:
        records = (self.disk.tracks - 2) * self.disk.sectors
        max_block = records // 8 - 1
        words = [max_block, self.disk.sectors, 2]
        dcb = bytearray()
        for word in words:
            dcb += bytes([word & 0xFF, word >> 8])
        dcb += bytes([0])                                  # 1K blocks
        dcb += bytes([63, 0])                              # max directory number
        dcb += bytes([ALLOC_MAP_A & 0xFF, ALLOC_MAP_A >> 8])
        dcb += bytes([0])                                  # do checksums
        dcb += bytes([(ALLOC_MAP_A + 0x40) & 0xFF, (ALLOC_MAP_A + 0x40) >> 8])
        self.memory[DCB_A:DCB_A + d.DCB_SIZE] = dcb

    # ----- loading and running ---------------------------------------------
    def load(self, program: bytes, tail: str = "", origin: int = d.TEA) -> None:
        mem = self.memory
        mem[origin:origin + len(program)] = program
        fcb1, fcb2, buffer = parse_command_tail(tail)
        mem[d.DEFAULT_FCB:d.DEFAULT_FCB + 16] = fcb1
        mem[d.DEFAULT_FCB + 16:d.DEFAULT_FCB + 32] = fcb2
        mem[d.DEFAULT_FCB + 32] = 0
        mem[d.DEFAULT_BUFFER:d.DEFAULT_BUFFER + len(buffer)] = buffer
        mem[d.DEFAULT_BUFFER + len(buffer)] = 0
        mpu = self.mpu
        mpu.sp = 0xFF
        self._push((CCM_RETURN - 1) >> 8)
        self._push((CCM_RETURN - 1) & 0xFF)
        mpu.pc = origin

    def bank(self, number: int) -> bytearray:
        return self.banks.setdefault(number, bytearray(65536))

    def run(self, max_steps: int = 200_000_000) -> str:
        mpu, mem, traps = self.mpu, self.memory, self.traps
        steps = 0
        try:
            while steps < max_steps:
                pc = mpu.pc
                trap = traps.get(pc)
                if trap is not None:
                    trap()
                    steps += 1
                    continue
                if mem[pc] == 0x00:
                    self.exit_reason = "brk"
                    self.steps += steps
                    return self.exit_reason
                if not gs_step(self):
                    self.exit_reason = f"gs:{pc:04X}:{mem[pc]:02X}"
                    self.steps += steps
                    return self.exit_reason
                steps += 1
            self.exit_reason = "steps"
        except ProgramExit:
            self.exit_reason = "exit"
        except InputExhausted:
            self.exit_reason = "input"
        self.steps += steps
        return self.exit_reason

    def note_speed(self, value: int) -> None:
        """A write to physical address 0 sets the MEGA65 speed override.

        The byte is not stored, and it cannot be read back.  65 forces
        40.5 MHz.  64 cancels the override.
        """
        self.speed = value & 0xFF
        self.speed_log.append(self.speed)

    def flat_read(self, addr: int) -> int:
        top = (addr >> 24) & 0xFF
        bank = (addr >> 16) & 0xFF
        off = addr & 0xFFFF
        if top == 0x08:
            if off >= len(self.attic):
                self.attic_fault = True
                return 0xFF
            return self.attic[off]
        if top == 0:
            return self.bank(bank & 0x0F)[off]
        self.attic_fault = True
        return 0xFF

    def flat_write(self, addr: int, value: int) -> None:
        top = (addr >> 24) & 0xFF
        bank = (addr >> 16) & 0xFF
        off = addr & 0xFFFF
        if top == 0x08:
            if off >= len(self.attic):
                self.attic_fault = True
                return
            self.attic[off] = value & 0xFF
            return
        if top == 0:
            self.bank(bank & 0x0F)[off] = value & 0xFF
            return
        self.attic_fault = True

    @staticmethod
    def _dma_addr(mb: int, bank: int, offset: int) -> int:
        return ((mb & 0xFF) << 20) | ((bank & 0x0F) << 16) | (offset & 0xFFFF)

    # ----- 6502 helpers ----------------------------------------------------
    def _push(self, value: int) -> None:
        self.memory[0x100 + self.mpu.sp] = value & 0xFF
        self.mpu.sp = (self.mpu.sp - 1) & 0xFF

    def _pull(self) -> int:
        self.mpu.sp = (self.mpu.sp + 1) & 0xFF
        return self.memory[0x100 + self.mpu.sp]

    def _rts(self) -> None:
        low = self._pull()
        high = self._pull()
        self.mpu.pc = ((high << 8 | low) + 1) & 0xFFFF

    def _set_nz(self, value: int) -> None:
        p = self.mpu.p & ~(self.mpu.NEGATIVE | self.mpu.ZERO)
        if value & 0x80:
            p |= self.mpu.NEGATIVE
        if value == 0:
            p |= self.mpu.ZERO
        self.mpu.p = p

    def _exit_trap(self) -> None:
        raise ProgramExit()

    # ----- DMAgic ---------------------------------------------------------
    def _dmagic(self, low: int) -> None:
        io = self.io
        list_addr = io[d.DMAGIC_ADDR_HIGH - 0xD000] << 8 | low
        list_bank = self.bank(io[d.DMAGIC_ADDR_BANK - 0xD000] & 0x0F)
        self._run_dma(bytes(list_bank[list_addr:list_addr + 12]), 0, 0)

    def _dmagic_enhanced(self, low: int) -> None:
        """Enhanced list: option bytes, then a 12-byte F018A body.

        Option $80 (source) or $81 (destination) followed by the megabyte
        number selects bits 20-27 of the 28-bit address, as in the real
        DMAgic and in xemu: $80 selects Attic RAM at $8000000.  $00 ends the options.  The job is started by writing
        the list address low byte to $D705.
        """
        io = self.io
        list_addr = io[0xD701 - 0xD000] << 8 | (low & 0xFF)
        list_bank = self.bank(io[0xD702 - 0xD000] & 0x0F)
        index = list_addr
        src_mb = dst_mb = 0
        for _ in range(16):
            opt = list_bank[index]
            index = (index + 1) & 0xFFFF
            if opt in (0x00, 0x0A, 0x0B):
                break
            if opt in (0x80, 0x81):
                mb = list_bank[index]
                index = (index + 1) & 0xFFFF
                if opt == 0x80:
                    src_mb = mb
                else:
                    dst_mb = mb
            else:
                break
        self._run_dma(bytes(list_bank[index:index + 12]), src_mb, dst_mb)

    def _run_dma(self, job: bytes, src_mb: int, dst_mb: int) -> None:
        if len(job) < 11:
            return
        command = job[0] & 0x03
        count = job[1] | job[2] << 8 or 0x10000
        src = job[3] | job[4] << 8
        src_bank = job[5] & 0x0F
        dst = job[6] | job[7] << 8
        dst_bank = job[8] & 0x0F
        self.dma_jobs.append((command, count, src_mb, src_bank, src,
                              dst_mb, dst_bank, dst))
        if command == 3:
            fill = job[3]
            for i in range(count):
                self.flat_write(self._dma_addr(dst_mb, dst_bank, dst + i), fill)
        elif command == 0:
            for i in range(count):
                value = self.flat_read(self._dma_addr(src_mb, src_bank, src + i))
                self.flat_write(self._dma_addr(dst_mb, dst_bank, dst + i), value)

    # ----- PEM --------------------------------------------------------------
    def _pem_trap(self) -> None:
        mpu, mem, fs, con = self.mpu, self.memory, self.fs, self.console
        function = mpu.x
        value = mpu.a
        address = mpu.y << 8 | mpu.a
        self.pem_log.append((function, address))
        result = 0
        high = mpu.y
        if function == 0:
            raise ProgramExit()
        elif function == 1:
            result = con.read()
            if con.echoes(result):
                con.write_cooked(result)
        elif function == 2:
            con.write_cooked(value)
        elif function == 3:
            result = con.reader.pop(0) if con.reader else 0x1A
        elif function == 4:
            con.punch.append(value)
        elif function == 5:
            con.printer.append(value)
        elif function == 6:
            result = con.read()
        elif function == 7:
            result = mem[d.IOSTAT]
        elif function == 8:
            mem[d.IOSTAT] = value
        elif function == 9:
            addr = address
            while mem[addr] != ord("$"):
                con.write_cooked(mem[addr])
                addr = (addr + 1) & 0xFFFF
        elif function == 10:
            self._read_buffer(address)
        elif function == 11:
            result = con.input[0] if con.status() else 0
        elif function == 12:
            result = 1
        elif function == 13:
            fs.current_drive = 0
            self.dma = d.DEFAULT_BUFFER
        elif function == 14:
            fs.current_drive = value
        elif function == 15:
            result = fs.open(mem, address)
        elif function == 16:
            result = fs.close(mem, address)
        elif function == 17:
            result = fs.search_first(mem, address, self.dma)
        elif function == 18:
            result = fs.search_next(mem, self.dma)
        elif function == 19:
            result = fs.delete(mem, address)
        elif function == 20:
            result = fs.read_seq(mem, address, self.dma)
        elif function == 21:
            result = fs.write_seq(mem, address, self.dma)
        elif function == 22:
            result = fs.make(mem, address)
        elif function == 23:
            result = fs.rename(mem, address)
        elif function == 24:
            result = 1
        elif function == 25:
            result = fs.current_drive
        elif function == 26:
            self.dma = address
        elif function == 27:
            result, high = ALLOC_MAP_A & 0xFF, ALLOC_MAP_A >> 8
        elif function == 28:
            self.read_only |= 1 << fs.current_drive
        elif function == 29:
            result = self.read_only
        elif function == 30:
            self.list_echo = value
        elif function == 31:
            result = self.list_echo
        elif function in (32, 33):
            result, high = 0, 0
        elif function == 34:
            result, high = DCB_A & 0xFF, DCB_A >> 8
        elif function == 35:
            result, high = mpu.a, mpu.y
        else:
            result = 0
        mpu.a = result & 0xFF
        mpu.y = high & 0xFF
        mpu.x = 0xEE
        self._set_nz(mpu.a)
        self._rts()

    def _read_buffer(self, addr: int) -> None:
        mem, con = self.memory, self.console
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

    # ----- SIM --------------------------------------------------------------
    def _sim_trap(self, offset: int) -> None:
        mpu, con = self.mpu, self.console
        address = mpu.y << 8 | mpu.a
        if offset in (0, 3):
            raise ProgramExit()
        elif offset == 6:
            mpu.a = 0xFF if con.status() else 0
        elif offset == 9:
            mpu.a = con.read()
        elif offset == 12:
            con.write_raw(mpu.a)
        elif offset == 15:
            con.printer.append(mpu.a)
        elif offset == 18:
            con.punch.append(mpu.a)
        elif offset == 21:
            mpu.a = con.reader.pop(0) if con.reader else 0x1A
        elif offset == 24:
            self._sim_track = 0
        elif offset == 27:
            self._sim_drive = mpu.a & 7
            dcb = DCB_A if self._sim_drive == 0 else 0
            mpu.a, mpu.y = dcb & 0xFF, dcb >> 8
        elif offset == 30:
            self._sim_track = address
        elif offset == 33:
            self._sim_sector = address
        elif offset == 36:
            self._sim_dma = address
        elif offset == 39:
            data = self.disk.read(self._sim_track, self._sim_sector)
            if data is None:
                mpu.a = 1
            else:
                self.memory[self._sim_dma:self._sim_dma + 128] = data
                mpu.a = 0
        elif offset == 42:
            ok = self.disk.write(self._sim_track, self._sim_sector,
                                 bytes(self.memory[self._sim_dma:self._sim_dma + 128]))
            mpu.a = 0 if ok else 1
        elif offset == 45:
            mpu.a = 1
        elif offset == 48:
            mpu.x = 128
        elif offset == 51:
            pass
        self._set_nz(mpu.a)
        self._rts()


def run_dos65(program: bytes, root: Path, script: bytes = b"", tail: str = "",
              max_steps: int = 200_000_000, pace: int = 0) -> DOS65Machine:
    machine = DOS65Machine(root, Console(script, pace=pace))
    machine.load(program, tail)
    machine.run(max_steps)
    return machine
