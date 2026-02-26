# Generic Makefile for Nim projects with HNIM
# Automatically detects .nim files and provides common targets

# Configuration
NIMFLAGS ?= -g --linedir:on --debuginfo --opt:none
HNIM_PATH ?= $(HOME)/ADA_PLAYGROUND/HNIM
NIM_PATH_FLAGS ?= -p:$(HNIM_PATH)

# Auto-detect all .nim files in current directory
NIM_FILES := $(wildcard *.nim)

# Build targets (executables) - replace .nim extension with nothing or custom name
TARGETS := $(NIM_FILES:.nim=)

# Default target
all: $(TARGETS)

# Pattern rule: build any .nim file to executable
%: %.nim
	nim c $(NIMFLAGS) $(NIM_PATH_FLAGS) -o:$@ $<

# Build all targets
build: $(TARGETS)

# Clean build artifacts
clean:
	rm -f $(TARGETS) $(TARGETS:=.o)
	rm -rf nimcache/

# Rebuild from scratch
rebuild: clean all

# Run a specific target (usage: make run TARGET=show_status)
run:
	@if [ -z "$(TARGET)" ]; then \
		echo "Usage: make run TARGET=<name>"; \
		exit 1; \
	fi
	./$(TARGET)

# Debug build with extra flags
debug: NIMFLAGS += -d:debug --stacktrace:on --lineTrace:on
debug: clean all

# Release build
release: NIMFLAGS := -d:release --opt:speed
release: clean all

# Show detected files and targets
info:
	@echo "Nim files found: $(NIM_FILES)"
	@echo "Build targets:   $(TARGETS)"
	@echo "HNIM path:       $(HNIM_PATH)"
	@echo "Nim flags:       $(NIMFLAGS)"

# Help
help:
	@echo "Available targets:"
	@echo "  all      - Build all Nim files (default)"
	@echo "  build    - Same as 'all'"
	@echo "  clean    - Remove build artifacts"
	@echo "  rebuild  - Clean and rebuild"
	@echo "  run      - Run a specific target (make run TARGET=name)"
	@echo "  debug    - Build with debug flags"
	@echo "  release  - Build optimized release"
	@echo "  info     - Show detected files and configuration"
	@echo "  help     - Show this help message"

.PHONY: all build clean rebuild run debug release info help
