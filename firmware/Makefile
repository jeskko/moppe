# R58 ham firmware build (notes/toolchain.md).
#   make          - build/r58.bin from r58.s (sdasz80 + sdldz80), map and
#                   listing next to it
#   make C=1      - build-c/r58.bin with some routines replaced by the C
#                   modules c/*.c (SDCC), linked as normal objects
#   make banktest - build-banktest/r58-banktest.bin: 64 KB EPROM image that
#                   checks the banked ROM window at boot (bank_test in r58.s)
#   make verify   - the released v3_Z ALs binary, byte-for-byte, twice:
#                   build-release/ (r58.asm converted by as80tosdas.py, built
#                   with this toolchain) and build-as80/ (r58.asm, as80).
#                   build-release is also the reference for the differential
#                   tests (emu/tests/test_diff.py).

SDCC   ?= sdcc
SDAS   ?= sdasz80
CPP     = cpp -undef -nostdinc -traditional -Wcomment -DLANGUAGE_ASSEMBLY -Dz80
TOOLS   = ../tools
DEFS    = -DP8x

SRC    ?= r58.s
ifeq ($(C),1)
BUILD  ?= build-c
DEFS   += -DC_MODULES
CMODS   = $(BUILD)/squelch_crc.rel $(BUILD)/timers.rel $(BUILD)/keys.rel $(BUILD)/display.rel
else
BUILD  ?= build
endif

CFLAGS  = -mz80 --sdcccall 1 --reserve-regs-iy --opt-code-size --max-allocs-per-node 200000

all: $(BUILD)/r58.bin

$(BUILD)/%.rel: c/%.c
	@mkdir -p $(BUILD)
	$(SDCC) $(CFLAGS) -c $< -o $@

$(BUILD)/cglue.inc: $(CMODS) $(TOOLS)/cglue.py
	@mkdir -p $(BUILD)
	python3 $(TOOLS)/cglue.py $(CMODS) > $@

GLUE = $(if $(CMODS),$(BUILD)/cglue.inc)

$(BUILD)/r58.pp.s: $(SRC) asm.h $(TOOLS)/asmpp.py $(GLUE)
	@mkdir -p $(BUILD)
	$(CPP) $(DEFS) -I. -I$(BUILD) $(SRC) | python3 $(TOOLS)/asmpp.py --labels $(BUILD)/r58.labels --linemap $(BUILD)/r58.linemap > $@

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
	$(MAKE) SRC=build-release/r58.s BUILD=build-release C=

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
	$(MAKE) BUILD=build-banktest DEFS="$(DEFS) -DBANK_TEST" IHXFLAGS="--bank1-sum bank1_sum" C=
	python3 $(TOOLS)/banktest.py build-banktest/r58.bin $@

clean:
	rm -rf build build-c build-as80 build-release build-banktest

.PHONY: all verify release as80 banktest clean
