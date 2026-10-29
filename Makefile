MARS    ?= java -jar tools/Mars.jar
ASM     ?= asm/svm.asm
PYTHON  ?= python3

.PHONY: all assemble run test

all: assemble

assemble:
	$(MARS) a nc ae1 $(ASM)

run:
	$(MARS) nc ae1 $(ASM)

test: assemble
	$(PYTHON) tests/diff_test.py
