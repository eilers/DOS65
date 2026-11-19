# run8080

`run8080` is a DOS/65 program for the MEGA65. It runs an 8080 `.COM` program and turns that program's system calls into native DOS/65 calls. The 8080 program is the only thing emulated. The disk and the console stay with DOS/65, so there is no second file system.

A few names used below:

- **PEM** is the Primitive Execution Module, the DOS/65 counterpart of the CP/M BDOS (Basic Disk Operating System).
- **SIM** is the System Interface Module, the DOS/65 counterpart of the CP/M BIOS.
- **CCM** is the Console Command Module, the DOS/65 command interpreter.
- **TEA** is the transient execution area, where DOS/65 loads `RUN8080.COM`.
- **FCB** is a file control block. CP/M uses 36 bytes; DOS/65 uses 33.
- **TPA** is the transient program area the 8080 program may use, `$0100` to `$DFFF`.
- **DMAgic** is the MEGA65 block-copy engine.
- **Attic RAM** is the memory at `$8000000`, above the chip RAM banks.

## Build and run

From this directory:

```
make
```

That runs `gen_handlers.py` and then bsa (Bit Shifter's Assembler) on `run8080.asm`, producing `RUN8080.COM`. `make disk` copies it onto `src/c65/disk/dos65_cpm.d64` with ctools when that image is present. `make test` runs the Python bench.

On the MEGA65, after DOS/65 is up:

```
run8080 sc2
```

The first word of the command tail is the program name. `.COM` is added when no extension was typed. The rest of the tail becomes the CP/M file control blocks at `$5C` and `$6C` and the command tail at `$80`.

The machine is already at its 40 MHz fast clock, and `run8080` leaves that clock alone. On the way out it jumps to the DOS/65 warm boot at `$0100`.

## Program disks

The MEGA65 SIM (System Interface Module) 1.01 reads two disk formats on drives A and B: the C64 CP/M format on a 1541 disk (`.d64`, 134 KB), and the C128 CP/M format on a 1581 disk (`.d81`, 790 KB). After each warm boot, the SIM asks each drive for track 40 the first time that drive is used. Only a 1581 disk has track 40, and its CBM (Commodore DOS) header there has format `D`. So change disks only at the `A>` prompt, then press Control-C.

On a 1581 disk, a DOS/65 track is one half of a 1581 track (20 sectors). The first half of track 40 holds the CBM header and directory, and DOS/65 skips it. Blocks are 2 KB, the highest block is 396, and there are 128 directory entries. These are the values of the C128 CP/M BIOS, so C128 CP/M 1581 disks can be read directly.

`mkd81.py` makes such a disk. It copies every user 0 file of a CP/M disk image, and it can add host files:

```
python3 mkd81.py supercalc2.d81 --name "SUPERCALC 2" --id S2 --from SuperCalc_v2.d81
python3 mkd81.py tools.d81 --name TOOLS FILE.COM OTHER.DAT
```

The new disk has a fresh directory. CP/M attribute bits are cleared, because DOS/65 compares file names byte by byte. The CBM BAM (block availability map) marks every sector as used, so the MEGA65's own DOS does not write into the CP/M data.

## Where the 64 KB lives

Bank 0 is left alone. It holds kernel data and the SIM-to-kernel bridge. Banks 2 and 3 are ROM. Bank 5 is DOS/65 itself.

Bank 4's first 8 KB (`$40000`–`$41FFF`) belongs to the MEGA65 ROM; its 80 by 50 text screen starts at `$40800`, and the guest draws on the top 24 rows there. The free 56 KB after it (`$42000`–`$4FFFF`) is the 8080 address range `$0000`–`$DFFF`. A 32-bit pointer's low 16 bits are the 8080 address plus `$2000`, and the high word is `$0004`. The guest's own bytes are read and written with `LDA [pointer],Z` and `STA [pointer],Z`, which do not use the memory map.

8080 `$E000`–`$FFFF` is an 8 KB read-only stub image in Attic RAM at `$8000000`. Address 6 holds `$E000`, so BDOS appears to start there and the guest cannot grow into bank 5. A write at or above `$E000` stops the program and names the address. Fetches and reads of the stub are allowed. The stub pages are copied with an enhanced DMAgic list (megabyte option `$80`, meaning bits 20–27 of the address, started at `$D705`). If that copy does not land, `run8080` stops instead of falling into bank 0.

## System calls

Page zero of the guest is the usual CP/M page: a jump to the warm boot at 0, a jump to BDOS at 5, the file control blocks, and the DMA address. The BDOS stub and the BIOS table are `OUT n` instructions. `OUT` is acted on only inside the stub image. `IN`, and `OUT` below `$E000`, stop the program. The Z80 prefixes `$CB`, `$DD`, `$ED` and `$FD` stop it too. `DI` and `EI` are ignored. `HLT`, BDOS function 0, and a jump or call to `$0000` all leave through the normal exit.

Functions 1–11 and 13–29 are passed to PEM, with two exceptions. Function 6 is the direct console call and is drawn by `run8080` itself. Function 12 does not call PEM: PEM 12 is the list-status call, so `run8080` returns the CP/M version `$0022` on its own. Functions 31, 33, 34, 35, 36, 37 and 40 are small shims. Function 31 builds a CP/M disk parameter block from the DOS/65 disk control block. Functions 33, 34 and 40 turn the random record into an extent and a record, then do a sequential read or write. A record past the first 16 KB needs that extent's directory entry, because a DOS/65 sequential read stays in the extent the file was opened with. A write to an extent that is not in the directory creates it. Extents it skips are not created, as on CP/M, so a later sequential read ends at the gap. A sequential read already moves to the next extent on its own: the DOS/65 read does that when the record counter reaches 128. DOS/65 files end after 32 extents (512 KB), because DOS/65 has no module byte, so a random record from 4096 up returns error 6. Setting the user number to anything but 0 stops the program. Any other function stops, and the message includes the function number.

A BIOS call stops and names the entry. The benchmark program does not make one.

## The screen

SuperCalc 2 on this disk is installed for an ADM-3A terminal, and it draws by calling BDOS function 6. Those bytes must not go through SIM console output, which drops the escape character. `run8080` interprets them onto the top 24 rows of the 80 by 50 screen:

- Escape, `=`, row, column places the cursor. The program has already added 32 to the row and the column.
- Control-Z clears the screen.
- The MEGA65 cursor keys are translated before the program sees them: up is Control-K (`$0B`), down is Control-J (`$0A`), left is Control-H (`$08`), right is Control-L (`$0C`). Cursor down and cursor right arrive as 17 and 29. Cursor up and cursor left arrive as 145 and 157, and the System Interface Module passes those two through so this translation can see them.

## What the bench checks

`tools/run8080/bench` is the Python model reused from the earlier translator work: an 8080, a CP/M machine, a DOS/65 machine, and a 45GS02 stepper that covers the instructions and the DMAgic lists this program uses. `make test` compares every 8080 opcode with random state, the BDOS functions SuperCalc 2 calls, and the two short CPU diagnostics `8080PRE` and `TST8080`. Both of those print their success line under the bench.

`CPUTEST` and `8080EXM` are the long suites. `8080EXM` is about three billion instructions, which is not a practical run of this bench or of one interactive session. They are not copied into the repository.

The acceptance run is SuperCalc 2, from `prod/SuperCalc_v2.d81` (kept outside this tree). The test signs on, loads `SAMPLE.CAL`, types a value into the current cell, saves, and compares the saved file and the 80 by 24 screen with the same session on the CP/M model. It skips when the disk image is absent.

## Speed

On the NOP / DCX / MOV / ORA / JNZ mix, the bench executes **70.4** 45GS02 instructions for each 8080 instruction, about **30,000** emulated 8080 instructions per second in CPython. That number is the interpreter, not the MEGA65.

xemu (`xmega65.native`) is already at **40.50 MHz** when DOS/65 is started from `c65run.prg`. `run8080` does not change that clock. A guest that prints a line and returns to the DOS/65 prompt has been run there. The measured instruction mix above is the Python bench, not a stopwatch sample from xemu.
