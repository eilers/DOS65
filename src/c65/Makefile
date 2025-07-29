BSA= ../../bsa/bsa_m2.x

.PONY: all

all: c65loader.prg c65boot.bin

clean:
	rm -f *.bin *.lst *.sym *.prg *_map.png *_map.txt


c65loader.prg: c65loader.asm
	$(BSA) c65loader.asm

c65boot.bin: c65boot.asm
	$(BSA) c65boot.asm

c65sim.bin: c65sim.asm
	$(BSA) -i c65sim.asm
