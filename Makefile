###############################################################################
# Top-level Makefile for make_airoha_atf.
#
# Pipeline summary for a supported platform (e.g. an7563):
#   1. Compile flash_table_gen (host tool).
#   2. Run flash_table_gen to emit flash_table.bin.
#   3. LZMA-compress flash_table.bin into flash_table.lzma.
#   4. Pack bl21.bin + bl22.lzma + bl23.lzma + flash_table.lzma into bl2.bin
#      via `trx -z`.
#   5. Append the CRC trailer with `trx -x`, replacing bl2.bin in place.
#   6. LZMA-compress bl31.bin into bl31.lzma.
#
# Common usage:
#       make                    # build bl2.bin and bl31.lzma
#       make PLATFORM=an7563    # explicit platform selection
#       make bl2 / make bl31    # build a single artifact
#       make clean              # remove generated files
#       make distclean          # also clean rebuilt host tools
#       make help               # show resolved variables and targets
#
# Per-IC tuning lives in configs/<PLATFORM>.mk; cross-cutting defaults live
# in config.mk.
###############################################################################

TOP_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

include $(TOP_DIR)/config.mk

# ---- Directory layout -------------------------------------------------------
SRC_DIR          := $(TOP_DIR)/src
TOOLS_DIR        := $(TOP_DIR)/tools
UNOPEN_IMG_DIR   := $(TOP_DIR)/unopen_img/$(PLATFORM)
BUILD_DIR        := $(TOP_DIR)/build/$(PLATFORM)

FLASH_TABLE_DIR  := $(SRC_DIR)/flash_table
FLASH_TABLE_GEN  := $(FLASH_TABLE_DIR)/flash_table_gen

LZMA             := $(TOOLS_DIR)/lzma
TRX              := $(TOOLS_DIR)/trx/trx

# ---- Inputs and outputs -----------------------------------------------------
BL21_BIN         := $(UNOPEN_IMG_DIR)/bl21.bin
BL22_LZMA        := $(UNOPEN_IMG_DIR)/bl22.lzma
BL23_LZMA        := $(UNOPEN_IMG_DIR)/bl23.lzma
BL31_BIN         := $(UNOPEN_IMG_DIR)/bl31.bin

FLASH_TABLE_BIN  := $(BUILD_DIR)/flash_table.bin
FLASH_TABLE_LZMA := $(BUILD_DIR)/flash_table.lzma
BL2_BIN          := $(BUILD_DIR)/bl2.bin
BL31_LZMA        := $(BUILD_DIR)/bl31.lzma

# Suppress command echo unless V=1.
V ?= 0
ifeq ($(V),1)
Q :=
else
Q := @
endif

.PHONY: all bl2 bl31 flash_table trx_build clean distclean help \
	check-bl2-inputs check-bl31-inputs

all: bl2 bl31

help:
	@echo "make_airoha_atf build targets:"
	@echo "  all             - build bl2.bin AND bl31.lzma"
	@echo "  bl2             - generate $(BL2_BIN)"
	@echo "  bl31            - generate $(BL31_LZMA)"
	@echo "  flash_table     - build host flash_table_gen tool only"
	@echo "  trx_build       - rebuild the trx host tool from source"
	@echo "  clean           - remove generated artifacts"
	@echo "  distclean       - clean + remove rebuilt host binaries"
	@echo ""
	@echo "Variables (override on command line, e.g. make PLATFORM=an7563 V=1):"
	@echo "  PLATFORM        = $(PLATFORM)"
	@echo "  CROSS_COMPILE   = $(CROSS_COMPILE)"
	@echo "  HOSTCC          = $(HOSTCC)"
	@echo "  TCSUPPORT_DEFS  = $(TCSUPPORT_DEFS)"
	@echo ""
	@echo "Resolved inputs:"
	@echo "  BL21_BIN  = $(BL21_BIN)"
	@echo "  BL22_LZMA = $(BL22_LZMA)"
	@echo "  BL23_LZMA = $(BL23_LZMA)"
	@echo "  BL31_BIN  = $(BL31_BIN)"

# ---- Pre-flight checks ------------------------------------------------------
# Guards against running the BL2 packaging on platforms that already ship a
# fully-assembled bl2.bin (i.e. anything missing the bl21/bl22/bl23 split).
check-bl2-inputs:
	@if [ ! -f "$(BL21_BIN)" ] || [ ! -f "$(BL22_LZMA)" ] || [ ! -f "$(BL23_LZMA)" ]; then \
		echo "ERROR: bl2 packaging requires bl21.bin / bl22.lzma / bl23.lzma for PLATFORM=$(PLATFORM)"; \
		echo "  expected: $(BL21_BIN)"; \
		echo "            $(BL22_LZMA)"; \
		echo "            $(BL23_LZMA)"; \
		echo "Platforms that already ship a final bl2.bin do not need this project."; \
		exit 1; \
	fi

