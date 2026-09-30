# R58 ham firmware build (notes/toolchain.md).
#   make          - build/r58.bin: r58.s (sdasz80) and the C modules c/*.c
#                   (SDCC), linked with sdldz80; map and listing next to it
#   make banktest - build-banktest/r58-banktest.bin: 64 KB EPROM image that
#                   checks the banked ROM window at boot (bank_test in r58.s)
#   make verify   - the released v3_Z ALs binary, byte-for-byte, twice:
#                   build-release/ (r58.asm converted by as80tosdas.py, built
#                   with this toolchain) and build-as80/ (r58.asm, as80).
#                   build-release is also the reference for test_diff.py.
#   make ref      - build-ref/: the assembler build of git tag $(REF_TAG)
#                   (the last one with the asm alternative to the C
#                   modules, with the bug fixes), the reference for the
#                   module differential tests (emu/tests/test_*_diff.py)

SDCC   ?= sdcc
SDAS   ?= sdasz80
CPP     = cpp -undef -nostdinc -traditional -Wcomment -DLANGUAGE_ASSEMBLY -Dz80
TOOLS   = ../tools
DEFS    = -DP8x

SRC    ?= r58.s
BUILD  ?= build
# link order sets the layout: add new modules at the end
MODULES = squelch_crc timers keys display freq fsk rptr gps aprs menu scan \
	  ptt mainloop
CMODS  ?= $(patsubst %,$(BUILD)/%.rel,$(MODULES))

CFLAGS  = -mz80 --sdcccall 1 --reserve-regs-iy --opt-code-size --max-allocs-per-node 200000

all: $(BUILD)/r58.bin

$(BUILD)/%.rel: c/%.c c/r58.h
	@mkdir -p $(BUILD)
	$(SDCC) $(CFLAGS) -c $< -o $@

$(BUILD)/cglue.inc: $(CMODS) $(TOOLS)/cglue.py
	@mkdir -p $(BUILD)
	python3 $(TOOLS)/cglue.py $(CMODS) > $@

GLUE = $(if $(CMODS),$(BUILD)/cglue.inc)

$(BUILD)/r58.pp.s: $(SRC) asm.h $(TOOLS)/asmpp.py $(GLUE)
	@mkdir -p $(BUILD)
	$(CPP) $(DEFS) -I. -I$(BUILD) $(SRC) | python3 $(TOOLS)/asmpp.py --labels $(BUILD)/r58.labels --linemap $(BUILD)/r58.linemap > $@

# tools/asmleft.py needs the same cpp invocation, outside a C-module build
# (asmpp.py's ABS-area label rewrite breaks its parsing); this prints the
# flags so both places define them once
print-cpp-flags:
	@echo $(CPP) $(DEFS)

$(BUILD)/r58.rel: $(BUILD)/r58.pp.s
	$(SDAS) -plosgffwa -o $@ $<

$(BUILD)/r58.ihx: $(BUILD)/r58.rel $(CMODS) $(TOOLS)/link.py
	python3 $(TOOLS)/link.py -o $(BUILD)/r58 $(BUILD)/r58.rel $(CMODS)

$(BUILD)/r58.bin: $(BUILD)/r58.ihx $(TOOLS)/ihx2bin.py
	python3 $(TOOLS)/ihx2bin.py $< $@ --map $(BUILD)/r58.map --cksum rom_cksum $(IHXFLAGS)

# sha256 of the released r58p8x3Z.bin (v3_Z ALs 24.09.2018)
ALS_SHA256 = cdfe7016a991766454f1b3aa49e9a1eac0978f42e9a5638bf8828b1f725d8fb7

verify: release build-as80/r58.bin
	@echo "$(ALS_SHA256)  build-release/r58.bin" | sha256sum -c -
	@echo "$(ALS_SHA256)  build-as80/r58.bin" | sha256sum -c -

release: build-release/r58.s
	$(MAKE) SRC=build-release/r58.s BUILD=build-release CMODS=

build-release/r58.s: r58.asm $(TOOLS)/as80tosdas.py
	@mkdir -p build-release
	python3 $(TOOLS)/as80tosdas.py r58.asm > $@ 2> build-release/as80tosdas.log

AS80 = $(TOOLS)/as80/as80
$(AS80):
	$(MAKE) -C $(TOOLS)/as80

as80: build-as80/r58.bin
build-as80/r58.bin: r58.asm $(AS80)
	@mkdir -p build-as80
	$(AS80) $(DEFS) -d -o $@ r58.asm > build-as80/r58.lst

# ROM window bench test for a real board: 64 KB image for a 27C512
banktest: build-banktest/r58-banktest.bin
build-banktest/r58-banktest.bin: $(SRC) asm.h $(TOOLS)/banktest.py
	$(MAKE) BUILD=build-banktest DEFS="$(DEFS) -DBANK_TEST" IHXFLAGS="--bank1-sum bank1_sum --bank2-sum bank2_sum"
	python3 $(TOOLS)/banktest.py build-banktest/r58.bin $@

# the pinned assembler reference (git archive of $(REF_TAG) into build-ref/)
REF_TAG = asm-final
ref: build-ref/r58.bin
build-ref/r58.bin:
	rm -rf build-ref
	mkdir -p build-ref/src
	git -C .. archive $(REF_TAG) firmware tools | tar -x -C build-ref/src
	$(MAKE) -C build-ref/src/firmware BUILD=$(CURDIR)/build-ref

clean:
	rm -rf build build-c build-as80 build-release build-banktest build-ref

.PHONY: all verify release as80 banktest ref clean print-cpp-flags
