# BSA= ../../bsa/bsa_m2.x
BSA= ../../bsa/bsa
CTOOLS= ../../ctools/src/ctools
CFORMAT= ../../ctools/src/cformat
DISK= disk/dos65_V2.15.D64

.PONY: all clean load xemu distribution

all: $(BSA) $(CTOOLS) c65sim.bin sysgn219.com c65boot.bin c65run.prg # c65loader.prg 
clean:
	rm -f *.bin *.lst *.sym *.prg *_map.png *_map.txt disk/*.COM ../*.lst 
	$(MAKE) -C ../../bsa clean
	$(MAKE) -C ../../ctools/src clean

load:	all
	/Applications/m65tools/m65.osx -l /dev/cu.usbserial-1101 c65run.prg
	/Applications/m65tools/m65dbg -l /dev/cu.usbserial-1101 
	
xemu:	all
	/Users/stefan/Developer/c65/xemu_gurce/build/bin/xmega65.native -prg ./c65run.prg -prgtest "print \"run\""  -uartmon :4510 -8 ../../disks/V2/C64/DOS65-1C.D64  &
	/Users/stefan/Developer/c65/m65dbg/m65dbg -l tcp

$(BSA): ../../bsa/bsa.c
	$(MAKE) -C ../../bsa

$(CTOOLS):
	$(MAKE) -C ../../ctools/src

pem.bin: ../pem.asm
	$(BSA) ../pem.asm

c65boot.bin: c65boot.asm
	$(BSA) c65boot.asm

c65sim.bin: c65sim.asm  macros.asm ../pem.asm ../ccm.asm ../constants.asm macros.asm kernel.asm
	$(BSA) -i c65sim.asm

sysgn219.com: ../SYSGN219.asm ../pem.asm ../ccm.asm ../constants.asm
	$(BSA) ../SYSGN219.asm

c65loader.prg: c65loader.asm  ../pem.asm ../ccm.asm ../constants.asm macros.asm kernel.asm
	$(BSA) c65loader.asm

c65run.prg: c65run.asm c65sim.bin ../constants.asm macros.asm kernel.asm
	$(BSA) c65run.asm
	# Remove the first two bytes from binary that was added by
	# BSA as load address header. But I don't want it here.. 
	tail +3c dos65.bin > dos65.bin.truncated && mv dos65.bin.truncated dos65.bin
	# Attach the os and the sim to the end of the runner.. 
	cat dos65.bin  >> c65run.prg
	cat c65sim.bin >> c65run.prg

# List of ASM files to build as COM files
# Add or remove entries from this list as needed
ASM_FILES = MORE202.ASM 
#            EDIT205.ASM \
            RUN207.ASM \
            ASM213.ASM \
            BASIC202.ASM \
            COMPL205.ASM \
            COMPR204.ASM \
            DEBUG204.ASM \
            DISKC205.ASM \
            DUMP100.ASM \
            HXCOM200.ASM \
            MKCOM204.ASM \
            MON1002.ASM \
            PAGE100.ASM \
            SUBMIT.ASM

# Generate COM file names by replacing .ASM with .COM
COM_FILES = $(ASM_FILES:.ASM=.COM)

# Pattern rule to build COM files from ASM files
%.COM: $(BSA) ../%.ASM
	mkdir -p disk
	$(BSA) -i ../$*.ASM

distribution: all $(COM_FILES)
	mkdir -p disk
	rm $(DISK)
	$(CFORMAT) -0 $(DISK)
	$(CTOOLS) $(DISK) p disk/*.COM 
