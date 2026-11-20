# run8080 architecture

This note is for someone who wants to change the emulator, port another CP/M program onto it, or judge whether a missing feature is a small shim or a new design. How to build and run it is in [README.md](README.md).

Names used here:

- **8080** is the processor CP/M programs are written for. **Z80** is the later processor that adds prefixes the 8080 does not have.
- **CP/M** is the operating system those programs expect. Its **BDOS** (Basic Disk Operating System) is the disk and console call layer. Its **BIOS** (Basic Input/Output System) is the jump table of hardware routines.
- **DOS/65** is the native system on this MEGA65 port. **PEM** (Primitive Execution Module) is its counterpart of the BDOS. **SIM** (System Interface Module) is its counterpart of the BIOS. **CCM** (Console Command Module) is the command interpreter that prints `A>`.
- **TEA** (transient execution area) is where DOS/65 loads `RUN8080.COM`, from `$0200` upward in bank 5.
- **TPA** (transient program area) is the memory the 8080 program believes it owns, `$0100` through `$DFFF`.
- **FCB** (file control block) is the 36-byte CP/M file descriptor. DOS/65 uses 33 bytes and has no module byte.
- **DMAgic** is the MEGA65 block-copy engine. **Attic RAM** is the memory at physical `$8000000`, above the 1 MB of chip RAM. The **45GS02** is the MEGA65 processor. **B** is its base-page register: `LDA` and `STA` of addresses `$00`–`$FF` use the zero page selected by B.

## The idea, and how it is realized

A CP/M `.COM` program spends almost all of its time in its own 8080 code, and only occasionally asks the operating system to read a key, draw a character, or touch a file. Emulating the whole of CP/M would mean a second file system beside DOS/65. `run8080` emulates only the processor. Every system call is turned into a PEM or SIM call, so the file the guest creates is an ordinary DOS/65 file and the screen the guest draws is the MEGA65 screen.

