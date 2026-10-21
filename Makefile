# Build truncate.exe for 16-bit MS-DOS with Open Watcom.
#   make WATCOM=~/opt/watcom

WATCOM ?= $(HOME)/opt/watcom
export WATCOM
export INCLUDE := $(WATCOM)/h
export PATH := $(WATCOM)/binl64:$(WATCOM)/binl:$(PATH)

VERSION := $(shell cat VERSION)

CC     = wcl
CFLAGS = -q -bt=dos -ms -0 -os -s -wx -we -zq '-DVERSION="$(VERSION)"'

SRCS = truncate.c

truncate.exe: $(SRCS) VERSION
	$(CC) $(CFLAGS) -fe=$@ $(SRCS)

test: truncate.exe
	sh tests/run.sh $(CURDIR)/truncate.exe

clean:
	rm -f *.o *.obj *.err truncate.exe

.PHONY: test clean
