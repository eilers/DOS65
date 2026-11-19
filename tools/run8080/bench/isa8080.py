"""Intel 8080 instruction set table shared by disassembler, simulator and
translator.

Operand kinds:
  imm8   8 bit immediate
  imm16  16 bit immediate (LXI): number, data address or code address
  addr   16 bit direct data address (LDA, STA, LHLD, SHLD)
  jump   16 bit code address (JMP, Jcc, CALL, Ccc)
  port   8 bit I/O port (IN, OUT)
"""

from __future__ import annotations

from dataclasses import dataclass, field

REGS = ["B", "C", "D", "E", "H", "L", "M", "A"]
PAIRS = ["B", "D", "H", "SP"]
PAIRS_PUSH = ["B", "D", "H", "PSW"]
CONDITIONS = ["NZ", "Z", "NC", "C", "PO", "PE", "P", "M"]
ALU = ["ADD", "ADC", "SUB", "SBB", "ANA", "XRA", "ORA", "CMP"]
ALU_IMM = ["ADI", "ACI", "SUI", "SBI", "ANI", "XRI", "ORI", "CPI"]

ALL_FLAGS = frozenset("SZAPC")
SZAP = frozenset("SZAP")
CARRY = frozenset("C")

# Condition -> flag it reads.
CONDITION_FLAG = {"NZ": "Z", "Z": "Z", "NC": "C", "C": "C",
                  "PO": "P", "PE": "P", "P": "S", "M": "S"}

_Z80_REG = {"B": "b", "C": "c", "D": "d", "E": "e", "H": "h", "L": "l",
            "M": "(hl)", "A": "a"}
_Z80_PAIR = {"B": "bc", "D": "de", "H": "hl", "SP": "sp", "PSW": "af"}
_Z80_ALU = {"ADD": "add a,", "ADC": "adc a,", "SUB": "sub ", "SBB": "sbc a,",
            "ANA": "and ", "XRA": "xor ", "ORA": "or ", "CMP": "cp "}


@dataclass(frozen=True)
class OpInfo:
    code: int
    name: str                 # Intel mnemonic without operands
    args: tuple = ()          # register / pair / condition arguments
    length: int = 1
    operand: str = ""         # see module doc
    z80: str = ""             # z80asm template, {n} / {nn} replaced
    flow: str = ""            # jump cjump call ccall ret cret rst pchl halt
    documented: bool = True
    reads: frozenset = field(default_factory=frozenset)
    writes: frozenset = field(default_factory=frozenset)
    prefix: bytes = b""       # Z80: CB, ED, DD, FD, DD CB, FD CB
    disp: bool = False        # Z80: signed displacement byte (IX+d)
    relative: bool = False    # Z80: JR/DJNZ, operand is PC relative

    @property
    def condition(self) -> str | None:
        return self.args[0] if self.flow in ("cjump", "ccall", "cret") else None

    def intel(self, operand_text: str = "") -> str:
        parts = [str(a) for a in self.args]
        if self.flow in ("cjump", "ccall", "cret"):
            text = self.name[0] + self.args[0]
            return f"{text} {operand_text}".strip()
        if self.name == "RST":
            return f"RST {self.args[0]}"
        if self.z80 and (self.prefix or self.relative or self.name in ("EXAF", "EXX")):
            return self.z80.replace("{nn}", operand_text or "nn").replace(
                "{n}", operand_text or "n").replace("{d}", "+d").upper()
        if operand_text:
            parts.append(operand_text)
        return f"{self.name} {','.join(parts)}".strip()


