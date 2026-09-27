# R58 ham firmware build.
#   make          - assemble r58.asm -> build/r58.bin (+ listing with symbols)
#   make verify   - check that the unmodified ALs source reproduces the
#                   released 24.09.2018 binary byte-for-byte

#   make C=1      - experimental: replace some routines with C modules from
#                   c/*.c (needs SDCC 4.x; set SDCC=/path/to/sdcc)

AS80  = ../tools/as80/as80
SDCC ?= sdcc
ifeq ($(C),1)
BUILD = build-c
ASFLAGS = -DC_MODULES -I$(BUILD)
CMODS = $(BUILD)/squelch_crc.inc
else
BUILD = build
endif

all: $(BUILD)/r58.bin

$(AS80):
	$(MAKE) -C ../tools/as80

$(BUILD)/r58.bin: r58.asm $(AS80) $(CMODS)
	@mkdir -p $(BUILD)
	$(AS80) -DP8x $(ASFLAGS) -d -o $@ r58.asm > $(BUILD)/r58.lst

$(BUILD)/%.inc: c/%.c ../tools/sdcc2as80.py
	@mkdir -p $(BUILD)
	$(SDCC) -mz80 --sdcccall 1 --reserve-regs-iy --opt-code-size --max-allocs-per-node 200000 \
		-S $< -o $(BUILD)/$*.s
	python3 ../tools/sdcc2as80.py $(BUILD)/$*.s -d $(BUILD)/$*_data.inc > $@

# sha256 of the released r58p8x3Z.bin (v3_Z ALs 24.09.2018)
ALS_SHA256 = cdfe7016a991766454f1b3aa49e9a1eac0978f42e9a5638bf8828b1f725d8fb7

verify: $(BUILD)/r58.bin
	@echo "$(ALS_SHA256)  $(BUILD)/r58.bin" | sha256sum -c -

clean:
	rm -rf build build-c

.PHONY: all verify clean
