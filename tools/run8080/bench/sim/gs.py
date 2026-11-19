"""45GS02 operations used by run8080, on top of the py65 6502.

The B register relocates the zero page.  Absolute addresses are not relocated,
so a store to address 0 is the MEGA65 speed override and a store to $0300
(zero-page address 0 while B is 3) is an ordinary byte.  A 32-bit indirect
`LDA [zp],Z` ignores the memory map and can see bank 4 and Attic RAM.
"""

from __future__ import annotations

_N = 0x80
_V = 0x40
_Z = 0x02
_C = 0x01


def step(machine) -> bool:
    """Execute one instruction.  False means the opcode is not implemented."""
    mem = machine.memory
    mpu = machine.mpu
    pc = mpu.pc
    op = mem[pc]
    if op == 0xEA:
        nxt = mem[(pc + 1) & 0xFFFF]
        if nxt in (0xB2, 0x92):
            _indirect32(machine, nxt, mem[(pc + 2) & 0xFFFF])
            mpu.pc = (pc + 3) & 0xFFFF
            return True
        mpu.pc = (pc + 1) & 0xFFFF
        return True
    handler = _OPS[op]
    if handler is None:
        return False
    handler(machine, pc)
    return True


def _zp(machine, offset: int) -> int:
    return ((machine.b & 0xFF) << 8 | (offset & 0xFF)) & 0xFFFF


def _rd_zp(machine, offset: int) -> int:
    return machine.memory[_zp(machine, offset)]


def _wr_zp(machine, offset: int, value: int) -> None:
    addr = _zp(machine, offset)
    if addr == 0:
        machine.note_speed(value)
        return
    machine.memory[addr] = value & 0xFF


def _rd_abs(machine, addr: int) -> int:
    addr &= 0xFFFF
    if machine.io_mapped and 0xD000 <= addr <= 0xDFFF:
        return machine.io[addr - 0xD000]
    return machine.memory[addr]


def _wr_abs(machine, addr: int, value: int) -> None:
    addr &= 0xFFFF
    if addr == 0:
        machine.note_speed(value)
        return
    if machine.io_mapped and 0xD000 <= addr <= 0xDFFF:
        machine.io[addr - 0xD000] = value & 0xFF
        if addr == 0xD700:
            machine._dmagic(value)
        elif addr == 0xD705:
            machine._dmagic_enhanced(value)
        return
    machine.memory[addr] = value & 0xFF


def _set_nz(mpu, value: int) -> None:
    value &= 0xFF
    p = mpu.p & ~(_N | _Z)
    if value == 0:
        p |= _Z
    else:
        p |= value & _N
    mpu.p = p


def _set_c(mpu, carry: int) -> None:
    if carry:
        mpu.p |= _C
    else:
        mpu.p &= ~_C


def _ptr32(machine, zp: int) -> int:
    base = _zp(machine, zp)
    mem = machine.memory
    addr = (mem[base] | (mem[(base + 1) & 0xFFFF] << 8)
            | (mem[(base + 2) & 0xFFFF] << 16)
            | (mem[(base + 3) & 0xFFFF] << 24))
    return (addr + (machine.z_register & 0xFF)) & 0xFFFFFFFF


def _indirect32(machine, op: int, zp: int) -> None:
    addr = _ptr32(machine, zp)
    if op == 0xB2:
        machine.mpu.a = machine.flat_read(addr)
        _set_nz(machine.mpu, machine.mpu.a)
    else:
        machine.flat_write(addr, machine.mpu.a)


def _ptr16(machine, zp: int) -> int:
    base = _zp(machine, zp)
    mem = machine.memory
    ptr = mem[base] | (mem[(base + 1) & 0xFFFF] << 8)
    return (ptr + (machine.z_register & 0xFF)) & 0xFFFF


def _branch(machine, pc: int, take: bool) -> None:
    offset = machine.memory[(pc + 1) & 0xFFFF]
    if offset & 0x80:
        offset -= 256
    machine.mpu.pc = ((pc + 2 + offset) if take else pc + 2) & 0xFFFF


def _adc(mpu, value: int) -> None:
    carry = mpu.p & _C
    total = mpu.a + value + carry
    mpu.a = total & 0xFF
    _set_c(mpu, total > 255)
    _set_nz(mpu, mpu.a)


