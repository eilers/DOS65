# BSA= ../../bsa/bsa_m2.x
BSA= ../../bsa/bsa

.PONY: all

all: $(BSA) c65sim.bin sysgn219.com c65loader.prg c65boot.bin c65run.prg 

clean:
	rm -f *.bin *.lst *.sym *.prg *_map.png *_map.txt *.com ../*.lst
	$(MAKE) -C ../../bsa clean

$(BSA): ../../bsa/bsa.c
	$(MAKE) -C ../../bsa

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
