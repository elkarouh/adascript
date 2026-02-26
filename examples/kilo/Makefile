# Makefile for kilo text editor (HNIM)
# nim.cfg provides --path:".." for HNIM imports

NIMFLAGS ?= -g --linedir:on --debuginfo --opt:none

all: kilo

kilo: kilo.nim
	nim c $(NIMFLAGS) -o:$@ $<

clean:
	rm -f kilo
	rm -rf nimcache/

rebuild: clean all

debug: NIMFLAGS += -d:debug --stacktrace:on --lineTrace:on
debug: clean all

release: NIMFLAGS := -d:release --opt:speed
release: clean all

run: kilo
	./kilo $(ARGS)

.PHONY: all clean rebuild debug release run