def _sbc(mpu, value: int) -> None:
    _adc(mpu, value ^ 0xFF)


def _op_ldz(m, pc):
    m.z_register = m.memory[(pc + 1) & 0xFFFF]
    m.mpu.pc = (pc + 2) & 0xFFFF


def _op_map(m, pc):
    m.io_mapped = m.z_register == 0xB5
    m.mpu.pc = (pc + 1) & 0xFFFF


def _op_tab(m, pc):
    m.b = m.mpu.a & 0xFF
    m.mpu.pc = (pc + 1) & 0xFFFF


def _op_tba(m, pc):
    m.mpu.a = m.b & 0xFF
    m.mpu.pc = (pc + 1) & 0xFFFF


def _op_neg(m, pc):
    value = (-m.mpu.a) & 0xFF
    m.mpu.a = value
    _set_nz(m.mpu, value)
    _set_c(m.mpu, 1 if value else 0)
    m.mpu.pc = (pc + 1) & 0xFFFF


def _op_asr(m, pc):
    a = m.mpu.a
    _set_c(m.mpu, a & 1)
    a = (a >> 1) | (a & 0x80)
    m.mpu.a = a
    _set_nz(m.mpu, a)
    m.mpu.pc = (pc + 1) & 0xFFFF


def _op_asw(m, pc):
    addr = m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8
    word = m.memory[addr] | m.memory[(addr + 1) & 0xFFFF] << 8
    _set_c(m.mpu, word >> 15)
    word = (word << 1) & 0xFFFF
    m.memory[addr] = word & 0xFF
    m.memory[(addr + 1) & 0xFFFF] = word >> 8
    _set_word_nz(m.mpu, word)
    m.mpu.pc = (pc + 3) & 0xFFFF


def _op_inw(m, pc):
    zp = m.memory[(pc + 1) & 0xFFFF]
    word = (_rd_zp(m, zp) | _rd_zp(m, (zp + 1) & 0xFF) << 8)
    word = (word + 1) & 0xFFFF
    _wr_zp(m, zp, word & 0xFF)
    _wr_zp(m, (zp + 1) & 0xFF, word >> 8)
    _set_word_nz(m.mpu, word)
    m.mpu.pc = (pc + 2) & 0xFFFF


def _op_dew(m, pc):
    zp = m.memory[(pc + 1) & 0xFFFF]
    word = (_rd_zp(m, zp) | _rd_zp(m, (zp + 1) & 0xFF) << 8)
    word = (word - 1) & 0xFFFF
    _wr_zp(m, zp, word & 0xFF)
    _wr_zp(m, (zp + 1) & 0xFF, word >> 8)
    _set_word_nz(m.mpu, word)
    m.mpu.pc = (pc + 2) & 0xFFFF


def _set_word_nz(mpu, word: int) -> None:
    p = mpu.p & ~(_N | _Z)
    if word & 0x8000:
        p |= _N
    if word == 0:
        p |= _Z
    mpu.p = p


def _op_jmp_ax(m, pc):
    base = m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8
    addr = (base + m.mpu.x) & 0xFFFF
    m.mpu.pc = m.memory[addr] | m.memory[(addr + 1) & 0xFFFF] << 8


def _op_jmp(m, pc):
    m.mpu.pc = m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8


def _op_jsr(m, pc):
    ret = (pc + 2) & 0xFFFF
    m._push(ret >> 8)
    m._push(ret & 0xFF)
    m.mpu.pc = m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8


def _op_rts(m, pc):
    m._rts()


def _op_pha(m, pc):
    m._push(m.mpu.a)
    m.mpu.pc = (pc + 1) & 0xFFFF


def _op_pla(m, pc):
    m.mpu.a = m._pull()
    _set_nz(m.mpu, m.mpu.a)
    m.mpu.pc = (pc + 1) & 0xFFFF


def _op_php(m, pc):
    m._push(m.mpu.p | 0x30)
    m.mpu.pc = (pc + 1) & 0xFFFF


def _op_plp(m, pc):
    m.mpu.p = (m._pull() | 0x20) & 0xFF
    m.mpu.pc = (pc + 1) & 0xFFFF