def _build() -> list[OpInfo]:
    table: list[OpInfo | None] = [None] * 256

    def put(code, **kw):
        table[code] = OpInfo(code=code, **kw)

    put(0x00, name="NOP", z80="nop")
    for code in (0x08, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38):
        put(code, name="NOP", z80="", documented=False)
    for i, rp in enumerate(PAIRS):
        put(0x01 | i << 4, name="LXI", args=(rp,), length=3, operand="imm16",
            z80=f"ld {_Z80_PAIR[rp]},{{nn}}")
        put(0x09 | i << 4, name="DAD", args=(rp,), z80=f"add hl,{_Z80_PAIR[rp]}",
            writes=CARRY)
        put(0x03 | i << 4, name="INX", args=(rp,), z80=f"inc {_Z80_PAIR[rp]}")
        put(0x0B | i << 4, name="DCX", args=(rp,), z80=f"dec {_Z80_PAIR[rp]}")
    put(0x02, name="STAX", args=("B",), z80="ld (bc),a")
    put(0x12, name="STAX", args=("D",), z80="ld (de),a")
    put(0x0A, name="LDAX", args=("B",), z80="ld a,(bc)")
    put(0x1A, name="LDAX", args=("D",), z80="ld a,(de)")
    put(0x22, name="SHLD", length=3, operand="addr", z80="ld ({nn}),hl")
    put(0x2A, name="LHLD", length=3, operand="addr", z80="ld hl,({nn})")
    put(0x32, name="STA", length=3, operand="addr", z80="ld ({nn}),a")
    put(0x3A, name="LDA", length=3, operand="addr", z80="ld a,({nn})")
    for i, r in enumerate(REGS):
        put(0x04 | i << 3, name="INR", args=(r,), z80=f"inc {_Z80_REG[r]}", writes=SZAP)
        put(0x05 | i << 3, name="DCR", args=(r,), z80=f"dec {_Z80_REG[r]}", writes=SZAP)
        put(0x06 | i << 3, name="MVI", args=(r,), length=2, operand="imm8",
            z80=f"ld {_Z80_REG[r]},{{n}}")
    put(0x07, name="RLC", z80="rlca", writes=CARRY)
    put(0x0F, name="RRC", z80="rrca", writes=CARRY)
    put(0x17, name="RAL", z80="rla", reads=CARRY, writes=CARRY)
    put(0x1F, name="RAR", z80="rra", reads=CARRY, writes=CARRY)
    put(0x27, name="DAA", z80="daa", reads=frozenset("AC"), writes=ALL_FLAGS)
    put(0x2F, name="CMA", z80="cpl")
    put(0x37, name="STC", z80="scf", writes=CARRY)
    put(0x3F, name="CMC", z80="ccf", reads=CARRY, writes=CARRY)
    for d, rd in enumerate(REGS):
        for s, rs in enumerate(REGS):
            code = 0x40 | d << 3 | s
            if code == 0x76:
                put(code, name="HLT", z80="halt", flow="halt")
            else:
                put(code, name="MOV", args=(rd, rs),
                    z80=f"ld {_Z80_REG[rd]},{_Z80_REG[rs]}")
    for o, op in enumerate(ALU):
        reads = CARRY if op in ("ADC", "SBB") else frozenset()
        for s, rs in enumerate(REGS):
            put(0x80 | o << 3 | s, name=op, args=(rs,),
                z80=_Z80_ALU[op] + _Z80_REG[rs], reads=reads, writes=ALL_FLAGS)
        put(0xC6 | o << 3, name=ALU_IMM[o], length=2, operand="imm8",
            z80=_Z80_ALU[op] + "{n}", reads=reads, writes=ALL_FLAGS)
    for c, cc in enumerate(CONDITIONS):
        flag = frozenset(CONDITION_FLAG[cc])
        put(0xC0 | c << 3, name="RET", args=(cc,), z80=f"ret {cc.lower()}",
            flow="cret", reads=flag)
        put(0xC2 | c << 3, name="JMP", args=(cc,), length=3, operand="jump",
            z80=f"jp {cc.lower()},{{nn}}", flow="cjump", reads=flag)
        put(0xC4 | c << 3, name="CALL", args=(cc,), length=3, operand="jump",
            z80=f"call {cc.lower()},{{nn}}", flow="ccall", reads=flag)
    for n in range(8):
        put(0xC7 | n << 3, name="RST", args=(n,), z80=f"rst {n * 8}", flow="rst")
    for i, rp in enumerate(PAIRS_PUSH):
        is_psw = rp == "PSW"
        put(0xC1 | i << 4, name="POP", args=(rp,), z80=f"pop {_Z80_PAIR[rp]}",
            writes=ALL_FLAGS if is_psw else frozenset())
        put(0xC5 | i << 4, name="PUSH", args=(rp,), z80=f"push {_Z80_PAIR[rp]}",
            reads=ALL_FLAGS if is_psw else frozenset())
    put(0xC3, name="JMP", length=3, operand="jump", z80="jp {nn}", flow="jump")
    put(0xCB, name="JMP", length=3, operand="jump", z80="", flow="jump", documented=False)
    put(0xC9, name="RET", z80="ret", flow="ret")
    put(0xD9, name="RET", z80="", flow="ret", documented=False)
    put(0xCD, name="CALL", length=3, operand="jump", z80="call {nn}", flow="call")
    for code in (0xDD, 0xED, 0xFD):
        put(code, name="CALL", length=3, operand="jump", z80="", flow="call",
            documented=False)
    put(0xD3, name="OUT", length=2, operand="port", z80="out ({n}),a")
    put(0xDB, name="IN", length=2, operand="port", z80="in a,({n})")
    put(0xE3, name="XTHL", z80="ex (sp),hl")
    put(0xE9, name="PCHL", z80="jp (hl)", flow="pchl")
    put(0xEB, name="XCHG", z80="ex de,hl")
    put(0xF3, name="DI", z80="di")
    put(0xFB, name="EI", z80="ei")
    put(0xF9, name="SPHL", z80="ld sp,hl")
    assert all(t is not None for t in table)
    return table  # type: ignore[return-value]


