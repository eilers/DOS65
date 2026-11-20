"""Facts about the DOS/65 2.19 Mega65 port, taken from src/constants.asm,
src/ccm.asm, src/pem.asm and src/c65/c65sim.asm.

DOS/65 terms used here:
  TEA  Transient Execution Area, where programs are loaded and started
  CCM  Console Command Module, the command interpreter (may be overwritten)
  PEM  Primitive Execution Module, the counterpart of the CP/M BDOS
  SIM  System Interface Module, the counterpart of the CP/M BIOS
  DCB  Disk Control Block, the counterpart of the CP/M disk parameter block
"""

BOOT_VECTOR = 0x100      # JMP to SIM warm boot entry (SIM base + 3)
PEM_VECTOR = 0x103       # JMP to PEM; X = function, A/Y = parameter
IOSTAT = 0x106
DEFAULT_FCB = 0x107      # 33 bytes, the CP/M random record bytes do not fit
DEFAULT_BUFFER = 0x128   # 128 bytes: length byte + command tail on entry
TEA = 0x200

CCM_LENGTH = 2037
PEM_LENGTH = 3047
SIM_PAGES = 11
MEMORY_SIZE = 64 * 1024
SIM_START = MEMORY_SIZE - SIM_PAGES * 256              # $F500
PEM_START = SIM_START - PEM_LENGTH                     # $E919
CCM_START = PEM_START - CCM_LENGTH                     # $E124

# Without overwriting CCM a program may use TEA..CCM_START-1.  Translated
# programs always leave through the warm boot vector, so CCM gets reloaded
# and memory up to PEM_START may be used as work space.
TEA_LIMIT = CCM_START

# PEM page zero use ($02-$09 is swapped by PEM itself, so programs may use it).
# The Mega65 SIM uses $D4 (quote mode) and the runner $FB/$FC.  Translated
# programs use a block starting at ZP_BASE.
ZP_RESERVED = {0x00, 0x01, 0xD4, 0xFB, 0xFC}
ZP_BASE_DEFAULT = 0x10

# PEM function numbers (pem.asm, cmdtbl).  0..29 match CP/M 2.2 by meaning.
PEM_FUNCTIONS = {
    0: "warm boot", 1: "console input with echo", 2: "console output",
    3: "reader input", 4: "punch output", 5: "list output",
    6: "console input without echo", 7: "read i/o status", 8: "set i/o status",
    9: "print string ($ terminated)", 10: "read buffer", 11: "console status",
    12: "list status", 13: "initialize system", 14: "log in drive",
    15: "open", 16: "close", 17: "search first", 18: "search next",
    19: "delete", 20: "read record", 21: "write record", 22: "make",
    23: "rename", 24: "login vector", 25: "current drive", 26: "set buffer",
    27: "allocation map address", 28: "set read only", 29: "read only vector",
    30: "set list echo", 31: "read list echo", 32: "read clock low",
    33: "read clock high", 34: "read DCB address", 35: "translate sector",
}
PEM_FUNCTION_COUNT = 36

# SIM jump table offsets (c65sim.asm) compared with the CP/M 2.2 BIOS.
# CP/M offset -> SIM offset.  Offsets up to 45 are identical; SECTRAN moves
# from 48 to 51 because the SIM has a clock entry at 48.
CPM_BIOS_ENTRIES = [
    "BOOT", "WBOOT", "CONST", "CONIN", "CONOUT", "LIST", "PUNCH", "READER",
    "HOME", "SELDSK", "SETTRK", "SETSEC", "SETDMA", "READ", "WRITE",
    "LISTST", "SECTRAN",
]
SIM_OFFSET_FOR_CPM_OFFSET = {3 * i: 3 * i for i in range(16)}
SIM_OFFSET_FOR_CPM_OFFSET[48] = 51
SIM_CLOCK_OFFSET = 48
SIM_CONSOLE_DEFINITION_OFFSET = 55   # sysdef block, see EDIT205.ASM condef

# DCB layout (14 bytes), c65sim.asm dcba:
#  +0 word max block number      +2 word records per track
#  +4 word system tracks         +6 byte block size code (0=1K,1=2K,2=4K,...)
#  +7 word max directory number  +9 word allocation map address
#  +11 byte checksum flag (0 = do checksums)  +12 word checksum map address
DCB_SIZE = 14

# FCB fields shared by CP/M and DOS/65.
FCB_DRIVE, FCB_NAME, FCB_TYPE, FCB_EXTENT, FCB_RECORD_COUNT = 0, 1, 9, 12, 15
FCB_NEXT_RECORD = 32
CPM_FCB_RANDOM = 33        # r0, r1, r2 exist only in CP/M

# Mega65: DOS/65 runs in bank 5.  I/O (DMAgic at $D700) is only visible after
# MAP with Z=%10110101, see c65/macros.asm SetBank5WithBridgeAndDMA.
MEGA65_DOS65_BANK = 5
MEGA65_OVERLAY_BANK_DEFAULT = 4
MEGA65_MAP_DMA = (0x00, 0xD5, 0x00, 0xB5)      # A, X, Y, Z
MEGA65_MAP_DOS65 = (0x00, 0xF5, 0x00, 0xF5)
DMAGIC_ADDR_LOW, DMAGIC_ADDR_HIGH, DMAGIC_ADDR_BANK = 0xD700, 0xD701, 0xD702