def _op_clc(m, pc):
    m.mpu.p &= ~_C
    m.mpu.pc = (pc + 1) & 0xFFFF


def _op_sec(m, pc):
    m.mpu.p |= _C
    m.mpu.pc = (pc + 1) & 0xFFFF


def _op_cli(m, pc):
    m.mpu.p &= ~0x04
    m.mpu.pc = (pc + 1) & 0xFFFF


def _op_sei(m, pc):
    m.mpu.p |= 0x04
    m.mpu.pc = (pc + 1) & 0xFFFF


def _op_cld(m, pc):
    m.mpu.p &= ~0x08
    m.mpu.pc = (pc + 1) & 0xFFFF


def _op_sed(m, pc):
    m.mpu.p |= 0x08
    m.mpu.pc = (pc + 1) & 0xFFFF


def _lda(m, pc, value, size):
    m.mpu.a = value & 0xFF
    _set_nz(m.mpu, m.mpu.a)
    m.mpu.pc = (pc + size) & 0xFFFF


def _ldx(m, pc, value, size):
    m.mpu.x = value & 0xFF
    _set_nz(m.mpu, m.mpu.x)
    m.mpu.pc = (pc + size) & 0xFFFF


def _ldy(m, pc, value, size):
    m.mpu.y = value & 0xFF
    _set_nz(m.mpu, m.mpu.y)
    m.mpu.pc = (pc + size) & 0xFFFF


def _op_lda_imm(m, pc):
    _lda(m, pc, m.memory[(pc + 1) & 0xFFFF], 2)


def _op_ldx_imm(m, pc):
    _ldx(m, pc, m.memory[(pc + 1) & 0xFFFF], 2)


def _op_ldy_imm(m, pc):
    _ldy(m, pc, m.memory[(pc + 1) & 0xFFFF], 2)


def _op_lda_zp(m, pc):
    _lda(m, pc, _rd_zp(m, m.memory[(pc + 1) & 0xFFFF]), 2)


def _op_ldx_zp(m, pc):
    _ldx(m, pc, _rd_zp(m, m.memory[(pc + 1) & 0xFFFF]), 2)


def _op_ldy_zp(m, pc):
    _ldy(m, pc, _rd_zp(m, m.memory[(pc + 1) & 0xFFFF]), 2)


def _op_lda_zpx(m, pc):
    _lda(m, pc, _rd_zp(m, (m.memory[(pc + 1) & 0xFFFF] + m.mpu.x) & 0xFF), 2)


def _op_ldy_zpx(m, pc):
    _ldy(m, pc, _rd_zp(m, (m.memory[(pc + 1) & 0xFFFF] + m.mpu.x) & 0xFF), 2)


def _op_lda_abs(m, pc):
    addr = m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8
    _lda(m, pc, _rd_abs(m, addr), 3)


def _op_ldx_abs(m, pc):
    addr = m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8
    _ldx(m, pc, _rd_abs(m, addr), 3)


def _op_ldy_abs(m, pc):
    addr = m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8
    _ldy(m, pc, _rd_abs(m, addr), 3)


def _op_lda_abx(m, pc):
    addr = (m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8) + m.mpu.x
    _lda(m, pc, _rd_abs(m, addr), 3)


def _op_ldx_aby(m, pc):
    addr = (m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8) + m.mpu.y
    _ldx(m, pc, _rd_abs(m, addr), 3)


def _op_and_aby(m, pc):
    addr = (m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8) + m.mpu.y
    _logic(m, pc, "and", _rd_abs(m, addr), 3)


def _op_cmp_aby(m, pc):
    addr = (m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8) + m.mpu.y
    _compare(m, m.mpu.a, _rd_abs(m, addr))
    m.mpu.pc = (pc + 3) & 0xFFFF


def _op_lda_aby(m, pc):
    addr = (m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8) + m.mpu.y
    _lda(m, pc, _rd_abs(m, addr), 3)


def _op_lda_izy(m, pc):
    zp = m.memory[(pc + 1) & 0xFFFF]
    base = _rd_zp(m, zp) | _rd_zp(m, (zp + 1) & 0xFF) << 8
    _lda(m, pc, _rd_abs(m, base + m.mpu.y), 2)


