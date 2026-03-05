## Makefile for phonecode

NIM = nim
NIMFLAGS = -d:release -p:../../
TARGET = phonecode
TEST_DICT = test_words.txt
TEST_PHONES = test_phones.txt

.PHONY: all build run clean help

all: build

build: $(TARGET)

$(TARGET): phonecode.nim
	$(NIM) c $(NIMFLAGS) -o:$@ $<

run: $(TARGET)
	./$(TARGET) $(TEST_DICT) $(TEST_PHONES)

clean:
	$(RM) $(TARGET)
	$(RM) -r nimcache

help:
	@echo "Targets: all, build, run, clean"