The shape of that idea was checked against [atari8080](https://github.com/ivop/atari8080), Ivo van Poorten's 8080 emulator for the Atari 130XE and the BBC Master. That program is 6502 assembly. It keeps the 8080 memory in 16 KB banks, runs the original CP/M 2.2 console command processor and BDOS as guest binaries, and turns BIOS calls into calls on CP/M-65. Nothing from that repository is compiled into `run8080`. The handlers, the 32-bit memory pointers, the PEM and SIM shims, the screen and the disk code were written for this port. The Python bench came from the earlier translator experiment in this repository, not from the Atari C prototype. Two techniques were kept because they had already been shown to work: one routine per opcode, reached through two jump tables selected by the high bit of the opcode, and an `OUT` instruction in a stub page as the way the guest reaches the host. `DI` and `EI` are ignored there as well.

atari8080 is under the 2-clause BSD license, copyright 2023 Ivo van Poorten. That license allows the code to be reused here, including inside DOS/65, whose own terms limit it to non-profit, educational, or private use unless Richard A. Leary agrees otherwise. The BSD terms would then apply only to the copied part: the copyright notice and the disclaimer have to stay with that source, and a binary distribution has to carry them in the documentation. They do not replace the DOS/65 terms for the rest of the tree. No notice is included now, because no source was copied.

The program is a threaded interpreter. One 45GS02 routine handles one 8080 opcode, then jumps back to `dispatch`. `gen_handlers.py` writes the 256 routines into `handlers.asm`. Opcodes that share a shape (register moves, the arithmetic group, conditional jumps) are a few instructions that call a common helper such as `getreg`, `setreg`, `do_add` or `cond`. There is no decode loop and no opcode table of operand formats at run time: the table is two jump tables, `tablo` and `tabhi`, indexed by the opcode shifted left one bit.

`dispatch` loads the 32-bit program counter, reads the opcode with `LDA [pc],Z`, advances the counter, and jumps through the table. A step budget in `maxlo`/`maxhi` exists for the test bench. A real run sets `unlim` and ignores it.

The guest never sees PEM. It sees the usual CP/M page zero:

| Address | Contents |
| --- | --- |
| `$0000` | `JMP $F203`, the BIOS warm-boot entry |
| `$0005` | `JMP $E000`, where BDOS appears to start |
| `$005C`, `$006C` | the two file control blocks, filled from the command tail |
| `$0080` | the command tail and the default disk buffer |

`$E000` in the stub image is `OUT 0` / `RET`. `$F200` is a BIOS jump table of 17 entries. Each entry jumps to an `OUT n` / `RET` pair at `$F233`, where `n` is the entry number plus 2. `OUT` is honoured only when the program counter is at `$E000` or above. Anywhere else it stops the guest. That is the whole trap mechanism: the 8080 `OUT` instruction is otherwise unused by these programs, and the fetch address tells the interpreter that this `OUT` is a call rather than a port write.

After the trap, execution continues at the `RET` that follows the `OUT`. BIOS routines that return a value write the 8080 register A and leave B, C, D, E, H and L as they were. WordStar copies the addresses out of the BIOS table and calls those addresses, which is why the table is real jumps rather than the `OUT` instructions themselves.

BDOS function numbers go through `fntab`:

- Functions 1–5, 7–11 and 13–29 call the PEM entry of the same number.
- Function 6 is the direct console call. Output is drawn by `run8080`. Input and status use the same SIM path as the BIOS console, so Control-S is not swallowed.
- Function 12 returns the CP/M version `$0022`. PEM function 12 is list status, a different call, so it is not used.
- Function 31 builds a CP/M disk parameter block from the DOS/65 disk control block of the current drive.
- Functions 33, 34 and 40 turn the CP/M random-record number into an extent and a record, then do a DOS/65 sequential read or write. DOS/65 sequential I/O stays inside the extent the file was opened with, so a record past the first 16 KB needs `seek_extent` first. A write to an extent that is not in the directory creates that directory entry. Extents that are skipped are not created, which matches CP/M, and a later sequential read stops at the gap.
- Function 32 sets the user number. Only user 0 is accepted.
- Anything else stops. The stop line includes the function number.

The BIOS entries that are implemented are BOOT, WBOOT, CONST, CONIN and CONOUT. BOOT and WBOOT leave back to DOS/65. CONST, CONIN and CONOUT are what WordStar 4 uses. The other twelve BIOS entries stop the guest and name the entry.

Console input calls the SIM, not PEM. PEM's console-status routine treats Control-S (`$13`) as freeze: it waits for another key and discards both, unless the second key is Control-C, in which case it warm-boots. WordStar uses Control-S as cursor left. The SIM returns the key. The MEGA65 ROM keyboard reader also drops Control-S, because `$13` is the HOME character and the reader throws that combination away when the control modifier is set. `steal_ctrls` reads the hardware keyboard queue (`$D610` holds the character, `$D619` the Commodore code, `$D60A` the modifiers) while interrupts are still off, takes a queue entry whose code is `$13` and whose modifier is control alone, and writes `$D619` to dequeue it. HOME without the control modifier is left for the ROM. Cursor keys are translated after that: up becomes Control-K, down Control-J, left Control-H, right Control-L.

Console output for both BDOS function 6 and BIOS CONOUT is interpreted as an ADM-3A or ADM-31 terminal onto all 50 rows of the screen. SIM console output cannot be used for this, because it drops the escape character. The sequences those two terminals share are implemented: cursor positioning, clear screen, clear to end of line, clear to end of screen, and the cursor-motion controls. Intensity sequences are accepted and ignored. ASCII `^` (`$5E`) is stored as screen code `$1E`, the up-arrow glyph, because screen code `$5E` in the lowercase font is the pi symbol and WordStar prints `$5E` in front of control-key names.

On the way out, a normal exit (HLT, BDOS function 0, BIOS boot, a jump or call to address 0) turns the cursor attribute off and jumps to the DOS/65 warm boot at `$0100`. A fault prints `STOP`, the program counter, the opcode, the function number and a reason byte, then warm-boots as well.

| Reason | Meaning |
| --- | --- |
| 1 | HLT while the bench is single-stepping |
| 2 | `IN` |
| 3 | `OUT` below `$E000` |
| 4 | a Z80 prefix (`$CB`, `$DD`, `$ED`, `$FD`) |
| 5 | a write at or above `$E000` |
| 6 | a BDOS function with no handler |
| 7 | a user number other than 0 |
| 8 | a BIOS entry with no handler |
| 9 | the Attic stub image did not land |
| 10 | the program name is missing, or the file did not open |
| 11 | a record number past what a DOS/65 file can hold |

## Limits of this design

The interpreter is an 8080, not a Z80. Turbo Pascal 3 and many later CP/M programs execute a Z80 prefix and stop with reason 4. `DI` and `EI` are ignored. There is no interrupt delivery into the guest, and no `IN` instruction at all.

The guest can use `$0000`–`$DFFF` only. Address 6 is `$E000`, which is what a CP/M program reads to find the top of the TPA. `$E000`–`$FFFF` is the stub. A store there stops the program. Programs that relocate themselves up against the BIOS, or that write through a pointer into that range, will not run.

Only five BIOS entries are implemented. A program that prints through the BIOS list entry, selects a disk through the BIOS, or calls `SECTRAN` stops with reason 8. WordStar's print command is in that group.

The terminal emulator is the shared subset of the ADM-3A and the ADM-31 that SuperCalc 2 and this WordStar 4 installation actually send. A program installed for a different terminal (Televideo, VT100, the Lear Siegler extra codes this build does not recognise) will draw garbage or nothing. Writing a character in column 80 wraps to the next row, and wrapping on row 50 scrolls. WordStar marks the end of a line in column 80; a write there on row 50 would scroll the screen. A program installed for 24 lines still only places its cursor inside those lines. A line feed on its own last line now continues into the rows below, because the terminal scrolls only on row 50.

The caret in WordStar's menus is the Commodore up-arrow glyph, not a separate caret. The font is the system font. `$D031` is never written: on the MEGA65 that register is hot, and a write makes the video chip rebuild the screen address from the C64-style pointer, which is the failure that displays ordinary RAM as if it were the screen.

DOS/65 files stop at 32 extents, 512 KB, because there is no CP/M module byte. A random record at or past 4096 returns error 6. User numbers other than 0 stop the guest. The random-record shim creates only the extent it writes; a sparse file has a real hole.

The SIM probes the disk format once after each warm boot, the first time a drive is selected. Swapping a 1541 image for a 1581 image without returning to the `A>` prompt leaves the old geometry in place. A drive that is not there is still asked for track 40, and that read can hang. Any 1581 disk whose track 40 header says format `D` is treated as CP/M, including a disk that is only a Commodore disk.

Control-S is stolen from the hardware queue only when it is the byte at the head and the modifier is control alone. A ROM change that queues that key differently will silently lose cursor left again. The steal runs with interrupts off and then the SIM is called with interrupts on, so a key that arrives between the two checks is handled by the ROM as usual.

Speed is the cost of a correct interpreter rather than a translated program. The inner step is a few dozen 45GS02 instructions, and every guest memory operand is a 32-bit indirect load or store. The Python bench measured about 70 native instructions per 8080 instruction on a small mix. That ratio is the bench, not a cycle count on the MEGA65. The machine is already at 40.5 MHz when DOS/65 starts, and `run8080` does not change the clock.

## Memory layout, and what the MEGA65 is used for

DOS/65 and the SIM live in bank 5. Bank 0 holds kernel data and the SIM-to-kernel bridge and is not written. Banks 2 and 3 are ROM. The guest cannot be given bank 5, and it cannot be given the low 8 KB of bank 4, because that is where the MEGA65 ROM keeps its own data and the 80 by 50 text screen (`$40800`).

What remains of bank 4 is `$42000`–`$4FFFF`, exactly 56 KB. That is the guest's `$0000`–`$DFFF`. A 32-bit pointer is four zero-page bytes. For an address below `$E000` the pointer is `guest + $2000` with the high word `$0004`. `LDA [pointer],Z` and `STA [pointer],Z` use the physical address in the pointer. They do not depend on which MAP is installed, so the interpreter can switch to the DOS/65 map for a PEM call and still see the guest.

The 8080 registers are also zero-page bytes, but on the base page selected by `TAB` with B = 3. PEM and the SIM use the real zero page. Keeping the guest registers on base page 3 means a PEM call can run with B = 0 without saving and restoring a shadow of every register. `pemcall` and the SIM callers save B, switch to base page 0, allow interrupts for the keyboard, call DOS/65, disable interrupts again, and restore B. While B is not zero, interrupts stay off, because an interrupt must see the real zero page.

`$E000`–`$FFFF` does not fit in the leftover bank 4 space, and it must not be writable guest RAM. It is an 8 KB image in Attic RAM at `$8000000`. The same 32-bit pointer reaches it: the high word is `$0008` and the low word is `guest - $E000`. Fetches and reads are allowed. Stores call `stop_write`. The image is filled with `HLT` (`$76`) and then overwritten at the two call sites. BDOS is `OUT 0` / `RET` at the start of the image. The BIOS table and its `OUT`/`RET` stubs are copied to offset `$1200`, which the guest sees as `$F200`. The copy uses an enhanced DMAgic list: option byte `$80` or `$81` followed by a megabyte number supplies bits 20–27 of the address, and the job is started by writing the list address to `$D705`. After the copy, `verify_attic` reads `$E000` and expects `$D3`, the opcode of `OUT`. If the copy missed, the guest would execute whatever was previously in that Attic page, or fall through into bank 0, so the emulator stops with reason 9 instead.

Crossing `$E000` with `INW` or `DEW` is adjusted by `fixup_inc` and `fixup_dec`, so a 16-bit register that wraps the boundary changes its high word between bank 4 and the Attic. A pointer that walks off the top of the stub is pulled back to `$E000` in bank 4 terms only when the Attic offset reaches `$2000`; the guest-visible address stays inside `$0000`–`$FFFF`.

Page zero of the guest is installed by copying eight bytes (`pageimg`) to 8080 address 0 after the program has been loaded. The program itself is read through PEM into guest `$0100` upward. The command tail is parsed in the DOS/65 default buffer at `$0128` and written into the guest's file control blocks.

The screen is the ROM's 80 by 50 text buffer at `$40800`, still in bank 4, below the guest. `run8080` clears all 4000 bytes at startup so the DOS/65 prompt does not show through. Character cells are one byte each. The cursor is not a software blink. The colour RAM at `$FF80000` has a blink bit and a reverse bit in the high nibble, and the video chip already honours them because the ROM turned that mode on. `place_cursor` saves the colour byte under the cursor, sets those two bits, and restores the previous cell when the cursor moves. The colour pointer in `$D064`/`$D065` is added so the cell matches the screen the ROM is showing. `$D031` is not written. It is a hot register: any write makes the video chip recompute the screen address from `$D018` and the VIC-II banking bits, and the display then shows whatever RAM that legacy address happens to name.

DMAgic is also used for the guest's own block moves when a transfer is large enough to be worth a list, and for scrolling the 50-row terminal window. Lists that stay inside the first megabyte are started at `$D700`. Lists that name the Attic are started at `$D705`. The CPU sees `$D000` only while the DMA map is installed (`map_dma`); `map_dos` puts the DOS/65 map back before the next guest instruction.

```
physical address          what it is
$00000000  bank 0         kernel data, never written by run8080
$00040000  bank 4         ROM data, then the 80 by 50 screen at $40800
$00042000  bank 4         guest $0000–$DFFF
$00050000  bank 5         DOS/65, the SIM, and RUN8080.COM
$08000000  Attic          guest $E000–$FFFF, the stub image
$0FF80000                 colour RAM, one byte per screen cell
```

## Ways this can grow

A Z80, even a partial one, is the change that unlocks Turbo Pascal 3 and a lot of later CP/M software. The prefixes `$CB`, `$DD`, `$ED` and `$FD` already stop at one place (`stop_prefix`). The work is the instructions behind them, the alternate register set, and tests against a known Z80 core. It does not require a different memory map.

The unimplemented BIOS entries are the next limit for WordStar itself. List output, punch, reader, and the disk entries (`SELDSK`, `SETTRK`, `SETSEC`, `SETDMA`, `READ`, `WRITE`, `SECTRAN`) each correspond to a SIM jump. The SIM base is already discovered from the warm-boot vector at `$0100`. A program that does its own sector I/O through the BIOS would then run, with the same geometry the SIM probed.

The terminal set can grow without changing the interpreter. The state machine in `adm_out` is where a new escape sequence goes. A real caret, as opposed to the up-arrow glyph, means a font change that does not retarget the video chip's character pointer by accident and does not write `$D031`. Patching eight bytes of the system font in place, if that font is in RAM, is the smaller version of that change.

Random-record files larger than 512 KB need a module byte DOS/65 does not have. Extending the directory format would be a DOS/65 change, not an emulator change, and it would break the property that a guest file is an ordinary DOS/65 file.

The interpreter's speed is dominated by the indirect load on every operand and by the jump back to `dispatch`. Grouping the common register-to-register moves into shorter routines, or keeping the program counter's physical pointer valid across several instructions instead of rebuilding it, is the sort of change that helps every guest. Recompiling a guest to 45GS02 code, which was the earlier translator experiment, is faster still and is a different program: it cannot run an unmodified `.COM`.

The Python bench in `bench/` is the safety net for all of the above. It runs the same `RUN8080.COM` image on a 45GS02 stepper, with PEM and the SIM trapped, and compares console and disk results with a CP/M model. A new BIOS entry or a new opcode should arrive with a test there before it is tried on the machine.
