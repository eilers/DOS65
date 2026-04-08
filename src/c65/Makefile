# BSA= ../../bsa/bsa_m2.x
BSA= ../../bsa/bsa
CTOOLS= ../../ctools/src/ctools
CFORMAT= ../../ctools/src/cformat
CC1541= ../../cc1541/cc1541
MERGER= ../../scripts/merge_d64.py

CPM_BASE_DISK= disk/dos65_cpm_base.d64
CPM_DISK= disk/dos65_cpm.d64
C64_DISK= disk/dos65_c64.d64
DISK= disk/dos65_V2.15.D64

.PHONY: all clean load xemu distribution

all: $(BSA) $(CTOOLS) $(CC1541) c65sim.bin c65boot.bin c65run.prg # c65loader.prg 
clean:
	rm -f *.bin *.lst *.sym *.prg *_map.png *_map.txt disk/*.COM disk/*.C65 ../*.lst 
	rm -f $(DISK) $(CPM_BASE_DISK) $(CPM_DISK) $(C64_DISK)
	$(MAKE) -C ../../bsa clean
	$(MAKE) -C ../../ctools/src clean
	$(MAKE) -C ../../cc1541 clean

load:	all
	/Applications/m65tools/m65.osx -l /dev/cu.usbserial-1101 c65run.prg
	/Applications/m65tools/m65dbg -l /dev/cu.usbserial-1101 
	
xemu:	all distribution
	/Users/stefan/Developer/c65/xemu_gurce/build/bin/xmega65.native -prg ./c65run.prg -prgtest "print \"run\""  -uartmon :4510 -8 $(DISK)  &
	/Users/stefan/Developer/c65/m65dbg/m65dbg -l tcp

$(BSA): ../../bsa/bsa.c
	$(MAKE) -C ../../bsa

$(CTOOLS):
	$(MAKE) -C ../../ctools/src

$(CC1541):
	$(MAKE) -C ../../cc1541

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
ASM_FILES = MORE202.ASM \
            BASIC202.ASM \
            COMPL205.ASM \
            RUN207.ASM \
	    ASM213.ASM 
#            EDIT205.ASM \
#            COMPR204.ASM \
            ALLOC208.ASM \
            DEBUG204.ASM \
            DISKC205.ASM \
            DUMP100.ASM \
            MON1002.ASM \
            PAGE100.ASM \
            HXCOM200.ASM \
            MKCOM204.ASM \
            SUBMIT.ASM (ONLY 3.x)

# Generate COM file names by replacing .ASM with .COM
COM_FILES = $(ASM_FILES:.ASM=.COM)

# Pattern rule to build COM files from ASM files
%.COM: $(BSA) ../%.ASM
	mkdir -p disk
	$(BSA) -i ../$*.ASM

$(CPM_BASE_DISK): all
	mkdir -p disk
	rm -f $(CPM_BASE_DISK)
	$(CFORMAT) -0 $(CPM_BASE_DISK)

$(CPM_DISK): $(CPM_BASE_DISK) all $(COM_FILES)
	cp $(CPM_BASE_DISK) $(CPM_DISK)
	$(CTOOLS) $(CPM_DISK) p disk/*.COM
	$(CTOOLS) $(CPM_DISK) p ../basic/*.BAS
	#$(CTOOLS) $(CPM_DISK) p ../RUN207.ASM

$(C64_DISK): all
	mkdir -p disk
	rm -f $(C64_DISK)
	cp c65run.prg disk/AUTOBOOT.C65
	$(CC1541) -n "dos/65 v2.15" -T PRG -w disk/autoboot.c65 $(C64_DISK)

distribution: $(CPM_BASE_DISK) $(CPM_DISK) $(C64_DISK) $(MERGER)
	python3 $(MERGER) --c64 $(C64_DISK) --cpm $(CPM_DISK) --cpm-base $(CPM_BASE_DISK)  --out $(DISK)
