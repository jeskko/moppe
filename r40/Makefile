# R40 ham firmware: build/r40.bin (the 256 KB EPROM image's first part),
# with build/r40.map and the generated .s files.
#   make            build
#   make test       firmware scenarios in the emulator (tests/r40)
#   make run        terminal UI on the emulator
TOP  := ..
H8CC := $(TOP)/tools/h8500/h8cc.py
SRCS := start.s hw.c i2c.c lcd.c font.c keypad.c serbus.c audio.c pll.c radio.c ui.c nv.c main.c
HDRS := $(wildcard *.h)

all: build/r40.bin

build/r40.bin: $(SRCS) $(HDRS) $(H8CC)
	@mkdir -p build
	python3 $(H8CC) -S --lib none --crt start.s -o $@ $(filter-out start.s,$(SRCS))

test: build/r40.bin
	python3 -m pytest -q $(TOP)/tests/r40

run: build/r40.bin
	python3 $(TOP)/emu/python/r40tui.py --rom build/r40.bin

clean:
	rm -rf build

.PHONY: all test run clean