OPCODES: list[OpInfo] = _build()
DOCUMENTED = [op for op in OPCODES if op.documented]


@dataclass(frozen=True)
class Instr:
    addr: int
    op: OpInfo
    value: int | None = None      # immediate, address or port (JR: target)
    disp: int | None = None       # Z80 index displacement (-128..127)

    @property
    def length(self) -> int:
        return self.op.length

    @property
    def next(self) -> int:
        return (self.addr + self.op.length) & 0xFFFF

    def raw(self) -> bytes:
        op = self.op
        if op.prefix or op.relative:
            out = bytearray(op.prefix)
            if op.prefix[-1:] == b"\xCB" and op.disp:      # DD CB d op
                return bytes(out + bytes([self.disp & 0xFF, op.code]))
            out.append(op.code)
            if op.disp:
                out.append(self.disp & 0xFF)
            rest = op.length - len(out)
            if op.relative:
                out.append((self.value - self.next) & 0xFF)
            elif rest == 1:
                out.append(self.value & 0xFF)
            elif rest == 2:
                out += bytes([self.value & 0xFF, self.value >> 8])
            return bytes(out)
        if self.op.length == 1:
            return bytes([self.op.code])
        if self.op.length == 2:
            return bytes([self.op.code, self.value & 0xFF])
        return bytes([self.op.code, self.value & 0xFF, self.value >> 8])

    def intel(self) -> str:
        if self.value is None:
            return self.op.intel()
        width = 2 if self.op.operand in ("imm8", "port") else 4
        return self.op.intel(f"{self.value:0{width}X}H")


def decode(mem, addr: int) -> Instr:
    """Decode one instruction; `mem` supports mem[addr] (0..65535)."""
    op = OPCODES[mem[addr]]
    if op.length == 1:
        return Instr(addr, op)
    if op.length == 2:
        return Instr(addr, op, mem[(addr + 1) & 0xFFFF])
    return Instr(addr, op, mem[(addr + 1) & 0xFFFF] | mem[(addr + 2) & 0xFFFF] << 8)