# Guards against running the BL31 step when no bl31.bin is staged.
check-bl31-inputs:
	@if [ ! -f "$(BL31_BIN)" ]; then \
		echo "ERROR: bl31 source missing for PLATFORM=$(PLATFORM)"; \
		echo "  expected: $(BL31_BIN)"; \
		exit 1; \
	fi

# ---- Host tools -------------------------------------------------------------
flash_table: $(FLASH_TABLE_GEN)

$(FLASH_TABLE_GEN):
	$(Q)$(MAKE) -C $(FLASH_TABLE_DIR) TOP_DIR=$(TOP_DIR)

# Rebuilds the trx tool from source. The repository ships a prebuilt binary,
# so this target is only needed when the prebuilt one is incompatible with
# the build host.
trx_build:
	$(Q)$(MAKE) -C $(TOOLS_DIR)/trx \
		TCSUPPORT_OPENWRT=$(TCSUPPORT_OPENWRT) \
		TCSUPPORT_LITTLE_ENDIAN=$(TCSUPPORT_LITTLE_ENDIAN) \
		TCSUPPORT_BB_256KB=$(TCSUPPORT_BB_256KB) \
		BOOTROM_LARGE_SIZE=$(BOOTROM_LARGE_SIZE) \
		TCSUPPORT_CMCCV2=$(TCSUPPORT_CMCCV2) \
		TCSUPPORT_SECURE_BOOT=$(TCSUPPORT_SECURE_BOOT) \
		TCSUPPORT_BL2_OPTIMIZATION=$(TCSUPPORT_BL2_OPTIMIZATION) \
		TCSUPPORT_SECURE_BOOT_FLASH_OTP=$(TCSUPPORT_SECURE_BOOT_FLASH_OTP) \
		TCSUPPORT_SECURE_BOOT_V1=$(TCSUPPORT_SECURE_BOOT_V1) \
		TCSUPPORT_SECURE_BOOT_V2=$(TCSUPPORT_SECURE_BOOT_V2) \
		TCSUPPORT_BOOTROM_LARGE_SIZE=$(TCSUPPORT_BOOTROM_LARGE_SIZE)

# ---- Build directory --------------------------------------------------------
$(BUILD_DIR):
	$(Q)mkdir -p $(BUILD_DIR)

# ---- BL2 packaging pipeline -------------------------------------------------
# Run flash_table_gen from inside the build directory so its working-directory
# output (flash_table.bin) lands in the per-platform build folder.
$(FLASH_TABLE_BIN): $(FLASH_TABLE_GEN) | $(BUILD_DIR)
	@echo "  GEN     $@"
	$(Q)cd $(BUILD_DIR) && $(FLASH_TABLE_GEN)

# Compress the flash table so BL2 can store it alongside the other lzma
# segments.
$(FLASH_TABLE_LZMA): $(FLASH_TABLE_BIN)
	@echo "  LZMA    $@"
	$(Q)$(LZMA) e $(FLASH_TABLE_BIN) $(FLASH_TABLE_LZMA)

bl2: check-bl2-inputs $(BL2_BIN)

# Combine the four input segments into bl2.bin and append the CRC trailer
# expected by BootROM. Intermediate flash_table artifacts are removed once
# they have been folded into the final image.
$(BL2_BIN): $(FLASH_TABLE_LZMA) $(BL21_BIN) $(BL22_LZMA) $(BL23_LZMA) | $(BUILD_DIR)
	@echo "  TRX -z  $@"
	$(Q)$(TRX) -z $(BL21_BIN) $(BL22_LZMA) $(BL23_LZMA) $(FLASH_TABLE_LZMA) $(BL2_BIN)
	@echo "  TRX -x  $@ (CRC)"
	$(Q)cp $(BL2_BIN) $(BUILD_DIR)/bl2.tmp
	$(Q)$(TRX) -x $(BUILD_DIR)/bl2.tmp $(BUILD_DIR)/bl2_crc.bin
	$(Q)mv $(BUILD_DIR)/bl2_crc.bin $(BL2_BIN)
	$(Q)rm -f $(BUILD_DIR)/bl2.tmp $(FLASH_TABLE_BIN) $(FLASH_TABLE_LZMA)
	@echo "  DONE    $(BL2_BIN)"

# ---- BL31 lzma compression --------------------------------------------------
bl31: check-bl31-inputs $(BL31_LZMA)

$(BL31_LZMA): $(BL31_BIN) | $(BUILD_DIR)
	@echo "  LZMA    $@"
	$(Q)$(LZMA) e $(BL31_BIN) $(BL31_LZMA)
	@echo "  DONE    $(BL31_LZMA)"

# ---- Cleanup ----------------------------------------------------------------
clean:
	$(Q)rm -rf $(TOP_DIR)/build
	$(Q)$(MAKE) -C $(FLASH_TABLE_DIR) TOP_DIR=$(TOP_DIR) clean

distclean: clean
	$(Q)$(MAKE) -C $(TOOLS_DIR)/trx clean || true
