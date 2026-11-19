"""Zero-page layout of run8080.  Must match the equates in run8080.asm.

The 45GS02 B register selects this page, so offset 0 is at $0300 while the
8080 core runs.  PEM (Primitive Execution Module) keeps the real zero page.
"""

PC = 0
SP = 4
HL = 8
DE = 12
BC = 16
RA = 20
RF = 21
UNLIM = 22
MAXLO = 23
MAXHI = 24
OPCODE = 25
OPCA = 26
OPCB = 27
FETLO = 28
FETHI = 29
VAL = 30
NEW = 31
OLDA = 32
RESULT = 33
REGIDX = 34
TMPLO = 35
TMPHI = 36
PLO = 37
PHI = 38
FETCH = 39
QPTR = 40
STOPPED = 47
REASON = 48
PORT = 49
DMAAD = 50
FUNC = 52
INS = 76

BASE = 0x300
B_VALUE = 3
CORE_ENTER = 0x203
WINDOW = 0x2000          # 8080 $0000 is bank 4 offset $2000
STUB = 0xE000            # 8080 addresses from here live in Attic RAM
ATTIC_MB = 0x08
SCREEN = 0x0800          # bank 4 offset of the MEGA65 ROM's 80 by 50 text screen
SCREEN_BYTES = 80 * 24

# Why a stop left the 8080 program.  Printed, and stored at REASON.
REASON_HLT = 1
REASON_IN = 2
REASON_OUT = 3
REASON_PREFIX = 4
REASON_WRITE = 5
REASON_FN = 6
REASON_USER = 7
REASON_BIOS = 8
REASON_ATTIC = 9
REASON_FILE = 10
