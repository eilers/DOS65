# BSA= ../../bsa/bsa_m2.x
BSA= ../../bsa/bsa

.PONY: all

all: $(BSA) c65loader.prg c65boot.bin c65sim.bin sysgen.bin

clean:
	rm -f *.bin *.lst *.sym *.prg *_map.png *_map.txt *.com ../*.lst
	$(MAKE) -C ../../bsa clean

$(BSA): ../../bsa/bsa.c
	$(MAKE) -C ../../bsa


c65loader.prg: c65loader.asm
	$(BSA) c65loader.asm

c65boot.bin: c65boot.asm
	$(BSA) c65boot.asm

c65sim.bin: c65sim.asm
	$(BSA) -i c65sim.asm

sysgen.bin: ../SYSGN219.asm
	$(BSA) ../SYSGN219.asm
