# R58 ham firmware build.
#   make          - assemble r58.asm -> build/r58.bin (+ listing with symbols)
#   make verify   - check that the unmodified ALs source reproduces the
#                   released 24.09.2018 binary byte-for-byte

AS80  = ../tools/as80/as80
BUILD = build

all: $(BUILD)/r58.bin

$(AS80):
	$(MAKE) -C ../tools/as80

$(BUILD)/r58.bin: r58.asm $(AS80)
	@mkdir -p $(BUILD)
	$(AS80) -DP8x -d -o $@ r58.asm > $(BUILD)/r58.lst

# sha256 of the released r58p8x3Z.bin (v3_Z ALs 24.09.2018)
ALS_SHA256 = cdfe7016a991766454f1b3aa49e9a1eac0978f42e9a5638bf8828b1f725d8fb7

verify: $(BUILD)/r58.bin
	@echo "$(ALS_SHA256)  $(BUILD)/r58.bin" | sha256sum -c -

clean:
	rm -rf $(BUILD)

.PHONY: all verify clean