def _op_lda_izz(m, pc):
    _lda(m, pc, _rd_abs(m, _ptr16(m, m.memory[(pc + 1) & 0xFFFF])), 2)


def _op_sta_zp(m, pc):
    _wr_zp(m, m.memory[(pc + 1) & 0xFFFF], m.mpu.a)
    m.mpu.pc = (pc + 2) & 0xFFFF


def _op_stx_zp(m, pc):
    _wr_zp(m, m.memory[(pc + 1) & 0xFFFF], m.mpu.x)
    m.mpu.pc = (pc + 2) & 0xFFFF


def _op_sty_zp(m, pc):
    _wr_zp(m, m.memory[(pc + 1) & 0xFFFF], m.mpu.y)
    m.mpu.pc = (pc + 2) & 0xFFFF


def _op_sta_zpx(m, pc):
    _wr_zp(m, (m.memory[(pc + 1) & 0xFFFF] + m.mpu.x) & 0xFF, m.mpu.a)
    m.mpu.pc = (pc + 2) & 0xFFFF


def _op_sta_abs(m, pc):
    addr = m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8
    _wr_abs(m, addr, m.mpu.a)
    m.mpu.pc = (pc + 3) & 0xFFFF


def _op_stx_abs(m, pc):
    addr = m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8
    _wr_abs(m, addr, m.mpu.x)
    m.mpu.pc = (pc + 3) & 0xFFFF


def _op_sty_abs(m, pc):
    addr = m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8
    _wr_abs(m, addr, m.mpu.y)
    m.mpu.pc = (pc + 3) & 0xFFFF


def _op_sta_abx(m, pc):
    addr = (m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8) + m.mpu.x
    _wr_abs(m, addr, m.mpu.a)
    m.mpu.pc = (pc + 3) & 0xFFFF


def _op_sta_aby(m, pc):
    addr = (m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8) + m.mpu.y
    _wr_abs(m, addr, m.mpu.a)
    m.mpu.pc = (pc + 3) & 0xFFFF


def _op_sta_izy(m, pc):
    zp = m.memory[(pc + 1) & 0xFFFF]
    base = _rd_zp(m, zp) | _rd_zp(m, (zp + 1) & 0xFF) << 8
    _wr_abs(m, base + m.mpu.y, m.mpu.a)
    m.mpu.pc = (pc + 2) & 0xFFFF


def _op_sta_izz(m, pc):
    _wr_abs(m, _ptr16(m, m.memory[(pc + 1) & 0xFFFF]), m.mpu.a)
    m.mpu.pc = (pc + 2) & 0xFFFF


def _logic(m, pc, op, value, size):
    if op == "and":
        m.mpu.a &= value
    elif op == "ora":
        m.mpu.a |= value
    else:
        m.mpu.a ^= value
    m.mpu.a &= 0xFF
    _set_nz(m.mpu, m.mpu.a)
    m.mpu.pc = (pc + size) & 0xFFFF


def _op_and_imm(m, pc):
    _logic(m, pc, "and", m.memory[(pc + 1) & 0xFFFF], 2)


def _op_ora_imm(m, pc):
    _logic(m, pc, "ora", m.memory[(pc + 1) & 0xFFFF], 2)


def _op_eor_imm(m, pc):
    _logic(m, pc, "eor", m.memory[(pc + 1) & 0xFFFF], 2)


def _op_and_zp(m, pc):
    _logic(m, pc, "and", _rd_zp(m, m.memory[(pc + 1) & 0xFFFF]), 2)


def _op_ora_zp(m, pc):
    _logic(m, pc, "ora", _rd_zp(m, m.memory[(pc + 1) & 0xFFFF]), 2)


def _abs_value(m, pc):
    addr = m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8
    return _rd_abs(m, addr)


def _op_ora_abs(m, pc):
    _logic(m, pc, "ora", _abs_value(m, pc), 3)


def _op_and_abs(m, pc):
    _logic(m, pc, "and", _abs_value(m, pc), 3)


def _op_eor_abs(m, pc):
    _logic(m, pc, "eor", _abs_value(m, pc), 3)


