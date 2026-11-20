# Build RUN8080.COM with bsa (Bit Shifter's Assembler) and optionally
# copy it onto the DOS/65 disk image with ctools.

BSA = ../../bsa/bsa
CTOOLS = ../../ctools/src/ctools
DISK = ../../src/c65/disk/dos65_cpm.d64
# The bench requires Python 3.11 and py65, the 6502 emulator imported
# by the DOS/65 model. The test target installs both into .venv.
PYTHON = python3.11
VENV = .venv
PY = $(VENV)/bin/python

.PHONY: all disk test

all: RUN8080.COM

handlers.asm: gen_handlers.py
	python3 gen_handlers.py

RUN8080.COM: run8080.asm handlers.asm
	$(BSA) -i run8080.asm

disk: RUN8080.COM
	@if [ -f $(DISK) ]; then $(CTOOLS) $(DISK) p RUN8080.COM; else echo "disk image absent, skipped"; fi

$(VENV)/.installed: pyproject.toml
	$(PYTHON) -m venv $(VENV)
	$(PY) -m pip install -q -e '.[test]'
	touch $@

test: RUN8080.COM $(VENV)/.installed
	$(PY) -c 'from bench.testdata import fetch_cpu_tests; fetch_cpu_tests()'
	$(PY) -m pytest -q
