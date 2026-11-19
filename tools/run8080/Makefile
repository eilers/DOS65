# Build RUN8080.COM with bsa (Bit Shifter's Assembler) and optionally
# copy it onto the DOS/65 disk image with ctools.

BSA = ../../bsa/bsa
CTOOLS = ../../ctools/src/ctools
DISK = ../../src/c65/disk/dos65_cpm.d64

.PHONY: all disk test

all: RUN8080.COM

handlers.asm: gen_handlers.py
	python3 gen_handlers.py

RUN8080.COM: run8080.asm handlers.asm
	$(BSA) -i run8080.asm

disk: RUN8080.COM
	@if [ -f $(DISK) ]; then $(CTOOLS) $(DISK) p RUN8080.COM; else echo "disk image absent, skipped"; fi

test: RUN8080.COM
	python3 -m pytest -q