def _op_cmp_abs(m, pc):
    _compare(m, m.mpu.a, _abs_value(m, pc))
    m.mpu.pc = (pc + 3) & 0xFFFF


def _op_adc_abs(m, pc):
    _adc(m.mpu, _abs_value(m, pc))
    m.mpu.pc = (pc + 3) & 0xFFFF


def _op_sbc_abs(m, pc):
    _sbc(m.mpu, _abs_value(m, pc))
    m.mpu.pc = (pc + 3) & 0xFFFF


def _op_eor_zp(m, pc):
    _logic(m, pc, "eor", _rd_zp(m, m.memory[(pc + 1) & 0xFFFF]), 2)


def _op_adc_imm(m, pc):
    _adc(m.mpu, m.memory[(pc + 1) & 0xFFFF])
    m.mpu.pc = (pc + 2) & 0xFFFF


def _op_adc_zp(m, pc):
    _adc(m.mpu, _rd_zp(m, m.memory[(pc + 1) & 0xFFFF]))
    m.mpu.pc = (pc + 2) & 0xFFFF


def _op_sbc_imm(m, pc):
    _sbc(m.mpu, m.memory[(pc + 1) & 0xFFFF])
    m.mpu.pc = (pc + 2) & 0xFFFF


def _op_sbc_zp(m, pc):
    _sbc(m.mpu, _rd_zp(m, m.memory[(pc + 1) & 0xFFFF]))
    m.mpu.pc = (pc + 2) & 0xFFFF


def _op_cmp_imm(m, pc):
    _compare(m, m.mpu.a, m.memory[(pc + 1) & 0xFFFF])
    m.mpu.pc = (pc + 2) & 0xFFFF


def _op_cmp_zp(m, pc):
    _compare(m, m.mpu.a, _rd_zp(m, m.memory[(pc + 1) & 0xFFFF]))
    m.mpu.pc = (pc + 2) & 0xFFFF


def _op_cpx_zp(m, pc):
    _compare(m, m.mpu.x, _rd_zp(m, m.memory[(pc + 1) & 0xFFFF]))
    m.mpu.pc = (pc + 2) & 0xFFFF


def _op_cpy_zp(m, pc):
    _compare(m, m.mpu.y, _rd_zp(m, m.memory[(pc + 1) & 0xFFFF]))
    m.mpu.pc = (pc + 2) & 0xFFFF


def _op_cpx_imm(m, pc):
    _compare(m, m.mpu.x, m.memory[(pc + 1) & 0xFFFF])
    m.mpu.pc = (pc + 2) & 0xFFFF


def _op_cpy_imm(m, pc):
    _compare(m, m.mpu.y, m.memory[(pc + 1) & 0xFFFF])
    m.mpu.pc = (pc + 2) & 0xFFFF


def _compare(m, left, right):
    result = (left - right) & 0xFF
    _set_c(m.mpu, 1 if left >= right else 0)
    _set_nz(m.mpu, result)


def _shift_a(m, pc, kind):
    a = m.mpu.a
    carry = m.mpu.p & _C
    if kind == "asl":
        _set_c(m.mpu, a >> 7)
        a = (a << 1) & 0xFF
    elif kind == "lsr":
        _set_c(m.mpu, a & 1)
        a >>= 1
    elif kind == "rol":
        _set_c(m.mpu, a >> 7)
        a = ((a << 1) | carry) & 0xFF
    else:
        old = a & 1
        a = (a >> 1) | (carry << 7)
        _set_c(m.mpu, old)
    m.mpu.a = a
    _set_nz(m.mpu, a)
    m.mpu.pc = (pc + 1) & 0xFFFF


def _op_asl(m, pc):
    _shift_a(m, pc, "asl")


def _op_lsr(m, pc):
    _shift_a(m, pc, "lsr")


def _op_rol(m, pc):
    _shift_a(m, pc, "rol")


def _op_ror(m, pc):
    _shift_a(m, pc, "rar")


def _shift_zp(m, pc, kind):
    zp = m.memory[(pc + 1) & 0xFFFF]
    value = _rd_zp(m, zp)
    carry = m.mpu.p & _C
    if kind == "asl":
        _set_c(m.mpu, value >> 7)
        value = (value << 1) & 0xFF
    else:
        _set_c(m.mpu, value >> 7)
        value = ((value << 1) | carry) & 0xFF
    _wr_zp(m, zp, value)
    _set_nz(m.mpu, value)
    m.mpu.pc = (pc + 2) & 0xFFFF


