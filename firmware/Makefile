# R58 ham firmware build (notes/toolchain.md).
#   make          - build/r58.bin from r58.s (sdasz80 + sdldz80), map and
#                   listing next to it
#   make verify   - check that the unmodified source reproduces the released
#                   v3_Z ALs binary byte-for-byte
#   make C=1      - build-c/r58.bin with some routines replaced by the C
#                   modules c/*.c (SDCC), linked as normal objects
#   make as80     - build-as80/r58.bin from the original as80 source r58.asm
#                   (reference only; also checked by verify)

SDCC   ?= sdcc
SDAS   ?= sdasz80
CPP     = cpp -undef -nostdinc -traditional -Wcomment -DLANGUAGE_ASSEMBLY -Dz80
TOOLS   = ../tools
DEFS    = -DP8x

ifeq ($(C),1)
BUILD   = build-c
DEFS   += -DC_MODULES
CMODS   = $(BUILD)/squelch_crc.rel
else
BUILD   = build
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

$(BUILD)/r58.pp.s: r58.s asm.h $(TOOLS)/asmpp.py $(GLUE)
	@mkdir -p $(BUILD)
	$(CPP) $(DEFS) -I. -I$(BUILD) r58.s | python3 $(TOOLS)/asmpp.py --labels $(BUILD)/r58.labels > $@

$(BUILD)/r58.rel: $(BUILD)/r58.pp.s
	$(SDAS) -plosgffwa -o $@ $<

$(BUILD)/r58.ihx: $(BUILD)/r58.rel $(CMODS) $(TOOLS)/link.py
	python3 $(TOOLS)/link.py -o $(BUILD)/r58 $(BUILD)/r58.rel $(CMODS)

$(BUILD)/r58.bin: $(BUILD)/r58.ihx $(TOOLS)/ihx2bin.py
	python3 $(TOOLS)/ihx2bin.py $< $@ --map $(BUILD)/r58.map --cksum rom_cksum

# sha256 of the released r58p8x3Z.bin (v3_Z ALs 24.09.2018)
ALS_SHA256 = cdfe7016a991766454f1b3aa49e9a1eac0978f42e9a5638bf8828b1f725d8fb7

verify: $(BUILD)/r58.bin build-as80/r58.bin
	@echo "$(ALS_SHA256)  $(BUILD)/r58.bin" | sha256sum -c -
	@echo "$(ALS_SHA256)  build-as80/r58.bin" | sha256sum -c -

AS80 = $(TOOLS)/as80/as80
$(AS80):
	$(MAKE) -C $(TOOLS)/as80

as80: build-as80/r58.bin
build-as80/r58.bin: r58.asm $(AS80)
	@mkdir -p build-as80
	$(AS80) $(DEFS) -d -o $@ r58.asm > build-as80/r58.lst

clean:
	rm -rf build build-c build-as80

.PHONY: all verify as80 clean
