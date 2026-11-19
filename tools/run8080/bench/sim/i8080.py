"""Intel 8080 simulator in pure Python.

Flag semantics follow the documented 8080 behaviour (as validated by
TST8080, 8080PRE, CPUTEST and 8080EXM):
  AC after ADD/ADC: carry out of bit 3
  AC after SUB/SBB/CMP: inverted borrow out of bit 4 of (a ^ b ^ result)
  AC after ANA: ((a | b) & 8) != 0, after XRA/ORA: 0
"""

from __future__ import annotations

from typing import Callable

PARITY = [1 - (bin(i).count("1") & 1) for i in range(256)]


class Halted(Exception):
    pass


class CPU8080:
    def __init__(self, memory: bytearray | None = None):
        self.mem = memory if memory is not None else bytearray(65536)
        self.a = self.b = self.c = self.d = self.e = self.h = self.l = 0
        self.sp = 0
        self.pc = 0
        self.sf = self.zf = self.hf = self.pf = self.cf = 0
        self.halted = False
        self.cycles = 0
        self.steps = 0
        self.traps: dict[int, Callable[["CPU8080"], None]] = {}
        self.executed: set[int] | None = None       # coverage when not None
        self.write_hook: Callable[[int, int], None] | None = None
        self.port_out: Callable[[int, int], None] = lambda port, value: None
        self.port_in: Callable[[int], int] = lambda port: 0
        self._ops = [self._make(op) for op in range(256)]

    # ----- register helpers -------------------------------------------------
    @property
    def f(self) -> int:
        return (self.sf << 7 | self.zf << 6 | self.hf << 4 | self.pf << 2
                | 2 | self.cf)

    @f.setter
    def f(self, value: int) -> None:
        self.sf = value >> 7 & 1
        self.zf = value >> 6 & 1
        self.hf = value >> 4 & 1
        self.pf = value >> 2 & 1
        self.cf = value & 1

    def get_pair(self, rp: str) -> int:
        if rp == "B":
            return self.b << 8 | self.c
        if rp == "D":
            return self.d << 8 | self.e
        if rp == "H":
            return self.h << 8 | self.l
        if rp == "SP":
            return self.sp
        return self.a << 8 | self.f

    def set_pair(self, rp: str, value: int) -> None:
        value &= 0xFFFF
        if rp == "B":
            self.b, self.c = value >> 8, value & 0xFF
        elif rp == "D":
            self.d, self.e = value >> 8, value & 0xFF
        elif rp == "H":
            self.h, self.l = value >> 8, value & 0xFF
        elif rp == "SP":
            self.sp = value
        else:
            self.a, self.f = value >> 8, value & 0xFF

    @property
    def hl(self) -> int:
        return self.h << 8 | self.l

    @property
    def de(self) -> int:
        return self.d << 8 | self.e

    @property
    def bc(self) -> int:
        return self.b << 8 | self.c

    def read_word(self, addr: int) -> int:
        return self.mem[addr & 0xFFFF] | self.mem[(addr + 1) & 0xFFFF] << 8

    def write(self, addr: int, value: int) -> None:
        addr &= 0xFFFF
        if self.write_hook is not None:
            self.write_hook(addr, value)
        self.mem[addr] = value & 0xFF

    def write_word(self, addr: int, value: int) -> None:
        self.write(addr, value & 0xFF)
        self.write(addr + 1, value >> 8)

    def push(self, value: int) -> None:
        self.sp = (self.sp - 2) & 0xFFFF
        self.write_word(self.sp, value)

    def pop(self) -> int:
        value = self.read_word(self.sp)
        self.sp = (self.sp + 2) & 0xFFFF
        return value

    def state(self) -> dict:
        return {"a": self.a, "b": self.b, "c": self.c, "d": self.d, "e": self.e,
                "h": self.h, "l": self.l, "sp": self.sp, "pc": self.pc, "f": self.f}

    def set_state(self, **regs) -> None:
        for name, value in regs.items():
            setattr(self, name, value)

    # ----- execution --------------------------------------------------------
    def step(self) -> None:
        pc = self.pc
        trap = self.traps.get(pc)
        if trap is not None:
            trap(self)
            return
        if self.executed is not None:
            self.executed.add(pc)
        op = self.mem[pc]
        self.pc = (pc + 1) & 0xFFFF
        self.steps += 1
        self._ops[op]()

    def run(self, max_steps: int | None = None) -> None:
        steps = 0
        while not self.halted:
            self.step()
            steps += 1
            if max_steps is not None and steps >= max_steps:
                return

    def _fetch8(self) -> int:
        value = self.mem[self.pc]
        self.pc = (self.pc + 1) & 0xFFFF
        return value

    def _fetch16(self) -> int:
        value = self.mem[self.pc] | self.mem[(self.pc + 1) & 0xFFFF] << 8
        self.pc = (self.pc + 2) & 0xFFFF
        return value

    def _get_reg(self, index: int) -> int:
        if index == 6:
            return self.mem[self.h << 8 | self.l]
        return getattr(self, "bcdehl_a"[index])

    def _set_reg(self, index: int, value: int) -> None:
        if index == 6:
            self.write(self.h << 8 | self.l, value)
        else:
            setattr(self, "bcdehl_a"[index], value & 0xFF)

    def _szp(self, value: int) -> None:
        self.sf = value >> 7
        self.zf = 1 if value == 0 else 0
        self.pf = PARITY[value]

    def _add(self, value: int, carry: int) -> None:
        a = self.a
        result = a + value + carry
        self.hf = ((a ^ value ^ result) >> 4) & 1
        self.cf = result >> 8 & 1
        self.a = result & 0xFF
        self._szp(self.a)

    def _sub(self, value: int, borrow: int, store: bool = True) -> None:
        a = self.a
        result = a - value - borrow
        self.cf = 1 if result < 0 else 0
        result &= 0xFF
        self.hf = 0 if ((a ^ value ^ result) & 0x10) else 1
        self._szp(result)
        if store:
            self.a = result

    def _alu(self, kind: int, value: int) -> None:
        if kind == 0:
            self._add(value, 0)
        elif kind == 1:
            self._add(value, self.cf)
        elif kind == 2:
            self._sub(value, 0)
        elif kind == 3:
            self._sub(value, self.cf)
        elif kind == 4:
            self.hf = 1 if ((self.a | value) & 0x08) else 0
            self.a &= value
            self.cf = 0
            self._szp(self.a)
        elif kind == 5:
            self.a ^= value
            self.cf = self.hf = 0
            self._szp(self.a)
        elif kind == 6:
            self.a |= value
            self.cf = self.hf = 0
            self._szp(self.a)
        else:
            self._sub(value, 0, store=False)

    def _cond(self, index: int) -> bool:
        if index == 0:
            return not self.zf
        if index == 1:
            return bool(self.zf)
        if index == 2:
            return not self.cf
        if index == 3:
            return bool(self.cf)
        if index == 4:
            return not self.pf
        if index == 5:
            return bool(self.pf)
        if index == 6:
            return not self.sf
        return bool(self.sf)

    def _daa(self) -> None:
        a = self.a
        correction = 0
        carry = self.cf
        low, high = a & 0x0F, a >> 4
        if self.hf or low > 9:
            correction |= 0x06
        if self.cf or high > 9 or (high >= 9 and low > 9):
            correction |= 0x60
            carry = 1
        self._add(correction, 0)
        self.cf = carry

    def _make(self, op: int) -> Callable[[], None]:
        s = self
        pairs = ["B", "D", "H", "SP"]
        if op & 0xC0 == 0x40:
            if op == 0x76:
                def hlt():
                    s.halted = True
                    s.pc = (s.pc - 1) & 0xFFFF
                return hlt
            dst, src = op >> 3 & 7, op & 7
            return lambda: s._set_reg(dst, s._get_reg(src))
        if op & 0xC0 == 0x80:
            kind, src = op >> 3 & 7, op & 7
            return lambda: s._alu(kind, s._get_reg(src))
        if op & 0xC7 == 0xC6:
            kind = op >> 3 & 7
            return lambda: s._alu(kind, s._fetch8())
        if op & 0xC7 == 0x06:
            dst = op >> 3 & 7
            return lambda: s._set_reg(dst, s._fetch8())
        if op & 0xC7 == 0x04:
            r = op >> 3 & 7

            def inr():
                value = (s._get_reg(r) + 1) & 0xFF
                s.hf = 1 if value & 0x0F == 0 else 0
                s._szp(value)
                s._set_reg(r, value)
            return inr
        if op & 0xC7 == 0x05:
            r = op >> 3 & 7

            def dcr():
                value = (s._get_reg(r) - 1) & 0xFF
                s.hf = 0 if value & 0x0F == 0x0F else 1
                s._szp(value)
                s._set_reg(r, value)
            return dcr
        if op & 0xCF == 0x01:
            rp = pairs[op >> 4 & 3]
            return lambda: s.set_pair(rp, s._fetch16())
        if op & 0xCF == 0x09:
            rp = pairs[op >> 4 & 3]

            def dad():
                result = s.hl + s.get_pair(rp)
                s.cf = result >> 16
                s.set_pair("H", result)
            return dad
        if op & 0xCF == 0x03:
            rp = pairs[op >> 4 & 3]
            return lambda: s.set_pair(rp, s.get_pair(rp) + 1)
        if op & 0xCF == 0x0B:
            rp = pairs[op >> 4 & 3]
            return lambda: s.set_pair(rp, s.get_pair(rp) - 1)
        if op & 0xC7 == 0xC0:
            cc = op >> 3 & 7

            def rcc():
                if s._cond(cc):
                    s.pc = s.pop()
            return rcc
        if op & 0xC7 == 0xC2:
            cc = op >> 3 & 7

            def jcc():
                target = s._fetch16()
                if s._cond(cc):
                    s.pc = target
            return jcc
        if op & 0xC7 == 0xC4:
            cc = op >> 3 & 7

            def ccc():
                target = s._fetch16()
                if s._cond(cc):
                    s.push(s.pc)
                    s.pc = target
            return ccc
        if op & 0xC7 == 0xC7:
            vector = op & 0x38

            def rst():
                s.push(s.pc)
                s.pc = vector
            return rst
        if op & 0xCF == 0xC1:
            rp = ["B", "D", "H", "PSW"][op >> 4 & 3]
            return lambda: s.set_pair(rp, s.pop())
        if op & 0xCF == 0xC5:
            rp = ["B", "D", "H", "PSW"][op >> 4 & 3]
            return lambda: s.push(s.get_pair(rp))
        if op in (0x00, 0x08, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38, 0xF3, 0xFB):
            return lambda: None
        if op in (0xC3, 0xCB):
            def jmp():
                s.pc = s._fetch16()
            return jmp
        if op in (0xC9, 0xD9):
            def ret():
                s.pc = s.pop()
            return ret
        if op in (0xCD, 0xDD, 0xED, 0xFD):
            def call():
                target = s._fetch16()
                s.push(s.pc)
                s.pc = target
            return call

        def stax_b():
            s.write(s.bc, s.a)

        def stax_d():
            s.write(s.de, s.a)

        def ldax_b():
            s.a = s.mem[s.bc]

        def ldax_d():
            s.a = s.mem[s.de]

        def shld():
            s.write_word(s._fetch16(), s.hl)

        def lhld():
            s.set_pair("H", s.read_word(s._fetch16()))

        def sta():
            s.write(s._fetch16(), s.a)

        def lda():
            s.a = s.mem[s._fetch16()]

        def rlc():
            s.cf = s.a >> 7
            s.a = (s.a << 1 | s.cf) & 0xFF

        def rrc():
            s.cf = s.a & 1
            s.a = s.a >> 1 | s.cf << 7

        def ral():
            carry = s.cf
            s.cf = s.a >> 7
            s.a = (s.a << 1 | carry) & 0xFF

        def rar():
            carry = s.cf
            s.cf = s.a & 1
            s.a = s.a >> 1 | carry << 7

        def cma():
            s.a ^= 0xFF

        def stc():
            s.cf = 1

        def cmc():
            s.cf ^= 1

        def out():
            s.port_out(s._fetch8(), s.a)

        def inp():
            s.a = s.port_in(s._fetch8()) & 0xFF

        def xthl():
            value = s.read_word(s.sp)
            s.write_word(s.sp, s.hl)
            s.set_pair("H", value)

        def pchl():
            s.pc = s.hl

        def xchg():
            s.d, s.h = s.h, s.d
            s.e, s.l = s.l, s.e

        def sphl():
            s.sp = s.hl

        table = {0x02: stax_b, 0x12: stax_d, 0x0A: ldax_b, 0x1A: ldax_d,
                 0x22: shld, 0x2A: lhld, 0x32: sta, 0x3A: lda, 0x07: rlc,
                 0x0F: rrc, 0x17: ral, 0x1F: rar, 0x27: s._daa, 0x2F: cma,
                 0x37: stc, 0x3F: cmc, 0xD3: out, 0xDB: inp, 0xE3: xthl,
                 0xE9: pchl, 0xEB: xchg, 0xF9: sphl}
        return table[op]