def _shift_abs(m, pc, kind):
    addr = m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8
    value = _rd_abs(m, addr)
    carry = m.mpu.p & _C
    if kind == "asl":
        _set_c(m.mpu, value >> 7)
        value = (value << 1) & 0xFF
    elif kind == "rol":
        _set_c(m.mpu, value >> 7)
        value = ((value << 1) | carry) & 0xFF
    elif kind == "lsr":
        _set_c(m.mpu, value & 1)
        value >>= 1
    else:
        _set_c(m.mpu, value & 1)
        value = (value >> 1) | (0x80 if carry else 0)
    _wr_abs(m, addr, value)
    _set_nz(m.mpu, value)
    m.mpu.pc = (pc + 3) & 0xFFFF


def _op_asl_abs(m, pc):
    _shift_abs(m, pc, "asl")


def _op_rol_abs(m, pc):
    _shift_abs(m, pc, "rol")


def _op_lsr_abs(m, pc):
    _shift_abs(m, pc, "lsr")


def _op_ror_abs(m, pc):
    _shift_abs(m, pc, "ror")


def _op_asl_zp(m, pc):
    _shift_zp(m, pc, "asl")


def _op_rol_zp(m, pc):
    _shift_zp(m, pc, "rol")


def _inc_zp(m, pc, delta):
    zp = m.memory[(pc + 1) & 0xFFFF]
    value = (_rd_zp(m, zp) + delta) & 0xFF
    _wr_zp(m, zp, value)
    _set_nz(m.mpu, value)
    m.mpu.pc = (pc + 2) & 0xFFFF


def _op_inc_abs(m, pc):
    addr = m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8
    value = (_rd_abs(m, addr) + 1) & 0xFF
    _wr_abs(m, addr, value)
    _set_nz(m.mpu, value)
    m.mpu.pc = (pc + 3) & 0xFFFF


def _op_dec_abs(m, pc):
    addr = m.memory[(pc + 1) & 0xFFFF] | m.memory[(pc + 2) & 0xFFFF] << 8
    value = (_rd_abs(m, addr) - 1) & 0xFF
    _wr_abs(m, addr, value)
    _set_nz(m.mpu, value)
    m.mpu.pc = (pc + 3) & 0xFFFF


def _op_inc_zp(m, pc):
    _inc_zp(m, pc, 1)


def _op_dec_zp(m, pc):
    _inc_zp(m, pc, -1)


def _bump(m, pc, reg, delta):
    value = (getattr(m.mpu, reg) + delta) & 0xFF
    setattr(m.mpu, reg, value)
    _set_nz(m.mpu, value)
    m.mpu.pc = (pc + 1) & 0xFFFF


def _op_inx(m, pc):
    _bump(m, pc, "x", 1)


def _op_dex(m, pc):
    _bump(m, pc, "x", -1)


def _op_iny(m, pc):
    _bump(m, pc, "y", 1)


def _op_dey(m, pc):
    _bump(m, pc, "y", -1)


def _transfer(m, pc, src, dst):
    value = getattr(m.mpu, src) & 0xFF
    setattr(m.mpu, dst, value)
    if dst != "sp":
        _set_nz(m.mpu, value)
    m.mpu.pc = (pc + 1) & 0xFFFF


def _op_tax(m, pc):
    _transfer(m, pc, "a", "x")


def _op_txa(m, pc):
    _transfer(m, pc, "x", "a")


def _op_tay(m, pc):
    _transfer(m, pc, "a", "y")


def _op_tya(m, pc):
    _transfer(m, pc, "y", "a")


def _op_tsx(m, pc):
    _transfer(m, pc, "sp", "x")


def _op_txs(m, pc):
    _transfer(m, pc, "x", "sp")


def _op_bcc(m, pc):
    _branch(m, pc, not (m.mpu.p & _C))


def _op_bcs(m, pc):
    _branch(m, pc, bool(m.mpu.p & _C))


def _op_beq(m, pc):
    _branch(m, pc, bool(m.mpu.p & _Z))


