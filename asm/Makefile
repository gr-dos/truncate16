# Optional 8086 assembly build of truncate (truncate.com) with NASM.
# Not part of the default build: run from the top with "make -C asm".
#   make -C asm            builds truncate.com
#   make -C asm test       runs ../tests/run.sh and the differential
#                          tests against the C truncate.exe
#   make -C asm measure    prints the size / FAT / memory comparison

NASM   ?= nasm
NFLAGS  = -f bin -Werror

VERSION := $(shell cat ../VERSION)

all: truncate.com

truncate.com: truncate.asm ../VERSION
	$(NASM) $(NFLAGS) '-DVERSION="$(VERSION)"' -o $@ truncate.asm

tests/err2out.com: tests/err2out.asm
	$(NASM) $(NFLAGS) -o $@ tests/err2out.asm

tests/tail.com: tests/tail.asm
	$(NASM) $(NFLAGS) -o $@ tests/tail.asm

# The C reference, built by the top-level Makefile (LIBC16_ROOT= on
# this command line is passed down).
../truncate.exe: FORCE
	$(MAKE) -C .. truncate.exe

test: truncate.com tests/err2out.com tests/tail.com ../truncate.exe
	sh ../tests/run.sh $(CURDIR)/truncate.com
	sh tests/diff.sh $(CURDIR)/../truncate.exe $(CURDIR)/truncate.com

measure: truncate.com ../truncate.exe
	NASM=$(NASM) sh measure.sh $(CURDIR)/../truncate.exe \
	    $(CURDIR)/truncate.com $(CURDIR)/truncate.asm

clean:
	rm -f truncate.com tests/err2out.com tests/tail.com

.PHONY: all test measure clean FORCE