def _op_bne(m, pc):
    _branch(m, pc, not (m.mpu.p & _Z))


def _op_bpl(m, pc):
    _branch(m, pc, not (m.mpu.p & _N))


def _op_bmi(m, pc):
    _branch(m, pc, bool(m.mpu.p & _N))


def _op_bra(m, pc):
    _branch(m, pc, True)


_OPS: list = [None] * 256
for _op, _fn in {
    0x06: _op_asl_zp, 0x08: _op_php, 0x0A: _op_asl, 0x10: _op_bpl,
    0x18: _op_clc, 0x20: _op_jsr, 0x26: _op_rol_zp, 0x28: _op_plp,
    0x2A: _op_rol, 0x30: _op_bmi, 0x38: _op_sec, 0x42: _op_neg,
    0x43: _op_asr, 0x48: _op_pha, 0x4A: _op_lsr, 0x4C: _op_jmp,
    0x58: _op_cli, 0x5B: _op_tab, 0x5C: _op_map, 0x60: _op_rts,
    0x68: _op_pla, 0x6A: _op_ror, 0x78: _op_sei, 0x7B: _op_tba,
    0x7C: _op_jmp_ax, 0x80: _op_bra, 0x84: _op_sty_zp, 0x85: _op_sta_zp,
    0x86: _op_stx_zp, 0x88: _op_dey, 0x8A: _op_txa, 0x8C: _op_sty_abs,
    0x8D: _op_sta_abs, 0x8E: _op_stx_abs, 0x90: _op_bcc, 0x91: _op_sta_izy,
    0x92: _op_sta_izz, 0x95: _op_sta_zpx, 0x98: _op_tya, 0x99: _op_sta_aby,
    0x9A: _op_txs, 0x9D: _op_sta_abx, 0xA0: _op_ldy_imm, 0xA2: _op_ldx_imm,
    0xA3: _op_ldz, 0xA4: _op_ldy_zp, 0xA5: _op_lda_zp, 0xA6: _op_ldx_zp,
    0xA8: _op_tay, 0xA9: _op_lda_imm, 0xAA: _op_tax, 0xAC: _op_ldy_abs,
    0xAD: _op_lda_abs, 0xAE: _op_ldx_abs, 0xB1: _op_lda_izy, 0xB2: _op_lda_izz,
    0x39: _op_and_aby, 0xB4: _op_ldy_zpx, 0xB5: _op_lda_zpx,
    0xB9: _op_lda_aby, 0xBA: _op_tsx, 0xBE: _op_ldx_aby, 0xD9: _op_cmp_aby,
    0xBD: _op_lda_abx, 0xC0: _op_cpy_imm, 0xC3: _op_dew, 0xC4: _op_cpy_zp,
    0xC5: _op_cmp_zp,
    0xC6: _op_dec_zp, 0xC8: _op_iny, 0xC9: _op_cmp_imm, 0xCA: _op_dex,
    0xCB: _op_asw, 0xD0: _op_bne, 0xD8: _op_cld, 0xE0: _op_cpx_imm,
    0x0D: _op_ora_abs, 0x0E: _op_asl_abs, 0x2D: _op_and_abs, 0x2E: _op_rol_abs,
    0x4D: _op_eor_abs, 0x4E: _op_lsr_abs, 0x6D: _op_adc_abs, 0x6E: _op_ror_abs,
    0xCD: _op_cmp_abs, 0xED: _op_sbc_abs,
    0xCE: _op_dec_abs, 0xE3: _op_inw, 0xE4: _op_cpx_zp, 0xE5: _op_sbc_zp,
    0xE6: _op_inc_zp, 0xE8: _op_inx, 0xEE: _op_inc_abs,
    0xE9: _op_sbc_imm, 0x05: _op_ora_zp, 0x09: _op_ora_imm, 0x25: _op_and_zp,
    0x29: _op_and_imm, 0x45: _op_eor_zp, 0x49: _op_eor_imm, 0x65: _op_adc_zp,
    0x69: _op_adc_imm, 0xF0: _op_beq, 0xF8: _op_sed, 0xB0: _op_bcs,
}.items():
    _OPS[_op] = _fn
